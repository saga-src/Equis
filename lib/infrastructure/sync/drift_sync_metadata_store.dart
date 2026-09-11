import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/ports/sync_metadata_store.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';
import '../security/canonical_json.dart';

final class DriftSyncMetadataStore
    implements SyncMetadataStore, SyncDiagnosticsStore {
  const DriftSyncMetadataStore(this.database, {this.clock = DateTime.now});
  final EquisDatabase database;
  final DateTime Function() clock;

  Future<void> recordActivity({
    required String vaultId,
    required String entityType,
    required String recordId,
    required String kind,
    required int localRevision,
    required int remoteRevision,
    int? nowMicros,
  }) => database.customStatement(
    'INSERT OR IGNORE INTO sync_activity_events '
    '(vault_id, entity_type, record_id, kind, local_revision, remote_revision, occurred_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      vaultId,
      entityType,
      recordId,
      kind,
      localRevision,
      remoteRevision,
      nowMicros ?? clock().toUtc().microsecondsSinceEpoch,
    ],
  );

  @override
  Future<SyncDiagnostics> diagnostics(String vaultId) async {
    final now = clock().toUtc().microsecondsSinceEpoch;
    await database.customStatement(
      'DELETE FROM sync_activity_events WHERE occurred_at < ?',
      [now - const Duration(days: 7).inMicroseconds],
    );
    final activity = await database
        .customSelect(
          'SELECT kind, COUNT(*) AS n FROM sync_activity_events '
          'WHERE vault_id = ? AND occurred_at > ? AND occurred_at <= ? GROUP BY kind',
          variables: [
            Variable(vaultId),
            Variable(now - const Duration(hours: 24).inMicroseconds),
            Variable(now),
          ],
        )
        .get();
    final totals = {
      for (final r in activity) r.read<String>('kind'): r.read<int>('n'),
    };
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS n FROM sync_outbox WHERE vault_id = ?',
          variables: [Variable(vaultId)],
        )
        .getSingle();
    final value = await cursor(vaultId);
    return SyncDiagnostics(
      sent24h: totals['sent'] ?? 0,
      received24h: totals['received'] ?? 0,
      conflicts24h: totals['conflict'] ?? 0,
      pending: row.read<int>('n'),
      lastSuccess: value.lastSuccessAtMicros == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              value.lastSuccessAtMicros!,
              isUtc: true,
            ),
    );
  }

  @override
  Future<void> retryPending(String vaultId) => database.customStatement(
    'UPDATE sync_outbox SET next_retry_at = NULL WHERE vault_id = ?',
    [vaultId],
  );

  @override
  Future<void> retryTransient(String vaultId) => database.customStatement(
    'UPDATE sync_outbox SET next_retry_at = NULL WHERE vault_id = ? '
    'AND next_retry_at < ?',
    [vaultId, 0x7FFFFFFFFFFFFFFF],
  );

  @override
  Future<void> recordSuccess(
    String vaultId,
    int nowMicros,
  ) => database.customStatement(
    'INSERT INTO sync_cursors (vault_id, last_success_at) VALUES (?, ?) '
    'ON CONFLICT(vault_id) DO UPDATE SET last_success_at = excluded.last_success_at',
    [vaultId, nowMicros],
  );

  @override
  Future<void> enqueue({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int? baseRevision,
    required Map<String, Object?>? baseSnapshot,
    required int newRevision,
    required SyncOperation operation,
  }) async {
    if (newRevision < 1 || (baseRevision != null && baseRevision < 1)) {
      throw ArgumentError('Sync revisions must be positive.');
    }
    final existing = await database
        .customSelect(
          'SELECT operation_id, base_revision, base_snapshot, created_at '
          'FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ? '
          'ORDER BY created_at LIMIT 1',
          variables: [
            Variable(vaultId),
            Variable(entityType.wireName),
            Variable(recordId),
          ],
        )
        .getSingleOrNull();
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final operationId =
        existing?.read<String>('operation_id') ?? EntityId.generate().value;
    // A null base on an existing outbox row means creation has not been sent.
    // Preserve that null rather than replacing it with an intermediate edit.
    final retainedBaseRevision = existing != null
        ? existing.readNullable<int>('base_revision')
        : baseRevision;
    final retainedBase = existing != null
        ? existing.readNullable<String>('base_snapshot')
        : (baseSnapshot == null ? null : CanonicalJson.encode(baseSnapshot));

    await database.customStatement(
      'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? '
      'AND record_id = ?',
      [vaultId, entityType.wireName, recordId],
    );
    await database.customStatement(
      'INSERT INTO sync_outbox ('
      'operation_id, vault_id, entity_type, record_id, base_revision, '
      'base_snapshot, new_revision, operation, created_at, attempt_count'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
      [
        operationId,
        vaultId,
        entityType.wireName,
        recordId,
        retainedBaseRevision,
        retainedBase,
        newRevision,
        operation.name,
        existing?.read<int>('created_at') ?? now,
      ],
    );
    await database.customStatement(
      'INSERT INTO sync_entity_state ('
      'entity_type, record_id, local_revision, sync_state'
      ') VALUES (?, ?, ?, ?) '
      'ON CONFLICT(entity_type, record_id) DO UPDATE SET '
      'local_revision = excluded.local_revision, sync_state = excluded.sync_state',
      [
        entityType.wireName,
        recordId,
        newRevision,
        operation == SyncOperation.delete ? 'deleted_pending' : 'pending',
      ],
    );
  }

  @override
  Future<List<PendingSyncMutation>> readyMutations({
    required String vaultId,
    required int nowMicros,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit');
    }
    final rows = await database
        .customSelect(
          'SELECT * FROM sync_outbox WHERE vault_id = ? '
          'AND (next_retry_at IS NULL OR next_retry_at <= ?) '
          'ORDER BY created_at, operation_id LIMIT ?',
          variables: [Variable(vaultId), Variable(nowMicros), Variable(limit)],
        )
        .get();
    return rows.map(_readMutation).toList(growable: false);
  }

  @override
  Future<PendingSyncMutation?> pendingFor({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  }) async {
    final row = await database
        .customSelect(
          'SELECT * FROM sync_outbox WHERE vault_id = ? AND entity_type = ? '
          'AND record_id = ? ORDER BY created_at LIMIT 1',
          variables: [
            Variable(vaultId),
            Variable(entityType.wireName),
            Variable(recordId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _readMutation(row);
  }

  @override
  Future<void> markAccepted({
    required String operationId,
    required int revision,
    required int serverVersion,
    required int nowMicros,
  }) => database.transaction(() async {
    final row = await database
        .customSelect(
          'SELECT entity_type, record_id, vault_id FROM sync_outbox '
          'WHERE operation_id = ?',
          variables: [Variable(operationId)],
        )
        .getSingleOrNull();
    if (row == null) return;
    await recordActivity(
      vaultId: row.read<String>('vault_id'),
      entityType: row.read<String>('entity_type'),
      recordId: row.read<String>('record_id'),
      kind: 'sent',
      localRevision: revision,
      remoteRevision: revision,
      nowMicros: nowMicros,
    );
    await database.customStatement(
      'DELETE FROM sync_outbox WHERE operation_id = ? AND new_revision = ?',
      [operationId, revision],
    );
    // An edit committed while the request was in flight remains pending, but
    // its newly confirmed base is not a conflicting remote edit.
    await database.customStatement(
      'UPDATE sync_outbox SET base_revision = ?, base_snapshot = NULL '
      'WHERE operation_id = ? AND new_revision > ?',
      [revision, operationId, revision],
    );
    await database.customStatement(
      'UPDATE sync_entity_state SET last_synced_revision = ?, '
      'server_version = ?, sync_state = ? '
      'WHERE entity_type = ? AND record_id = ? AND local_revision = ?',
      [
        revision,
        serverVersion,
        'synced',
        row.read<String>('entity_type'),
        row.read<String>('record_id'),
        revision,
      ],
    );
    await _touchCursor(
      vaultId: row.read<String>('vault_id'),
      nowMicros: nowMicros,
      push: true,
    );
  });

  @override
  Future<void> markFailed({
    required String operationId,
    required int nextRetryAtMicros,
    required String errorCode,
  }) => database.customStatement(
    'UPDATE sync_outbox SET attempt_count = attempt_count + 1, '
    'next_retry_at = ?, last_error_code = ? WHERE operation_id = ?',
    [nextRetryAtMicros, errorCode, operationId],
  );

  @override
  Future<void> markPermanentFailure({
    required String operationId,
    required String errorCode,
  }) => database.customStatement(
    'UPDATE sync_outbox SET attempt_count = attempt_count + 1, '
    'next_retry_at = ?, last_error_code = ? WHERE operation_id = ?',
    [0x7FFFFFFFFFFFFFFF, errorCode, operationId],
  );

  @override
  Future<SyncCursorValue> cursor(String vaultId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM sync_cursors WHERE vault_id = ?',
          variables: [Variable(vaultId)],
        )
        .getSingleOrNull();
    if (row == null) {
      return SyncCursorValue(vaultId: vaultId, lastServerVersion: 0);
    }
    return SyncCursorValue(
      vaultId: vaultId,
      lastServerVersion: row.read<int>('last_server_version'),
      lastPullAtMicros: row.readNullable<int>('last_pull_at'),
      lastPushAtMicros: row.readNullable<int>('last_push_at'),
      lastSuccessAtMicros: row.readNullable<int>('last_success_at'),
    );
  }

  @override
  Future<void> advanceCursor({
    required String vaultId,
    required int serverVersion,
    required int nowMicros,
  }) async {
    final current = await cursor(vaultId);
    if (serverVersion < current.lastServerVersion) {
      throw StateError('A sync cursor cannot move backwards.');
    }
    await database.customStatement(
      'INSERT INTO sync_cursors ('
      'vault_id, last_server_version, last_pull_at'
      ') VALUES (?, ?, ?) '
      'ON CONFLICT(vault_id) DO UPDATE SET '
      'last_server_version = excluded.last_server_version, '
      'last_pull_at = excluded.last_pull_at',
      [vaultId, serverVersion, nowMicros],
    );
  }

  PendingSyncMutation _readMutation(QueryRow row) {
    final encodedBase = row.readNullable<String>('base_snapshot');
    final decodedBase = encodedBase == null ? null : jsonDecode(encodedBase);
    if (decodedBase != null && decodedBase is! Map<String, dynamic>) {
      throw const FormatException('Invalid sync base snapshot.');
    }
    return PendingSyncMutation(
      operationId: row.read<String>('operation_id'),
      vaultId: row.read<String>('vault_id'),
      entityType: SyncEntityType.parse(row.read<String>('entity_type')),
      recordId: row.read<String>('record_id'),
      baseRevision: row.readNullable<int>('base_revision'),
      baseSnapshot: decodedBase == null
          ? null
          : Map<String, Object?>.from(decodedBase),
      newRevision: row.read<int>('new_revision'),
      operation: SyncOperation.values.byName(row.read<String>('operation')),
      createdAtMicros: row.read<int>('created_at'),
      attemptCount: row.read<int>('attempt_count'),
      nextRetryAtMicros: row.readNullable<int>('next_retry_at'),
      lastErrorCode: row.readNullable<String>('last_error_code'),
    );
  }

  Future<void> _touchCursor({
    required String vaultId,
    required int nowMicros,
    required bool push,
  }) => database.customStatement(
    'INSERT INTO sync_cursors (vault_id, last_${push ? 'push' : 'pull'}_at) '
    'VALUES (?, ?) '
    'ON CONFLICT(vault_id) DO UPDATE SET '
    'last_${push ? 'push' : 'pull'}_at = excluded.last_${push ? 'push' : 'pull'}_at',
    [vaultId, nowMicros],
  );
}
