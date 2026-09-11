import 'package:drift/drift.dart';

import '../../application/sync/sync_models.dart';
import '../../application/services/sync_mutation_notifications.dart';
import '../persistence/database/equis_database.dart';
import 'drift_sync_aggregate_store.dart';
import 'drift_sync_metadata_store.dart';

final class DriftSyncMutationRecorder {
  const DriftSyncMutationRecorder({
    required this.database,
    required this.aggregates,
    required this.metadata,
    this.notifications,
  });

  final EquisDatabase database;
  final DriftSyncAggregateStore aggregates;
  final DriftSyncMetadataStore metadata;
  final SyncMutationNotifications? notifications;

  Future<T> run<T>({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int newRevision,
    required SyncOperation operation,
    required Future<T> Function() action,
  }) async {
    var enqueued = false;
    final result = await database.transaction(() async {
      final enabled = await _syncEnabled(vaultId);
      final base = enabled
          ? await aggregates.loadPayload(
              vaultId: vaultId,
              entityType: entityType,
              recordId: recordId,
            )
          : null;
      final result = await action();
      if (!enabled) return result;
      final written = await aggregates.loadPayload(
        vaultId: vaultId,
        entityType: entityType,
        recordId: recordId,
      );
      final root = written?['root'];
      if (root is! Map || root['revision'] != newRevision) {
        throw StateError(
          'The sync aggregate revision does not match the mutation.',
        );
      }
      final baseRoot = base?['root'];
      final baseRevision = baseRoot is Map
          ? baseRoot['revision'] as int?
          : null;
      await metadata.enqueue(
        vaultId: vaultId,
        entityType: entityType,
        recordId: recordId,
        baseRevision: baseRevision,
        baseSnapshot: base,
        newRevision: newRevision,
        operation: operation,
      );
      enqueued = true;
      return result;
    });
    if (enqueued) notifications?.notify(vaultId);
    return result;
  }

  Future<bool> _syncEnabled(String vaultId) async {
    final row = await database
        .customSelect(
          'SELECT sync_enabled FROM vault_cloud_bindings WHERE vault_id = ?',
          variables: [Variable(vaultId)],
        )
        .getSingleOrNull();
    return row?.read<int>('sync_enabled') == 1;
  }
}
