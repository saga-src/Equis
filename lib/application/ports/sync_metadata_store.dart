import '../sync/sync_models.dart';

abstract interface class SyncMetadataStore {
  Future<void> enqueue({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int? baseRevision,
    required Map<String, Object?>? baseSnapshot,
    required int newRevision,
    required SyncOperation operation,
  });

  Future<List<PendingSyncMutation>> readyMutations({
    required String vaultId,
    required int nowMicros,
    int limit = 50,
  });

  Future<PendingSyncMutation?> pendingFor({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  });

  Future<void> markAccepted({
    required String operationId,
    required int revision,
    required int serverVersion,
    required int nowMicros,
  });

  Future<void> markFailed({
    required String operationId,
    required int nextRetryAtMicros,
    required String errorCode,
  });

  Future<void> markPermanentFailure({
    required String operationId,
    required String errorCode,
  });

  Future<SyncCursorValue> cursor(String vaultId);

  Future<void> advanceCursor({
    required String vaultId,
    required int serverVersion,
    required int nowMicros,
  });
}

final class SyncDiagnostics {
  const SyncDiagnostics({
    this.pending = 0,
    this.lastSuccess,
    this.sent24h = 0,
    this.received24h = 0,
    this.conflicts24h = 0,
  });
  final int pending;
  final int sent24h;
  final int received24h;
  final int conflicts24h;
  final DateTime? lastSuccess;
}

abstract interface class SyncDiagnosticsStore {
  Future<SyncDiagnostics> diagnostics(String vaultId);
  Future<void> retryPending(String vaultId);
  Future<void> retryTransient(String vaultId);
  Future<void> recordSuccess(String vaultId, int nowMicros);
}
