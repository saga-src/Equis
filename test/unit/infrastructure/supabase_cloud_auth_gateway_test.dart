import 'dart:convert';

import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/infrastructure/cloud/supabase_cloud_auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('email sign-up returns verification-pending identity only', () async {
    late http.Request sent;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'publishable-key',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'id': '11111111-1111-4111-8111-111111111111',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'person@example.com',
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
            'created_at': '2026-08-22T12:00:00Z',
            'updated_at': '2026-08-22T12:00:00Z',
            'confirmation_sent_at': '2026-08-22T12:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    final identity = await SupabaseCloudAuthGateway(
      client,
    ).signUp(email: 'person@example.com', password: 'long-test-password');

    expect(sent.url.path, '/auth/v1/signup');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['email'], 'person@example.com');
    expect(body['password'], 'long-test-password');
    expect(body.toString(), isNot(contains('transaction')));
    expect(body.toString(), isNot(contains('vault')));
    expect(identity.emailVerified, isFalse);
    expect(identity.hasActiveSession, isFalse);
  });

  test('provider error codes become safe application failure codes', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'publishable-key',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error_code":"email_not_confirmed","msg":"Email not confirmed"}',
          400,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseCloudAuthGateway(
        client,
      ).signIn(email: 'person@example.com', password: 'long-test-password'),
      throwsA(
        isA<CloudAuthFailure>().having(
          (value) => value.code,
          'code',
          CloudAuthFailureCode.emailNotVerified,
        ),
      ),
    );
  });
}
