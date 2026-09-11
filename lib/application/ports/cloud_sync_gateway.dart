import '../sync/encrypted_sync_models.dart';

final class CloudSyncMutation {
  const CloudSyncMutation({
    required this.operationId,
    required this.record,
    this.expectedRevision,
  });

  final String operationId;
  final EncryptedSyncRecord record;
  final int? expectedRevision;
}

enum CloudPushStatus { accepted, conflict }

final class CloudPushResult {
  const CloudPushResult({
    required this.operationId,
    required this.status,
    required this.serverVersion,
    this.revision,
    this.remoteRevision,
    this.idempotentReplay = false,
  });

  final String operationId;
  final CloudPushStatus status;
  final int? revision;
  final int? remoteRevision;
  final int? serverVersion;
  final bool idempotentReplay;
}

final class CloudSyncRecord {
  const CloudSyncRecord({required this.record, required this.serverVersion});
  final EncryptedSyncRecord record;
  final int serverVersion;
}

abstract interface class CloudSyncGateway {
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  });

  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  });

  Future<List<CloudSyncRecord>> pull({
    required String vaultId,
    required int afterServerVersion,
    int limit = 100,
  });

  Future<CloudSyncRecord?> fetch({
    required String vaultId,
    required String entityType,
    required String recordId,
  });

  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  });
}

abstract interface class CloudSyncWakeupGateway {
  Stream<void> wakeups({required String vaultId});
}

enum CloudSyncFailureCode {
  keyMismatch,
  clientObsolete,
  network,
  accessDenied,
  invalidMutation,
  remote,
  sessionExpired,
  incompatibleServer,
}

final class CloudSyncFailure implements Exception {
  const CloudSyncFailure(this.code);
  final CloudSyncFailureCode code;

  @override
  String toString() => 'Cloud synchronization request failed.';
}

final class CloudSyncFormatException implements Exception {
  const CloudSyncFormatException();

  @override
  String toString() => 'Cloud synchronization response is invalid.';
}
