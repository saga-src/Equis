import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/infrastructure/cloud/supabase_cloud_auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('EQUIS_SUPABASE_URL');
const _publishableKey = String.fromEnvironment('EQUIS_SUPABASE_ANON_KEY');
const _configured = _url != '' && _publishableKey != '';

void main() {
  test(
    'configured project rejects invalid credentials through the real gateway',
    () async {
      final client = SupabaseClient(
        _url,
        _publishableKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        SupabaseCloudAuthGateway(client).signIn(
          email: 'missing-equis-live-smoke@example.invalid',
          password: 'not-a-real-equis-password',
        ),
        throwsA(
          isA<CloudAuthFailure>().having(
            (failure) => failure.code,
            'safe failure code',
            CloudAuthFailureCode.invalidCredentials,
          ),
        ),
      );
    },
    skip: _configured
        ? false
        : 'Pass EQUIS_SUPABASE_URL and EQUIS_SUPABASE_ANON_KEY with '
              '--dart-define-from-file to run this live smoke test.',
  );
}
