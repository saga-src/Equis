import '../sync/sync_models.dart';

enum SyncConflictResolution { keepLocal, keepRemote, merged }

final class SyncConflictSummary {
  const SyncConflictSummary({
    required this.id,
    required this.vaultId,
    required this.entityType,
    required this.recordId,
    required this.baseRevision,
    required this.localRevision,
    required this.remoteRevision,
    required this.detectedAtMicros,
  });

  final String id;
  final String vaultId;
  final SyncEntityType entityType;
  final String recordId;
  final int baseRevision;
  final int localRevision;
  final int remoteRevision;
  final int detectedAtMicros;
}

abstract interface class SyncConflictResolver {
  Future<List<SyncConflictSummary>> unresolved(String vaultId);

  Future<void> resolve({
    required String conflictId,
    required SyncConflictResolution resolution,
    Map<String, Object?>? mergedSnapshot,
  });
}
