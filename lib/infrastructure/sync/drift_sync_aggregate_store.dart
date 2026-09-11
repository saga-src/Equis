import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/ports/sync_aggregate_store.dart';
import '../../application/ports/sync_conflict_resolver.dart';
import '../../application/sync/sync_models.dart';
import '../../application/sync/sync_revision_order.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';
import '../security/canonical_json.dart';
import 'drift_sync_metadata_store.dart';

final class DriftSyncAggregateStore
    implements SyncAggregateStore, SyncConflictResolver {
  const DriftSyncAggregateStore({
    required this.database,
    required this.metadata,
  });

  final EquisDatabase database;
  final DriftSyncMetadataStore metadata;

  @override
  Future<SyncReconciliation> reconcileRemote({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
    required int serverVersion,
    required bool isDeleted,
    required Map<String, Object?> payload,
  }) => database.transaction(() async {
    _validatePayload(
      payload,
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
      revision: revision,
    );
    final state = await database
        .customSelect(
          'SELECT server_version, sync_state FROM sync_entity_state WHERE entity_type = ? AND record_id = ?',
          variables: [Variable(entityType.wireName), Variable(recordId)],
        )
        .getSingleOrNull();
    // A pull page may contain a snapshot already superseded by this run's push.
    if ((state?.readNullable<int>('server_version') ?? 0) > serverVersion ||
        ((state?.readNullable<int>('server_version') ?? 0) == serverVersion &&
            state?.read<String>('sync_state') == 'synced')) {
      return const SyncReconciliation();
    }
    final pending = await metadata.pendingFor(
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
    );
    final local = await loadPayload(
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
    );
    if (pending != null && local == null) {
      throw const SyncAggregateFormatException();
    }
    final identical =
        local != null &&
        CanonicalJson.encode(local) == CanonicalJson.encode(payload);
    final divergent =
        pending != null && !identical && pending.baseRevision != revision;
    if (divergent) {
      await metadata.recordActivity(
        vaultId: vaultId,
        entityType: entityType.wireName,
        recordId: recordId,
        kind: 'conflict',
        localRevision: pending.newRevision,
        remoteRevision: revision,
      );
    }
    final localWins =
        pending != null &&
        compareSyncRevisions(
              localRevision: pending.newRevision,
              remoteRevision: revision,
              local: local!,
              remote: payload,
            ) >
            0;
    var changed = pending != null;
    if (localWins) {
      // Keep coalesced offline revisions. Only an equal-revision tie needs a
      // new revision to satisfy the server's compare-and-swap contract.
      if (pending.baseRevision == revision && pending.newRevision > revision) {
        changed = false;
      } else {
        final next = pending.newRevision > revision
            ? pending.newRevision
            : revision + 1;
        final revised = _withRootRevision(local, next);
        await _replaceAggregate(entityType, recordId, revised);
        await database.customStatement(
          'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ?',
          [vaultId, entityType.wireName, recordId],
        );
        await metadata.enqueue(
          vaultId: vaultId,
          entityType: entityType,
          recordId: recordId,
          baseRevision: revision,
          baseSnapshot: payload,
          newRevision: next,
          operation: pending.operation,
        );
      }
      await database.customStatement(
        'UPDATE sync_entity_state SET server_version = ?, sync_state = ? WHERE entity_type = ? AND record_id = ?',
        [
          serverVersion,
          pending.operation == SyncOperation.delete
              ? 'deleted_pending'
              : 'pending',
          entityType.wireName,
          recordId,
        ],
      );
    } else {
      await database.customStatement(
        'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ?',
        [vaultId, entityType.wireName, recordId],
      );
      await applyRemote(
        vaultId: vaultId,
        entityType: entityType,
        recordId: recordId,
        revision: revision,
        serverVersion: serverVersion,
        isDeleted: isDeleted,
        payload: payload,
      );
      if (!identical) {
        await metadata.recordActivity(
          vaultId: vaultId,
          entityType: entityType.wireName,
          recordId: recordId,
          kind: 'received',
          localRevision: revision,
          remoteRevision: revision,
        );
      } else if (pending != null) {
        await metadata.recordActivity(
          vaultId: vaultId,
          entityType: entityType.wireName,
          recordId: recordId,
          kind: 'sent',
          localRevision: revision,
          remoteRevision: revision,
        );
      }
    }
    await database.customStatement(
      'UPDATE sync_conflicts SET resolved_at = ?, resolution = ? WHERE vault_id = ? AND entity_type = ? AND record_id = ? AND resolved_at IS NULL',
      [
        DateTime.now().toUtc().microsecondsSinceEpoch,
        localWins ? 'keepLocal' : 'keepRemote',
        vaultId,
        entityType.wireName,
        recordId,
      ],
    );
    return SyncReconciliation(
      outboxChanged: changed,
      remoteApplied: !localWins && !identical,
      sentConfirmed: !localWins && identical && pending != null,
      conflictDetected: divergent,
    );
  });

  @override
  Future<List<SyncConflictSummary>> unresolved(String vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT id, vault_id, entity_type, record_id, base_revision, '
          'local_revision, remote_revision, detected_at FROM sync_conflicts '
          'WHERE vault_id = ? AND resolved_at IS NULL ORDER BY detected_at, id',
          variables: [Variable(vaultId)],
        )
        .get();
    return [
      for (final row in rows)
        SyncConflictSummary(
          id: row.read<String>('id'),
          vaultId: row.read<String>('vault_id'),
          entityType: SyncEntityType.parse(row.read<String>('entity_type')),
          recordId: row.read<String>('record_id'),
          baseRevision: row.read<int>('base_revision'),
          localRevision: row.read<int>('local_revision'),
          remoteRevision: row.read<int>('remote_revision'),
          detectedAtMicros: row.read<int>('detected_at'),
        ),
    ];
  }

  @override
  Future<void> resolve({
    required String conflictId,
    required SyncConflictResolution resolution,
    Map<String, Object?>? mergedSnapshot,
  }) => database.transaction(() async {
    final row = await database
        .customSelect(
          'SELECT * FROM sync_conflicts WHERE id = ? AND resolved_at IS NULL',
          variables: [Variable(conflictId)],
        )
        .getSingleOrNull();
    if (row == null) throw StateError('The sync conflict is unavailable.');
    if (resolution == SyncConflictResolution.merged && mergedSnapshot == null) {
      throw ArgumentError.notNull('mergedSnapshot');
    }
    final type = SyncEntityType.parse(row.read<String>('entity_type'));
    final vaultId = row.read<String>('vault_id');
    final recordId = row.read<String>('record_id');
    final remoteRevision = row.read<int>('remote_revision');
    final remote = _decodeSnapshot(row.read<String>('remote_snapshot'));
    final selected = switch (resolution) {
      SyncConflictResolution.keepRemote => remote,
      SyncConflictResolution.keepLocal => _decodeSnapshot(
        row.read<String>('local_snapshot'),
      ),
      SyncConflictResolution.merged => mergedSnapshot!,
    };
    await database.customStatement(
      'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ?',
      [vaultId, type.wireName, recordId],
    );
    if (resolution == SyncConflictResolution.keepRemote) {
      final normalized = _validatePayload(
        selected,
        vaultId: vaultId,
        entityType: type,
        recordId: recordId,
        revision: remoteRevision,
      );
      await _replaceAggregate(type, recordId, normalized);
      await database.customStatement(
        'UPDATE sync_entity_state SET local_revision = ?, '
        'last_synced_revision = ?, sync_state = ? '
        'WHERE entity_type = ? AND record_id = ?',
        [remoteRevision, remoteRevision, 'synced', type.wireName, recordId],
      );
    } else {
      final nextRevision = remoteRevision + 1;
      final revised = _withRootRevision(selected, nextRevision);
      final normalized = _validatePayload(
        revised,
        vaultId: vaultId,
        entityType: type,
        recordId: recordId,
        revision: nextRevision,
      );
      await _replaceAggregate(type, recordId, normalized);
      await metadata.enqueue(
        vaultId: vaultId,
        entityType: type,
        recordId: recordId,
        baseRevision: remoteRevision,
        baseSnapshot: remote,
        newRevision: nextRevision,
        operation: SyncOperation.upsert,
      );
    }
    await database.customStatement(
      'UPDATE sync_conflicts SET resolved_at = ?, resolution = ? WHERE id = ?',
      [
        DateTime.now().toUtc().microsecondsSinceEpoch,
        resolution.name,
        conflictId,
      ],
    );
  });

  @override
  Future<Map<String, Object?>?> loadPayload({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  }) async {
    final spec = _specs[entityType]!;
    final root = await _one(spec.table, 'id', recordId);
    if (root == null ||
        root['vault_id'] != vaultId && entityType != SyncEntityType.vault) {
      return null;
    }
    final children = <String, Object?>{};
    for (final child in spec.children) {
      children[child.table] = await _many(
        child.table,
        child.foreignKey,
        recordId,
      );
    }
    if (entityType == SyncEntityType.account) {
      final pocketIds = _ids(children['account_pockets']);
      children['credit_card_limits'] = await _manyIn(
        'credit_card_limits',
        'account_pocket_id',
        pocketIds,
      );
    } else if (entityType == SyncEntityType.transaction) {
      final eventIds = _ids(children['investment_events']);
      children['investment_lots'] = await _manyIn(
        'investment_lots',
        'acquisition_event_id',
        eventIds,
      );
      children['investment_lot_disposals'] = await _manyIn(
        'investment_lot_disposals',
        'disposal_event_id',
        eventIds,
      );
    }
    if (entityType == SyncEntityType.attachment) {
      root.remove('local_path');
      root.remove('upload_state');
    }
    return {
      'format_version': 1,
      'entity_type': entityType.wireName,
      'root': root,
      'children': children,
    };
  }

  @override
  Future<void> applyRemote({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
    required int serverVersion,
    required bool isDeleted,
    required Map<String, Object?> payload,
  }) => database.transaction(() async {
    final normalized = _validatePayload(
      payload,
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
      revision: revision,
    );
    await _replaceAggregate(entityType, recordId, normalized);
    await database.customStatement(
      'INSERT INTO sync_entity_state ('
      'entity_type, record_id, local_revision, last_synced_revision, '
      'server_version, sync_state) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, record_id) DO UPDATE SET '
      'local_revision = excluded.local_revision, '
      'last_synced_revision = excluded.last_synced_revision, '
      'server_version = excluded.server_version, sync_state = excluded.sync_state',
      [
        entityType.wireName,
        recordId,
        revision,
        revision,
        serverVersion,
        'synced',
      ],
    );
  });

  @override
  Future<void> applyMerged({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int remoteRevision,
    required int serverVersion,
    required Map<String, Object?> remoteSnapshot,
    required Map<String, Object?> mergedSnapshot,
  }) => database.transaction(() async {
    final nextRevision = remoteRevision + 1;
    final updated = _withRootRevision(mergedSnapshot, nextRevision);
    final normalized = _validatePayload(
      updated,
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
      revision: nextRevision,
    );
    await _replaceAggregate(entityType, recordId, normalized);
    await database.customStatement(
      'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ?',
      [vaultId, entityType.wireName, recordId],
    );
    await metadata.enqueue(
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
      baseRevision: remoteRevision,
      baseSnapshot: remoteSnapshot,
      newRevision: nextRevision,
      operation: SyncOperation.upsert,
    );
    await database.customStatement(
      'UPDATE sync_entity_state SET server_version = ? '
      'WHERE entity_type = ? AND record_id = ?',
      [serverVersion, entityType.wireName, recordId],
    );
  });

  @override
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
  }) => database.transaction(() async {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final existing = await database
        .customSelect(
          'SELECT id FROM sync_conflicts WHERE vault_id = ? AND entity_type = ? '
          'AND record_id = ? AND remote_revision = ? AND resolved_at IS NULL '
          'ORDER BY detected_at LIMIT 1',
          variables: [
            Variable(vaultId),
            Variable(entityType.wireName),
            Variable(recordId),
            Variable(remoteRevision),
          ],
        )
        .getSingleOrNull();
    if (existing == null) {
      await database.customStatement(
        'INSERT INTO sync_conflicts ('
        'id, vault_id, entity_type, record_id, base_revision, local_revision, '
        'remote_revision, base_snapshot, local_snapshot, remote_snapshot, detected_at'
        ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          EntityId.generate().value,
          vaultId,
          entityType.wireName,
          recordId,
          baseRevision,
          localRevision,
          remoteRevision,
          CanonicalJson.encode(baseSnapshot),
          CanonicalJson.encode(localSnapshot),
          CanonicalJson.encode(remoteSnapshot),
          now,
        ],
      );
    } else {
      await database.customStatement(
        'UPDATE sync_conflicts SET local_revision = ?, local_snapshot = ? '
        'WHERE id = ?',
        [
          localRevision,
          CanonicalJson.encode(localSnapshot),
          existing.read<String>('id'),
        ],
      );
    }
    await database.customStatement(
      'INSERT INTO sync_entity_state ('
      'entity_type, record_id, local_revision, server_version, sync_state'
      ') VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, record_id) DO UPDATE SET '
      'server_version = excluded.server_version, sync_state = excluded.sync_state',
      [entityType.wireName, recordId, localRevision, serverVersion, 'conflict'],
    );
  });

  Map<String, Object?> _validatePayload(
    Map<String, Object?> payload, {
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
  }) {
    if (payload['format_version'] != 1 ||
        payload['entity_type'] != entityType.wireName ||
        payload['root'] is! Map ||
        payload['children'] is! Map) {
      throw const SyncAggregateFormatException();
    }
    final root = Map<String, Object?>.from(payload['root']! as Map);
    if (root['id'] != recordId ||
        root['revision'] != revision ||
        (entityType == SyncEntityType.vault
            ? recordId != vaultId
            : root['vault_id'] != vaultId)) {
      throw const SyncAggregateFormatException();
    }
    final children = Map<String, Object?>.from(payload['children']! as Map);
    final allowed = {
      for (final child in _specs[entityType]!.children) child.table,
      if (entityType == SyncEntityType.account) 'credit_card_limits',
      if (entityType == SyncEntityType.transaction) ...{
        'investment_lots',
        'investment_lot_disposals',
      },
    };
    if (!children.keys.toSet().containsAll(allowed) ||
        children.keys.any((key) => !allowed.contains(key)) ||
        children.values.any((value) => value is! List)) {
      throw const SyncAggregateFormatException();
    }
    return {
      'format_version': 1,
      'entity_type': entityType.wireName,
      'root': root,
      'children': children,
    };
  }

  Future<void> _replaceAggregate(
    SyncEntityType type,
    String recordId,
    Map<String, Object?> payload,
  ) async {
    final spec = _specs[type]!;
    final root = Map<String, Object?>.from(payload['root']! as Map);
    final children = Map<String, Object?>.from(payload['children']! as Map);
    if (type == SyncEntityType.account) {
      await _deleteNested(
        'credit_card_limits',
        'account_pocket_id',
        'account_pockets',
        'account_id',
        recordId,
      );
    } else if (type == SyncEntityType.transaction) {
      await _deleteNested(
        'investment_lot_disposals',
        'disposal_event_id',
        'investment_events',
        'transaction_id',
        recordId,
      );
      await _deleteNested(
        'investment_lots',
        'acquisition_event_id',
        'investment_events',
        'transaction_id',
        recordId,
      );
    }
    for (final child in spec.children.reversed) {
      if (child.table == 'account_pockets') {
        final retained = _ids(children[child.table]);
        await database.customStatement(
          'DELETE FROM account_pockets WHERE account_id = ?'
          '${retained.isEmpty ? '' : ' AND id NOT IN (${List.filled(retained.length, '?').join(',')})'}',
          [recordId, ...retained],
        );
        continue;
      }
      await database.customStatement(
        'DELETE FROM ${child.table} WHERE ${child.foreignKey} = ?',
        [recordId],
      );
    }
    await _upsert(spec.table, root);
    for (final child in spec.children) {
      for (final row in _rows(children[child.table])) {
        if (child.table == 'account_pockets') {
          await _upsert(child.table, row);
        } else {
          await _insert(child.table, row);
        }
      }
    }
    if (type == SyncEntityType.account) {
      for (final row in _rows(children['credit_card_limits'])) {
        await _insert('credit_card_limits', row);
      }
    } else if (type == SyncEntityType.transaction) {
      for (final row in _rows(children['investment_lots'])) {
        await _insert('investment_lots', row);
      }
      for (final row in _rows(children['investment_lot_disposals'])) {
        await _insert('investment_lot_disposals', row);
      }
    }
  }

  Future<Map<String, Object?>?> _one(
    String table,
    String column,
    String value,
  ) async {
    final row = await database
        .customSelect(
          'SELECT * FROM $table WHERE $column = ?',
          variables: [Variable(value)],
        )
        .getSingleOrNull();
    return row == null ? null : Map<String, Object?>.from(row.data);
  }

  Future<List<Map<String, Object?>>> _many(
    String table,
    String column,
    String value,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM $table WHERE $column = ? ORDER BY rowid',
          variables: [Variable(value)],
        )
        .get();
    return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
  }

  Future<List<Map<String, Object?>>> _manyIn(
    String table,
    String column,
    List<String> values,
  ) async {
    if (values.isEmpty) return [];
    final placeholders = List.filled(values.length, '?').join(',');
    final rows = await database
        .customSelect(
          'SELECT * FROM $table WHERE $column IN ($placeholders) ORDER BY rowid',
          variables: values.map(Variable.new).toList(),
        )
        .get();
    return rows.map((row) => Map<String, Object?>.from(row.data)).toList();
  }

  Future<void> _deleteNested(
    String childTable,
    String childForeignKey,
    String parentTable,
    String parentForeignKey,
    String recordId,
  ) => database.customStatement(
    'DELETE FROM $childTable WHERE $childForeignKey IN '
    '(SELECT id FROM $parentTable WHERE $parentForeignKey = ?)',
    [recordId],
  );

  Future<void> _insert(String table, Map<String, Object?> row) async {
    if (row.isEmpty) throw const SyncAggregateFormatException();
    final columns = row.keys.toList()..sort();
    await database.customStatement(
      'INSERT INTO $table (${columns.join(',')}) VALUES '
      '(${List.filled(columns.length, '?').join(',')})',
      columns.map((column) => row[column]).toList(),
    );
  }

  Future<void> _upsert(String table, Map<String, Object?> row) async {
    if (row['id'] == null) throw const SyncAggregateFormatException();
    final columns = row.keys.toList()..sort();
    final updates = columns
        .where((column) => column != 'id')
        .map((column) => '$column = excluded.$column')
        .join(',');
    await database.customStatement(
      'INSERT INTO $table (${columns.join(',')}) VALUES '
      '(${List.filled(columns.length, '?').join(',')}) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      columns.map((column) => row[column]).toList(),
    );
  }

  Map<String, Object?> _withRootRevision(
    Map<String, Object?> payload,
    int revision,
  ) {
    final copy =
        jsonDecode(CanonicalJson.encode(payload)) as Map<String, dynamic>;
    final root = Map<String, Object?>.from(copy['root']! as Map);
    root['revision'] = revision;
    root['updated_at'] = DateTime.now().toUtc().microsecondsSinceEpoch;
    copy['root'] = root;
    return Map<String, Object?>.from(copy);
  }

  Map<String, Object?> _decodeSnapshot(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const SyncAggregateFormatException();
    }
    return Map<String, Object?>.from(decoded);
  }
}

