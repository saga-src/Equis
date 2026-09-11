import '../../application/ports/cloud_sync_gateway.dart';
import '../../application/ports/sync_enrollment_store.dart';
import '../../application/ports/vault_recovery_ports.dart';
import '../security/vault_recovery_service.dart';
import '../security/encrypted_payload_cipher.dart';

final class PreparedCloudSyncEnrollment {
  const PreparedCloudSyncEnrollment({
    required this.vaultId,
    required this.deviceId,
    required this.authUserId,
    required this.recoverySecret,
  });

  final String vaultId;
  final String deviceId;
  final String authUserId;
  final RecoverySecret recoverySecret;
}

final class CloudSyncEnrollmentService {
  const CloudSyncEnrollmentService({
    required this.cloud,
    required this.recoveryGateway,
    required this.recovery,
    required this.local,
  });

  final CloudSyncGateway cloud;
  final VaultRecoveryRecordGateway recoveryGateway;
  final VaultRecoveryService recovery;
  final SyncEnrollmentStore local;

  Future<bool> resumeExisting({
    required String vaultId,
    required String deviceId,
    required String authUserId,
  }) async {
    if (recovery.keys.protocolVersion == 2) {
      final identity = await recovery.keys.requireVault(vaultId);
      if (identity.ownerId != null && identity.ownerId != authUserId) {
        throw const CloudSyncFailure(CloudSyncFailureCode.accessDenied);
      }
      await cloud.ensureVaultAndDevice(vaultId: vaultId, deviceId: deviceId);
      await local.seedAndEnable(vaultId: vaultId, authUserId: authUserId);
      return true;
    }
    final existing = await recoveryGateway.fetchWrappedRecord(
      vaultId: vaultId,
      keyVersion: await recovery.keys.currentVersion(),
    );
    if (existing == null) return false;
    await cloud.ensureVaultAndDevice(vaultId: vaultId, deviceId: deviceId);
    final cipher = SyncPayloadCipher(keys: recovery.keys);
    var cursor = 0;
    var verified = false;
    while (true) {
      final records = await cloud.pull(
        vaultId: vaultId,
        afterServerVersion: cursor,
      );
      for (final record in records) {
        if (record.record.identity.vaultId != vaultId ||
            record.serverVersion <= cursor) {
          throw const CloudSyncFormatException();
        }
        await cipher.decrypt(
          identity: record.record.identity,
          envelope: record.record.envelope,
        );
        cursor = record.serverVersion;
        verified = true;
      }
      if (records.length < 100) break;
    }
    if (!verified) throw const PayloadAuthenticationException();
    await local.seedAndEnable(vaultId: vaultId, authUserId: authUserId);
    return true;
  }

  Future<PreparedCloudSyncEnrollment> prepare({
    required String vaultId,
    required String deviceId,
    required String authUserId,
  }) async {
    if (await recoveryGateway.fetchWrappedRecord(
          vaultId: vaultId,
          keyVersion: await recovery.keys.currentVersion(),
        ) !=
        null) {
      throw const PayloadAuthenticationException();
    }
    await cloud.ensureVaultAndDevice(vaultId: vaultId, deviceId: deviceId);
    final package = await recovery.create(vaultId: vaultId);
    await recoveryGateway.publishWrappedRecord(
      vaultId: vaultId,
      keyVersion: package.record.keyVersion,
      wrappedRecord: package.record.toCloudColumns(),
    );
    return PreparedCloudSyncEnrollment(
      vaultId: vaultId,
      deviceId: deviceId,
      authUserId: authUserId,
      recoverySecret: package.secret,
    );
  }

  Future<void> confirmRecoverySaved(PreparedCloudSyncEnrollment prepared) =>
      local.seedAndEnable(
        vaultId: prepared.vaultId,
        authUserId: prepared.authUserId,
      );
}
