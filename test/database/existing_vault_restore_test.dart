import 'dart:io';

import 'package:equis/application/ports/cloud_identity_ports.dart';
import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/application/ports/vault_recovery_ports.dart';
import 'package:equis/application/services/cloud_account_service.dart';
import 'package:equis/application/services/existing_vault_restore_service.dart';
import 'package:equis/application/services/sync_coordinator.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/local_database_lifecycle.dart';
import 'package:equis/infrastructure/persistence/database/secure_storage_local_database_key_provider.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/security/vault_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fresh device authenticates, adopts recovered key, and starts pull',
    () async {
      const vaultId = '01900000-0000-7000-8000-000000000099';
      final remoteKeys = VaultKeyManager(store: _MemorySecureStore());
      await remoteKeys.loadOrCreateMasterKey();
      final package = await VaultRecoveryService(
        keys: remoteKeys,
      ).create(vaultId: vaultId);

      final directory = await Directory.systemTemp.createTemp(
        'equis-existing-restore-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final localKeys = VaultKeyManager(store: _MemorySecureStore());
      final lifecycle = EncryptedDriftDatabaseLifecycle(
        file: File('${directory.path}${Platform.pathSeparator}vault.db'),
        keyProvider: SecureStorageLocalDatabaseKeyProvider(
          keyManager: localKeys,
        ),
      );
      await lifecycle.initialize();
      addTearDown(lifecycle.close);
      final cloud = _CloudGateway();
      final runner = _SyncRunner();
      final coordinator = SyncCoordinator(engine: runner);
      addTearDown(coordinator.dispose);
      final service = ExistingVaultRestoreService(
        accounts: CloudAccountService(
          repository: _IdentityRepository(),
          auth: _AuthGateway(),
          deviceName: 'Test Windows',
          platform: 'windows',
        ),
        discovery: _Discovery(package.record.toCloudColumns()),
        recovery: VaultRecoveryService(keys: localKeys),
        lifecycle: lifecycle,
        database: lifecycle.database,
        cloud: cloud,
        coordinator: coordinator,
        deviceName: 'Test Windows',
        platform: 'windows',
      );

      final result = await service.restore(
        email: 'person@example.com',
        password: 'correct-password',
        recoverySecret: package.secret.export(),
        now: const UtcInstant.fromEpochMicroseconds(10),
      );

      expect(result.vaultId.value, vaultId);
      expect(result.sync.status, SyncRunStatus.succeeded);
      expect(cloud.ensuredVaultId, vaultId);
      expect(runner.vaultId, vaultId);
      expect(
        await (await localKeys.loadMasterKey(1)).extractBytes(),
        await (await remoteKeys.loadMasterKey(1)).extractBytes(),
      );
      final binding = await lifecycle.database
          .customSelect(
            'SELECT auth_user_id, sync_enabled FROM vault_cloud_bindings',
          )
          .getSingle();
      expect(binding.read<String>('auth_user_id'), _AuthGateway.userId);
      expect(binding.read<int>('sync_enabled'), 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final class _MemorySecureStore implements SecureStringStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _Discovery implements CloudVaultRecoveryDiscoveryGateway {
  const _Discovery(this.record);
  final Map<String, Object> record;

  @override
  Future<List<Map<String, Object>>> listAccessibleWrappedRecords() async => [
    record,
  ];
}

final class _AuthGateway implements CloudAuthGateway {
  static const userId = '11111111-1111-4111-8111-111111111111';

  @override
  String? get currentAccessToken => 'token';

  @override
  CloudAuthIdentity? get currentIdentity => null;

  @override
  Stream<CloudAuthIdentity?> get identityChanges => const Stream.empty();

  @override
  Future<void> resendVerification(String email) async {}

  @override
  Future<CloudAuthIdentity> signIn({
    required String email,
    required String password,
  }) async => const CloudAuthIdentity(
    authUserId: userId,
    email: 'person@example.com',
    emailVerified: true,
    hasActiveSession: true,
  );

  @override
  Future<CloudAuthIdentity> signUp({
    required String email,
    required String password,
  }) => signIn(email: email, password: password);

  @override
  Future<void> signOut() async {}
}

final class _IdentityRepository implements CloudIdentityRepository {
  @override
  Future<LocalDeviceIdentity?> findDevice(EntityId vaultId) async => null;

  @override
  Future<VaultCloudBinding?> findBinding(EntityId vaultId) async => null;

  @override
  Future<void> saveBinding(VaultCloudBinding binding) async {}

  @override
  Future<void> saveDevice(LocalDeviceIdentity device) async {}
}

final class _CloudGateway implements CloudSyncGateway {
  String? ensuredVaultId;

  @override
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  }) async => ensuredVaultId = vaultId;

  @override
  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  }) async {}

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
  }) async => const [];

  @override
  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  }) async => const [];
}

final class _SyncRunner implements SyncRunner {
  String? vaultId;

  @override
  Future<SyncRunResult> synchronize({
    required String vaultId,
    required String deviceId,
  }) async {
    this.vaultId = vaultId;
    return const SyncRunResult(status: SyncRunStatus.succeeded, pulled: 4);
  }
}
