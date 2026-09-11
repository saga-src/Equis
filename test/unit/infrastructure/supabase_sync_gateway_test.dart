import 'dart:convert';

import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/infrastructure/cloud/supabase_sync_gateway.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final entry in {
    'PGRST301': CloudSyncFailureCode.sessionExpired,
    'PGRST202': CloudSyncFailureCode.incompatibleServer,
    '42501': CloudSyncFailureCode.accessDenied,
  }.entries) {
    test('classifies ${entry.key} without leaking server details', () async {
      final gateway = _gateway(
        (request) async => http.Response(
          jsonEncode({'code': entry.key, 'message': 'private server detail'}),
          400,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        gateway.ensureVaultAndDevice(vaultId: 'vault', deviceId: 'device'),
        throwsA(
          isA<CloudSyncFailure>()
              .having((error) => error.code, 'code', entry.value)
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('private')),
              ),
        ),
      );
    });
  }

  const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const record = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  const operation = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';

  test('push sends encrypted bytes and parses accepted replay', () async {
    late http.Request sent;
    final gateway = _gateway((request) async {
      sent = request;
      return http.Response(
        '[{"operation_id":"$operation","status":"accepted",'
        '"revision":2,"server_version":7,"idempotent_replay":true}]',
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await gateway.pushBatch(
      vaultId: vault,
      mutations: [
        CloudSyncMutation(
          operationId: operation,
          expectedRevision: 1,
          record: _encrypted(vault, record, 2),
        ),
      ],
    );

    expect(sent.url.path, '/rest/v1/rpc/apply_sync_batch');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    final mutation =
        (body['p_mutations'] as List).single as Map<String, dynamic>;
    expect(mutation.keys, {
      'operation_id',
      'entity_type',
      'record_id',
      'expected_revision',
      'new_revision',
      'cipher_version',
      'nonce_hex',
      'ciphertext_hex',
      'is_deleted',
    });
    expect(sent.body, isNot(contains('merchant')));
    expect(result.single.status, CloudPushStatus.accepted);
    expect(result.single.idempotentReplay, isTrue);
    expect(result.single.serverVersion, 7);
  });

  test('pull is ascending after the durable cursor and parses bytea', () async {
    late http.Request sent;
    final encrypted = _encrypted(vault, record, 4);
    final gateway = _gateway((request) async {
      sent = request;
      return http.Response(
        jsonEncode([
          {
            'vault_id': vault,
            'entity_type': 'transaction',
            'record_id': record,
            'revision': 4,
            'server_version': 12,
            'cipher_version': 1,
            'nonce': '\\x${_hex(encrypted.envelope.nonce)}',
            'ciphertext': '\\x${_hex(encrypted.envelope.cloudCiphertext)}',
            'is_deleted': false,
          },
        ]),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await gateway.pull(vaultId: vault, afterServerVersion: 10);

    expect(sent.url.query, contains('server_version=gt.10'));
    expect(sent.url.query, contains('order=server_version.asc'));
    expect(result.single.serverVersion, 12);
    expect(
      result.single.record.envelope.cloudCiphertext,
      encrypted.envelope.cloudCiphertext,
    );
  });
}

SupabaseSyncGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'publishable-key',
    httpClient: MockClient(handler),
  );
  addTearDown(client.dispose);
  return SupabaseSyncGateway(client);
}

EncryptedSyncRecord _encrypted(String vault, String record, int revision) =>
    EncryptedSyncRecord(
      identity: SyncRecordIdentity(
        vaultId: vault,
        recordId: record,
        entityType: 'transaction',
        revision: revision,
      ),
      envelope: EncryptedPayloadEnvelope(
        cipherVersion: 1,
        keyVersion: 1,
        nonce: List<int>.generate(24, (i) => i),
        cipherText: [1, 2, 3, 4],
        mac: List<int>.filled(16, 9),
      ),
    );

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
