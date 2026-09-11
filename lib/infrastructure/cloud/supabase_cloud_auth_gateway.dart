import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/ports/cloud_identity_ports.dart';
import '../../domain/cloud/cloud_identity_models.dart';

final class SupabaseCloudAuthGateway implements CloudAuthGateway {
  const SupabaseCloudAuthGateway(this.client);
  final SupabaseClient client;

  @override
  CloudAuthIdentity? get currentIdentity => _identity(
    client.auth.currentUser,
    hasSession: client.auth.currentSession != null,
  );

  @override
  String? get currentAccessToken => client.auth.currentSession?.accessToken;

  @override
  Stream<CloudAuthIdentity?> get identityChanges =>
      client.auth.onAuthStateChange.map(
        (state) =>
            _identity(state.session?.user, hasSession: state.session != null),
      );

  @override
  Future<CloudAuthIdentity> signUp({
    required String email,
    required String password,
  }) => _translate(() async {
    final response = await client.auth.signUp(email: email, password: password);
    return _requiredIdentity(response);
  });

  @override
  Future<CloudAuthIdentity> signIn({
    required String email,
    required String password,
  }) => _translate(() async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _requiredIdentity(response);
  });

  @override
  Future<void> resendVerification(String email) => _translate(
    () => client.auth.resend(email: email, type: OtpType.signup).then((_) {}),
  );

  @override
  Future<void> signOut() => _translate(client.auth.signOut);

  CloudAuthIdentity _requiredIdentity(AuthResponse response) {
    final value = _identity(
      response.user,
      hasSession: response.session != null,
    );
    if (value == null) {
      throw const CloudAuthFailure(CloudAuthFailureCode.unknown);
    }
    return value;
  }
}

CloudAuthIdentity? _identity(User? user, {required bool hasSession}) {
  if (user == null) return null;
  return CloudAuthIdentity(
    authUserId: user.id,
    email: user.email ?? '',
    emailVerified: user.emailConfirmedAt != null,
    hasActiveSession: hasSession,
  );
}

Future<T> _translate<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on CloudAuthFailure {
    rethrow;
  } on AuthException catch (error) {
    throw CloudAuthFailure(_code(error));
  } on Exception {
    throw const CloudAuthFailure(CloudAuthFailureCode.network);
  }
}

CloudAuthFailureCode _code(AuthException error) => switch (error.code) {
  'invalid_credentials' => CloudAuthFailureCode.invalidCredentials,
  'email_not_confirmed' => CloudAuthFailureCode.emailNotVerified,
  'weak_password' => CloudAuthFailureCode.weakPassword,
  'user_already_exists' ||
  'email_exists' => CloudAuthFailureCode.accountAlreadyExists,
  'over_email_send_rate_limit' ||
  'over_request_rate_limit' => CloudAuthFailureCode.rateLimited,
  _ =>
    error.statusCode == null
        ? CloudAuthFailureCode.network
        : CloudAuthFailureCode.unknown,
};
