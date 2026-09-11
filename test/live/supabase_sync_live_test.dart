import 'dart:convert';

import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/infrastructure/cloud/supabase_sync_gateway.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('EQUIS_SUPABASE_URL');
const _publishableKey = String.fromEnvironment('EQUIS_SUPABASE_ANON_KEY');
const _email = String.fromEnvironment('EQUIS_SUPABASE_TEST_EMAIL');
const _password = String.fromEnvironment('EQUIS_SUPABASE_TEST_PASSWORD');
const _configured =
    _url != '' && _publishableKey != '' && _email != '' && _password != '';

void main() {
  test(
    'hosted schema accepts only authenticated encrypted cursor sync',
    () async {
      final client = SupabaseClient(
        _url,
        _publishableKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      addTearDown(client.dispose);
      final auth = await client.auth.signInWithPassword(
        email: _email,
        password: _password,
      );
      final userId = auth.user!.id.replaceAll('-', '');
      final suffix = userId.substring(0, 12);
      final vaultId = '018f47c2-9b72-7cc1-8b83-$suffix';
      final deviceId = '018f47c2-9b72-7cc2-8b83-$suffix';
      final recordId = '018f47c2-9b72-7cc3-8b83-$suffix';
      final operationId = '018f47c2-9b72-7cc4-8b83-$suffix';
      final gateway = SupabaseSyncGateway(client);
      await gateway.ensureVaultAndDevice(vaultId: vaultId, deviceId: deviceId);

      final cipher = SyncPayloadCipher(
        keys: VaultKeyManager(
          store: _MemoryStore(
            base64UrlEncode(List<int>.generate(32, (index) => index)),
          ),
        ),
      );
      final identity = SyncRecordIdentity(
        vaultId: vaultId,
        recordId: recordId,
        entityType: 'transaction',
        revision: 1,
      );
      final encrypted = EncryptedSyncRecord(
        identity: identity,
        envelope: await cipher.encrypt(
          identity: identity,
          payload: const {
            'format_version': 1,
            'merchant': 'must-remain-inside-ciphertext',
            'amount_minor': 12345,
          },
          nonce: List<int>.generate(24, (index) => index + 1),
        ),
      );
      final mutation = CloudSyncMutation(
        operationId: operationId,
        record: encrypted,
      );

      final first = await gateway.pushBatch(
        vaultId: vaultId,
        mutations: [mutation],
      );
      expect(first.single.status, CloudPushStatus.accepted);
      final replay = await gateway.pushBatch(
        vaultId: vaultId,
        mutations: [mutation],
      );
      expect(replay.single.idempotentReplay, isTrue);

      final pulled = await gateway.pull(
        vaultId: vaultId,
        afterServerVersion: 0,
      );
      final record = pulled.singleWhere(
        (item) => item.record.identity.recordId == recordId,
      );
      expect(
        await cipher.decrypt(
          identity: record.record.identity,
          envelope: record.record.envelope,
        ),
        containsPair('amount_minor', 12345),
      );
      await gateway.acknowledgeCursor(
        vaultId: vaultId,
        deviceId: deviceId,
        serverVersion: record.serverVersion,
      );

      final raw = await client
          .from('sync_records')
          .select()
          .eq('vault_id', vaultId)
          .eq('record_id', recordId)
          .single();
      expect(raw.keys.toSet(), {
        'vault_id',
        'entity_type',
        'record_id',
        'revision',
        'server_version',
        'cipher_version',
        'nonce',
        'ciphertext',
        'is_deleted',
        'updated_at',
      });
      expect(jsonEncode(raw), isNot(contains('must-remain-inside-ciphertext')));

      final device = await client
          .from('devices')
          .select('last_acknowledged_server_version')
          .eq('id', deviceId)
          .single();
      expect(device['last_acknowledged_server_version'], record.serverVersion);

      final anonymous = SupabaseClient(_url, _publishableKey);
      addTearDown(anonymous.dispose);
      await expectLater(
        SupabaseSyncGateway(
          anonymous,
        ).pull(vaultId: vaultId, afterServerVersion: 0),
        throwsA(
          isA<CloudSyncFailure>().having(
            (failure) => failure.code,
            'failure code',
            CloudSyncFailureCode.accessDenied,
          ),
        ),
      );
    },
    skip: _configured
        ? false
        : 'Pass URL, publishable key, confirmed test email, and test password '
              'through an ignored .dart-defines.sync.local.json file.',
  );
}

final class _MemoryStore implements SecureStringStore {
  _MemoryStore(String masterKey)
    : _values = {'equis.vault_master_key.v1': masterKey};

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
