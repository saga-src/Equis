import '../../domain/cloud/cloud_identity_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../infrastructure/persistence/database/equis_database.dart';
import '../../infrastructure/persistence/database/local_database_lifecycle.dart';
import '../../infrastructure/security/vault_recovery_service.dart';
import '../ports/cloud_sync_gateway.dart';
import '../ports/vault_recovery_ports.dart';
import 'cloud_account_service.dart';
import 'sync_coordinator.dart';
import 'sync_engine.dart';

enum ExistingVaultRestoreFailureCode {
  unavailable,
  noVault,
  multipleVaults,
  invalidRecoverySecret,
  localVaultExists,
  synchronization,
}

final class ExistingVaultRestoreFailure implements Exception {
  const ExistingVaultRestoreFailure(this.code);
  final ExistingVaultRestoreFailureCode code;
}

final class ExistingVaultRestoreResult {
  const ExistingVaultRestoreResult({
    required this.vaultId,
    required this.deviceId,
    required this.sync,
  });
  final EntityId vaultId;
  final EntityId deviceId;
  final SyncRunResult sync;
}

final class ExistingVaultRestoreService {
  const ExistingVaultRestoreService({
    required this.accounts,
    required this.discovery,
    required this.recovery,
    required this.lifecycle,
    required this.database,
    required this.cloud,
    required this.coordinator,
    required this.deviceName,
    required this.platform,
  });

  final CloudAccountService accounts;
  final CloudVaultRecoveryDiscoveryGateway discovery;
  final VaultRecoveryService recovery;
  final EncryptedDriftDatabaseLifecycle lifecycle;
  final EquisDatabase database;
  final CloudSyncGateway cloud;
  final SyncCoordinator coordinator;
  final String deviceName;
  final String platform;

  Future<ExistingVaultRestoreResult> restore({
    required String email,
    required String password,
    required String recoverySecret,
    required UtcInstant now,
  }) async {
    if (await _hasLocalVault()) {
      throw const ExistingVaultRestoreFailure(
        ExistingVaultRestoreFailureCode.localVaultExists,
      );
    }
    final CloudAuthIdentity identity = await accounts.authenticateExisting(
      email: email,
      password: password,
    );
    final rows = await discovery.listAccessibleWrappedRecords();
    if (rows.isEmpty) {
      throw const ExistingVaultRestoreFailure(
        ExistingVaultRestoreFailureCode.noVault,
      );
    }
    final normalizedRecoverySecret = recoverySecret.trim();
    VaultRecoveryRecord? record;
    for (final row in rows) {
      final candidate = VaultRecoveryRecord.fromCloudColumns(row);
      try {
        final masterKey = await recovery.recover(
          record: candidate,
          recoverySecret: normalizedRecoverySecret,
        );
        await lifecycle.replaceKeyForEmptyDatabase(
          version: candidate.keyVersion,
          masterKey: masterKey,
        );
        record = candidate;
        break;
      } on RecoveryAuthenticationException {
        // A recovery secret is bound to one vault. Try the remaining vaults
        // accessible to this account until the matching record is found.
      } on RecoveryFormatException {
        throw const ExistingVaultRestoreFailure(
          ExistingVaultRestoreFailureCode.invalidRecoverySecret,
        );
      }
    }
    if (record == null) {
      throw const ExistingVaultRestoreFailure(
        ExistingVaultRestoreFailureCode.invalidRecoverySecret,
      );
    }

    final vaultId = EntityId.parse(record.vaultId);
    final deviceId = EntityId.generate();
    await _prepareEmptyLocalReplica(
      vaultId: vaultId,
      deviceId: deviceId,
      authUserId: identity.authUserId,
      now: now,
    );
    await cloud.ensureVaultAndDevice(
      vaultId: vaultId.value,
      deviceId: deviceId.value,
    );
    final sync = await coordinator.start(
      vaultId: vaultId.value,
      deviceId: deviceId.value,
    );
    if (sync.status == SyncRunStatus.permanentFailure) {
      throw const ExistingVaultRestoreFailure(
        ExistingVaultRestoreFailureCode.synchronization,
      );
    }
    return ExistingVaultRestoreResult(
      vaultId: vaultId,
      deviceId: deviceId,
      sync: sync,
    );
  }

  Future<bool> _hasLocalVault() async {
    final result = await database
        .customSelect('SELECT 1 FROM vaults LIMIT 1')
        .getSingleOrNull();
    return result != null;
  }

  Future<void> _prepareEmptyLocalReplica({
    required EntityId vaultId,
    required EntityId deviceId,
    required String authUserId,
    required UtcInstant now,
  }) => database.transaction(() async {
    await database.customStatement(
      'INSERT OR IGNORE INTO currencies '
      '(code, name_key, symbol, minor_units) VALUES (?, ?, ?, ?)',
      ['BRL', 'currency.brl', r'R$', 2],
    );
    await database.customStatement(
      'INSERT OR IGNORE INTO currencies '
      '(code, name_key, symbol, minor_units) VALUES (?, ?, ?, ?)',
      ['USD', 'currency.usd', r'US$', 2],
    );
    await database.customStatement(
      'INSERT INTO vaults '
      '(id, name, base_currency_code, locale, timezone, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        vaultId.value,
        'Equis',
        'BRL',
        'en-US',
        'UTC',
        now.epochMicroseconds,
        now.epochMicroseconds,
      ],
    );
    await database.customStatement(
      'INSERT INTO devices '
      '(id, vault_id, name, platform, created_at, last_seen_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        deviceId.value,
        vaultId.value,
        deviceName,
        platform,
        now.epochMicroseconds,
        now.epochMicroseconds,
      ],
    );
    await database.customStatement(
      'INSERT INTO vault_cloud_bindings '
      '(vault_id, auth_user_id, sync_enabled, linked_at) '
      'VALUES (?, ?, 1, ?)',
      [vaultId.value, authUserId, now.epochMicroseconds],
    );
  });
}
