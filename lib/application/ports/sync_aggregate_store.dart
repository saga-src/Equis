import 'cloud_sync_gateway.dart';
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

/// Allows an aggregate store to hold mutations behind a persisted conflict.
abstract interface class SyncPushEligibility {
  Future<bool> canPush({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  });
}

/// Commits an authenticated inbound record and, for ordered pull, its cursor
/// in one local unit. A conflict fetch must not skip other cloud records.
abstract interface class SyncAuthenticatedInboundStore {
  Future<int> unresolvedQuarantineCount(String vaultId);

  Future<SyncReconciliation> receiveCloudRecord({
    required CloudSyncRecord cloudRecord,
    required Map<String, Object?> payload,
    required int nowMicros,
    bool advanceCursor = true,
  });
}

/// Hydrates a complete authenticated first-pull snapshot atomically, preserving
/// archived accounts only after their historical dependencies are validated.
abstract interface class SyncBootstrapHistoryStore {
  Future<void> hydrateBootstrapHistory({
    required String vaultId,
    required int nowMicros,
    required Future<void> Function(bool hydrate) pull,
  });
}

final class AuthenticatedSyncReplay {
  const AuthenticatedSyncReplay({
    required this.cloudRecord,
    required this.payload,
  });
  final CloudSyncRecord cloudRecord;
  final Map<String, Object?> payload;
}

abstract interface class SyncQuarantineRecoveryStore {
  Future<List<CloudSyncRecord>> replayCandidates(String vaultId);
  Future<int> replayQuarantined({
    required List<AuthenticatedSyncReplay> records,
    required int nowMicros,
  });
}

final class AccountSyncRecoveryState {
  const AccountSyncRecoveryState({
    required this.accountId,
    required this.revision,
    required this.restorationPending,
  });

  final String accountId;
  final int revision;
  final bool restorationPending;
}

abstract interface class AccountSyncRecoveryStore {
  Future<List<AccountSyncRecoveryState>> accountRecoveryStates(String vaultId);
  Future<int> requestAccountRestore({
    required String vaultId,
    required String accountId,
    required int expectedRevision,
    required int nowMicros,
  });
}