List<Map<String, Object?>> _rows(Object? value) => (value! as List)
    .map((row) => Map<String, Object?>.from(row as Map))
    .toList(growable: false);

List<String> _ids(Object? rows) =>
    _rows(rows).map((row) => row['id']! as String).toList(growable: false);

final class _ChildSpec {
  const _ChildSpec(this.table, this.foreignKey);
  final String table;
  final String foreignKey;
}

final class _AggregateSpec {
  const _AggregateSpec(this.table, [this.children = const []]);
  final String table;
  final List<_ChildSpec> children;
}

const _specs = <SyncEntityType, _AggregateSpec>{
  SyncEntityType.vault: _AggregateSpec('vaults', [
    _ChildSpec('vault_preferences', 'vault_id'),
  ]),
  SyncEntityType.account: _AggregateSpec('accounts', [
    _ChildSpec('account_pockets', 'account_id'),
    _ChildSpec('credit_card_profiles', 'account_id'),
  ]),
  SyncEntityType.category: _AggregateSpec('categories'),
  SyncEntityType.counterparty: _AggregateSpec('counterparties', [
    _ChildSpec('counterparty_aliases', 'counterparty_id'),
  ]),
  SyncEntityType.tag: _AggregateSpec('tags'),
  SyncEntityType.transaction: _AggregateSpec('transactions', [
    _ChildSpec('account_movements', 'transaction_id'),
    _ChildSpec('transaction_splits', 'transaction_id'),
    _ChildSpec('transaction_tags', 'transaction_id'),
    _ChildSpec('fx_conversions', 'transaction_id'),
    _ChildSpec('investment_events', 'transaction_id'),
  ]),
  SyncEntityType.recurringRule: _AggregateSpec('recurring_rules', [
    _ChildSpec('recurring_templates', 'recurring_rule_id'),
    _ChildSpec('recurring_template_movements', 'recurring_rule_id'),
    _ChildSpec('recurring_template_splits', 'recurring_rule_id'),
  ]),
  SyncEntityType.installmentPlan: _AggregateSpec('installment_plans', [
    _ChildSpec('installments', 'installment_plan_id'),
  ]),
  SyncEntityType.creditCardStatement: _AggregateSpec('credit_card_statements'),
  SyncEntityType.budget: _AggregateSpec('budgets', [
    _ChildSpec('budget_categories', 'budget_id'),
    _ChildSpec('budget_accounts', 'budget_id'),
    _ChildSpec('budget_tags', 'budget_id'),
  ]),
  SyncEntityType.goal: _AggregateSpec('goals', [
    _ChildSpec('goal_accounts', 'goal_id'),
    _ChildSpec('goal_contributions', 'goal_id'),
  ]),
  SyncEntityType.asset: _AggregateSpec('assets', [
    _ChildSpec('asset_valuations', 'asset_id'),
  ]),
  SyncEntityType.investmentInstrument: _AggregateSpec('investment_instruments'),
  SyncEntityType.manualFxRate: _AggregateSpec('manual_fx_rates'),
  SyncEntityType.manualMarketPrice: _AggregateSpec('manual_market_prices'),
  SyncEntityType.attachment: _AggregateSpec('attachments', [
    _ChildSpec('attachment_links', 'attachment_id'),
  ]),
};

final class SyncAggregateFormatException implements Exception {
  const SyncAggregateFormatException();

  @override
  String toString() => 'Synchronization aggregate is invalid.';
}
