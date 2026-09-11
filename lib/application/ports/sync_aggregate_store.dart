import '../sync/sync_models.dart';

final class SyncReconciliation {
  const SyncReconciliation({
    this.outboxChanged = false,
    this.remoteApplied = false,
    this.sentConfirmed = false,
    this.conflictDetected = false,
  });
  final bool outboxChanged, remoteApplied, sentConfirmed, conflictDetected;
}

abstract interface class SyncAggregateStore {
  /// Atomically compares the current local revision with authenticated remote
  /// data, applies the winner and retires any previous review for this record.
  /// Returns true when the outbox changed and another push may make progress.
  Future<SyncReconciliation> reconcileRemote({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
    required int serverVersion,
    required bool isDeleted,
    required Map<String, Object?> payload,
  });

  Future<Map<String, Object?>?> loadPayload({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  });

  Future<void> applyRemote({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
    required int serverVersion,
    required bool isDeleted,
    required Map<String, Object?> payload,
  });

  Future<void> applyMerged({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int remoteRevision,
    required int serverVersion,
    required Map<String, Object?> remoteSnapshot,
    required Map<String, Object?> mergedSnapshot,
  });

  Future<void> preserveConflict({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int baseRevision,
    required int localRevision,
    required int remoteRevision,
    required int serverVersion,
    required Map<String, Object?> baseSnapshot,
    required Map<String, Object?> localSnapshot,
    required Map<String, Object?> remoteSnapshot,
  });
}
