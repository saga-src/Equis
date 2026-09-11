import 'dart:convert';

import 'package:drift/native.dart';
import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/application/ports/vault_recovery_ports.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/vault_recovery_service.dart';
import 'package:equis/infrastructure/sync/cloud_sync_enrollment_service.dart';
import 'package:equis/infrastructure/sync/drift_sync_enrollment_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftSyncMetadataStore metadata;
  late _RecoveryGateway recoveryGateway;
  late _Cloud cloud;
  late CloudSyncEnrollmentService service;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    metadata = DriftSyncMetadataStore(database);
    recoveryGateway = _RecoveryGateway();
    cloud = _Cloud();
    final keys = VaultKeyManager(
      store: _Store(base64UrlEncode(List<int>.generate(32, (i) => i))),
    );
    service = CloudSyncEnrollmentService(
      cloud: cloud,
      recoveryGateway: recoveryGateway,
      recovery: VaultRecoveryService(
        keys: keys,
        parameters: const RecoveryKdfParameters(memoryKiB: 32),
      ),
      local: DriftSyncEnrollmentStore(database: database, metadata: metadata),
    );
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
      [_vault],
    );
    await database.customStatement(
      "INSERT INTO tags (id, vault_id, name, created_at, updated_at) VALUES (?, ?, 'Local', 1, 1)",
      [_tag, _vault],
    );
    await database.customStatement(
      'INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, ?, 0, 1)',
      [_vault, _user],
    );
  });
  tearDown(() => database.close());

  test(
    'v2 binds after verified registration and repeated enrollment preserves operation IDs',
    () async {
      await database.customStatement('DELETE FROM vault_cloud_bindings');
      final keys = VaultKeyManager(store: _Store(''), protocolVersion: 2);
      await keys.ensureVault(_vault);
      final v2 = CloudSyncEnrollmentService(
        cloud: cloud,
        recoveryGateway: recoveryGateway,
        recovery: VaultRecoveryService(keys: keys),
        local: DriftSyncEnrollmentStore(
          database: database,
          metadata: metadata,
          allowVerifiedOwnerBinding: true,
        ),
      );
      await v2.resumeExisting(
        vaultId: _vault,
        deviceId: _device,
        authUserId: _user,
      );
      expect(cloud.ensured, isTrue);
      expect(recoveryGateway.record, isNull);
      final operations =
          (await database
                  .customSelect(
                    'SELECT operation_id FROM sync_outbox ORDER BY operation_id',
                  )
                  .get())
              .map((row) => row.read<String>('operation_id'))
              .toList();
      expect(operations, isNotEmpty);
      await v2.resumeExisting(
        vaultId: _vault,
        deviceId: _device,
        authUserId: _user,
      );
      expect(
        (await database
                .customSelect(
                  'SELECT operation_id FROM sync_outbox ORDER BY operation_id',
                )
                .get())
            .map((row) => row.read<String>('operation_id'))
            .toList(),
        operations,
      );
      await expectLater(
        DriftSyncEnrollmentStore(
          database: database,
          metadata: metadata,
          allowVerifiedOwnerBinding: true,
        ).seedAndEnable(
          vaultId: _vault,
          authUserId: '22222222-2222-4222-8222-222222222222',
        ),
        throwsStateError,
      );
    },
  );

  test('enrollment enables only after recovery export is confirmed', () async {
    final prepared = await service.prepare(
      vaultId: _vault,
      deviceId: _device,
      authUserId: _user,
    );

    expect(cloud.ensured, isTrue);
    expect(recoveryGateway.record!.keys, {
      'vault_id',
      'wrapped_vault_key',
      'kdf',
      'kdf_parameters',
      'salt',
      'nonce',
      'key_version',
    });
    expect(
      recoveryGateway.record.toString(),
      isNot(contains(prepared.recoverySecret.export())),
    );
    expect(
      await database.customSelect('SELECT * FROM sync_outbox').get(),
      isEmpty,
    );
    final beforeConfirmation = await database
        .customSelect('SELECT sync_enabled FROM vault_cloud_bindings')
        .getSingle();
    expect(beforeConfirmation.read<int>('sync_enabled'), 0);

    await service.confirmRecoverySaved(prepared);

    final pending = await metadata.readyMutations(
      vaultId: _vault,
      nowMicros: 9999999999999999,
    );
    expect(
      pending.map((item) => item.entityType),
      containsAll([SyncEntityType.vault, SyncEntityType.tag]),
    );
    final binding = await database
        .customSelect('SELECT sync_enabled FROM vault_cloud_bindings')
        .getSingle();
    expect(binding.read<int>('sync_enabled'), 1);
  });

  test('remote recovery failure leaves sync disabled and unseeded', () async {
    recoveryGateway.fail = true;

    await expectLater(
      service.prepare(vaultId: _vault, deviceId: _device, authUserId: _user),
      throwsA(isA<CloudSyncFailure>()),
    );

    expect(
      await database.customSelect('SELECT * FROM sync_outbox').get(),
      isEmpty,
    );
    final binding = await database
        .customSelect('SELECT sync_enabled FROM vault_cloud_bindings')
        .getSingle();
    expect(binding.read<int>('sync_enabled'), 0);
  });

  test(
    'existing recovery is preserved and activation verifies remote encryption',
    () async {
      await service.prepare(
        vaultId: _vault,
        deviceId: _device,
        authUserId: _user,
      );
      final original = recoveryGateway.record;
      await expectLater(
        service.prepare(vaultId: _vault, deviceId: _device, authUserId: _user),
        throwsA(isA<PayloadAuthenticationException>()),
      );
      expect(recoveryGateway.record, same(original));
      cloud.records = [
        CloudSyncRecord(
          record: EncryptedSyncRecord(
            identity: SyncRecordIdentity(
              vaultId: _vault,
              recordId: _tag,
              entityType: 'tag',
              revision: 1,
            ),
            envelope: await SyncPayloadCipher(keys: service.recovery.keys)
                .encrypt(
                  identity: SyncRecordIdentity(
                    vaultId: _vault,
                    recordId: _tag,
                    entityType: 'tag',
                    revision: 1,
                  ),
                  payload: {'name': 'test'},
                ),
            isDeleted: false,
          ),
          serverVersion: 1,
        ),
      ];
      expect(
        await service.resumeExisting(
          vaultId: _vault,
          deviceId: _device,
          authUserId: _user,
        ),
        isTrue,
      );
      expect(recoveryGateway.record, same(original));
    },
  );
}

