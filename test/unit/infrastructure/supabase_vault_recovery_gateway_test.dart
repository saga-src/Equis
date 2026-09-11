import 'dart:convert';
import 'dart:typed_data';

import 'package:equis/infrastructure/cloud/supabase_vault_recovery_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';

  test('publishes only wrapped recovery material', () async {
    late http.Request sent;
    final gateway = _gateway((request) async {
      sent = request;
      return http.Response(
        '{}',
        201,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    final record = _record(vault);

    await gateway.publishWrappedRecord(
      vaultId: vault,
      keyVersion: 1,
      wrappedRecord: record,
    );

    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body.keys, record.keys);
    expect(body['wrapped_vault_key'], startsWith(r'\x'));
    expect(sent.body, isNot(contains('recovery_secret')));
    expect(sent.body, isNot(contains('vault_master_key')));
    expect(sent.headers['prefer'] ?? '', isNot(contains('merge-duplicates')));
    expect(sent.url.queryParameters, isNot(contains('on_conflict')));
  });

  test(
    'fetch parses PostgreSQL bytea without adding plaintext fields',
    () async {
      final gateway = _gateway((request) async {
        final body = _record(vault).map(
          (key, value) =>
              MapEntry(key, value is Uint8List ? '\\x${_hex(value)}' : value),
        );
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await gateway.fetchWrappedRecord(
        vaultId: vault,
        keyVersion: 1,
      );

      expect(result!.keys, _record(vault).keys);
      expect(result['wrapped_vault_key'], isA<Uint8List>());
      expect((result['wrapped_vault_key']! as Uint8List), hasLength(48));
    },
  );
}

SupabaseVaultRecoveryGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'publishable-key',
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return SupabaseVaultRecoveryGateway(client);
}

Map<String, Object> _record(String vault) => {
  'vault_id': vault,
  'wrapped_vault_key': Uint8List(48),
  'kdf': 'argon2id',
  'kdf_parameters': const {'memory_kib': 19456, 'iterations': 2},
  'salt': Uint8List(16),
  'nonce': Uint8List(24),
  'key_version': 1,
};

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