final class _Cloud implements CloudSyncGateway {
  bool ensured = false;
  List<CloudSyncRecord> records = [];
  @override
  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  }) async {}
  @override
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  }) async => ensured = true;
  @override
  Future<CloudSyncRecord?> fetch({
    required String vaultId,
    required String entityType,
    required String recordId,
  }) async => null;
  @override
  Future<List<CloudSyncRecord>> pull({
    required String vaultId,
    required int afterServerVersion,
    int limit = 100,
  }) async =>
      records.where((row) => row.serverVersion > afterServerVersion).toList();
  @override
  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  }) async => const [];
}

final class _RecoveryGateway implements VaultRecoveryRecordGateway {
  bool fail = false;
  Map<String, Object>? record;
  @override
  Future<Map<String, Object>?> fetchWrappedRecord({
    required String vaultId,
    required int keyVersion,
  }) async => record;
  @override
  Future<void> publishWrappedRecord({
    required String vaultId,
    required int keyVersion,
    required Map<String, Object> wrappedRecord,
  }) async {
    if (fail) throw const CloudSyncFailure(CloudSyncFailureCode.network);
    record = wrappedRecord;
  }
}

final class _Store implements SecureStringStore {
  _Store(String master) : values = {'equis.vault_master_key.v1': master};
  final Map<String, String> values;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const _tag = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
const _device = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
const _user = '11111111-1111-4111-8111-111111111111';
