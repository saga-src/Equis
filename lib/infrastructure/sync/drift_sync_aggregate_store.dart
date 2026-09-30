import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/ports/sync_aggregate_store.dart';
import '../../application/ports/cloud_sync_gateway.dart';
import '../../application/ports/sync_conflict_resolver.dart';
import '../../application/ports/sync_payload_cryptography.dart';
import '../../application/sync/sync_models.dart';
import '../../application/sync/encrypted_sync_models.dart';
import '../../application/sync/sync_revision_order.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/shared/utc_instant.dart';
import '../persistence/database/equis_database.dart';
import '../repositories/drift_foundational_repositories.dart';
import '../security/canonical_json.dart';
import 'drift_sync_metadata_store.dart';

final class _BootstrapHistory {
  _BootstrapHistory(this.vaultId, this.knownAccounts);
  final String vaultId;
  final Set<String> knownAccounts;
  final Set<String> archivedAccounts = {};
}

final class DriftSyncAggregateStore
    implements
        SyncAggregateStore,
        SyncConflictResolver,
        SyncPushEligibility,
        SyncAuthenticatedInboundStore,
        SyncBootstrapHistoryStore,
        SyncQuarantineRecoveryStore,
        AccountSyncRecoveryStore {
  const DriftSyncAggregateStore({
    required this.database,
    required this.metadata,
    this.cipher,
  });

  final EquisDatabase database;
  final DriftSyncMetadataStore metadata;
  final SyncPayloadCryptography? cipher;

  static const _bootstrapHistoryKey = #equisBootstrapHistory;

  @override
  Future<void> hydrateBootstrapHistory({
    required String vaultId,
    required int nowMicros,
    required Future<void> Function(bool hydrate) pull,
  }) => database.transaction(() async {
    final cursor = await metadata.cursor(vaultId);
    final pending = await database
        .customSelect(
          'SELECT 1 FROM sync_outbox WHERE vault_id = ? LIMIT 1',
          variables: [Variable(vaultId)],
        )
        .getSingleOrNull();
    if (cursor.lastServerVersion != 0 || pending != null) {
      await pull(false);
      return;
    }
    final known = await database
        .customSelect(
          'SELECT id FROM accounts WHERE vault_id = ?',
          variables: [Variable(vaultId)],
        )
        .get();
    if (known.isNotEmpty) {
      // A populated local ledger is reconciliation, not snapshot hydration.
      await pull(false);
      return;
    }
    final history = _BootstrapHistory(
      vaultId,
      known.map((row) => row.read<String>('id')).toSet(),
    );
    await runZoned(
      () => pull(true),
      zoneValues: {_bootstrapHistoryKey: history},
    );
    // The cloud provides latest roots, not an authenticated archive-event
    // timeline. Accept only a complete, internally consistent first snapshot.
    for (final id in history.archivedAccounts) {
      final account = await _one('accounts', 'id', id);
      if (account == null ||
          account['archived'] != 1 ||
          account['deleted_at'] != null ||
          account['closed_on'] is! String) {
        throw const SyncAggregateFormatException();
      }
      final later = await database
          .customSelect(
            'SELECT 1 FROM transactions t JOIN account_movements m ON m.transaction_id = t.id '
            'JOIN account_pockets p ON p.id = m.account_pocket_id WHERE p.account_id = ? '
            "AND t.deleted_at IS NULL AND t.status != 'cancelled' AND t.financial_date > ? LIMIT 1",
            variables: [Variable(id), Variable(account['closed_on'])],
          )
          .getSingleOrNull();
      final paused = await database
          .customSelect(
            'SELECT 1 FROM sync_dependency_pause WHERE vault_id = ? AND account_id = ?',
            variables: [Variable(vaultId), Variable(id)],
          )
          .getSingleOrNull();
      final assessment = await DriftAccountAggregateRepository(database)
          .assessArchivedSnapshot(
            vaultId: EntityId.parse(vaultId),
            accountId: EntityId.parse(id),
            now: UtcInstant.fromEpochMicroseconds(nowMicros),
          );
      if (later != null || paused != null || assessment.blockers.isNotEmpty) {
        throw const SyncAggregateFormatException();
      }
    }
  });

  @override
  Future<List<AccountSyncRecoveryState>> accountRecoveryStates(
    String vaultId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT a.id, a.revision, p.permitted_restore_operation_id, '
          'p.accepted_restore_revision FROM sync_dependency_pause p '
          'JOIN accounts a ON a.id = p.account_id AND a.vault_id = p.vault_id '
          'WHERE p.vault_id = ? ORDER BY a.id',
          variables: [Variable(vaultId)],
        )
        .get();
    return [
      for (final row in rows)
        AccountSyncRecoveryState(
          accountId: row.read<String>('id'),
          revision: row.read<int>('revision'),
          restorationPending:
              row.readNullable<String>('permitted_restore_operation_id') !=
                  null ||
              row.readNullable<int>('accepted_restore_revision') != null,
        ),
    ];
  }

  @override
  Future<int> unresolvedQuarantineCount(String vaultId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS count FROM sync_quarantine WHERE vault_id = ? '
          "AND (replayed_at IS NULL OR replay_state <> 'replayed')",
          variables: [Variable(vaultId)],
        )
        .getSingle();
    return row.read<int>('count');
  }

  /// Prepares an explicit restoration; dependent mutations remain paused until
  /// the server accepts this revision and authenticated events can be replayed.
  @override
  Future<int> requestAccountRestore({
    required String vaultId,
    required String accountId,
    required int expectedRevision,
    required int nowMicros,
  }) => database.transaction(() async {
    final pause = await database
        .customSelect(
          'SELECT * FROM sync_dependency_pause WHERE vault_id = ? AND account_id = ?',
          variables: [Variable(vaultId), Variable(accountId)],
        )
        .getSingleOrNull();
    final local = await loadPayload(
      vaultId: vaultId,
      entityType: SyncEntityType.account,
      recordId: accountId,
    );
    if (pause == null || local == null) {
      throw const SyncAggregateFormatException();
    }
    if (pause.readNullable<String>('permitted_restore_operation_id') != null ||
        pause.readNullable<int>('accepted_restore_revision') != null) {
      throw const SyncAggregateFormatException();
    }
    final root = Map<String, Object?>.from(local['root']! as Map);
    if (root['revision'] != expectedRevision) {
      throw const SyncAggregateFormatException();
    }
    final state = await database
        .customSelect(
          'SELECT last_synced_revision FROM sync_entity_state WHERE entity_type = ? AND record_id = ?',
          variables: [
            Variable(SyncEntityType.account.wireName),
            Variable(accountId),
          ],
        )
        .getSingleOrNull();
    final blocked = await database
        .customSelect(
          'SELECT MAX(entity_revision) AS revision FROM sync_quarantine WHERE vault_id = ? '
          'AND entity_type = ? AND entity_id = ? AND replayed_at IS NULL',
          variables: [
            Variable(vaultId),
            Variable(SyncEntityType.account.wireName),
            Variable(accountId),
          ],
        )
        .getSingle();
    final blockedRevision = blocked.readNullable<int>('revision');
    final syncedRevision = state?.readNullable<int>('last_synced_revision');
    final cloudRevision = blockedRevision == null
        ? syncedRevision
        : syncedRevision == null || blockedRevision > syncedRevision
        ? blockedRevision
        : syncedRevision;
    if (cloudRevision == null || cloudRevision < 1) {
      throw const SyncAggregateFormatException();
    }
    final nextRevision =
        (expectedRevision > cloudRevision ? expectedRevision : cloudRevision) +
        1;
    final restoredState = await _restorationState(
      vaultId: vaultId,
      accountId: accountId,
      local: local,
    );
    final restored = {
      ...local,
      'children': restoredState.children,
      'root': {
        ...restoredState.root,
        'archived': 0,
        'closed_on': null,
        'deleted_at': null,
        'revision': nextRevision,
        'updated_at': nowMicros,
      },
    };
    await _replaceAccount(
      accountId,
      _validatePayload(
        restored,
        vaultId: vaultId,
        entityType: SyncEntityType.account,
        recordId: accountId,
        revision: nextRevision,
      ),
    );
    await database.customStatement(
      'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ?',
      [vaultId, SyncEntityType.account.wireName, accountId],
    );
    await metadata.enqueue(
      vaultId: vaultId,
      entityType: SyncEntityType.account,
      recordId: accountId,
      baseRevision: cloudRevision,
      baseSnapshot: null,
      newRevision: nextRevision,
      operation: SyncOperation.upsert,
    );
    final restore = (await metadata.pendingFor(
      vaultId: vaultId,
      entityType: SyncEntityType.account,
      recordId: accountId,
    ))!;
    await database.customStatement(
      'UPDATE sync_dependency_pause SET permitted_restore_operation_id = ?, accepted_restore_revision = ? '
      'WHERE vault_id = ? AND account_id = ?',
      [restore.operationId, cloudRevision, vaultId, accountId],
    );
    return nextRevision;
  });

  Future<({Map<String, Object?> root, Map<String, Object?> children})>
  _restorationState({
    required String vaultId,
    required String accountId,
    required Map<String, Object?> local,
  }) async {
    final localRoot = Map<String, Object?>.from(local['root']! as Map);
    final children = Map<String, Object?>.from(local['children']! as Map);
    final quarantined = await database
        .customSelect(
          'SELECT * FROM sync_quarantine WHERE vault_id = ? AND entity_type = ? '
          'AND entity_id = ? AND replayed_at IS NULL ORDER BY server_version DESC',
          variables: [
            Variable(vaultId),
            Variable(SyncEntityType.account.wireName),
            Variable(accountId),
          ],
        )
        .get();
    if (quarantined.isEmpty) return (root: localRoot, children: children);
    final decrypter = cipher;
    if (decrypter == null) throw const SyncAggregateFormatException();
    final localDefault = _rows(
      children['account_pockets'],
    ).where((row) => row['is_default'] == 1).firstOrNull;
    final pendingAccount = await metadata.pendingFor(
      vaultId: vaultId,
      entityType: SyncEntityType.account,
      recordId: accountId,
    );
    final remoteChildren = <String, Map<Object?, Map<String, Object?>>>{
      for (final table in [
        'account_pockets',
        'credit_card_profiles',
        'credit_card_limits',
      ])
        table: {},
    };
    Map<String, Object?>? latestRemoteRoot;
    for (final row in quarantined) {
      final stored =
          jsonDecode(row.read<String>('authenticated_envelope')) as Map;
      final identity = SyncRecordIdentity(
        vaultId: vaultId,
        recordId: accountId,
        entityType: SyncEntityType.account.wireName,
        revision: row.read<int>('entity_revision'),
      );
      final payload = _validatePayload(
        await decrypter.decrypt(
          identity: identity,
          envelope: EncryptedPayloadEnvelope(
            cipherVersion: stored['cipher_version'] as int,
            keyVersion: stored['key_version'] as int,
            nonce: base64Decode(stored['nonce'] as String),
            cipherText: base64Decode(stored['cipher_text'] as String),
            mac: base64Decode(stored['mac'] as String),
          ),
        ),
        vaultId: vaultId,
        entityType: SyncEntityType.account,
        recordId: accountId,
        revision: identity.revision,
      );
      latestRemoteRoot ??= Map<String, Object?>.from(payload['root']! as Map);
      final remote = Map<String, Object?>.from(payload['children']! as Map);
      for (final (table, key) in [
        ('account_pockets', 'id'),
        ('credit_card_profiles', 'account_id'),
        ('credit_card_limits', 'account_pocket_id'),
      ]) {
        for (final item in _rows(remote[table])) {
          // Quarantine rows are newest first; an older event cannot replace
          // the authenticated child state in the latest account event.
          remoteChildren[table]!.putIfAbsent(item[key], () => item);
        }
      }
    }
    for (final (table, key) in [
      ('account_pockets', 'id'),
      ('credit_card_profiles', 'account_id'),
      ('credit_card_limits', 'account_pocket_id'),
    ]) {
      final merged = <Object?, Map<String, Object?>>{
        for (final item in _rows(children[table])) item[key]: item,
      };
      for (final remote in remoteChildren[table]!.values) {
        final current = merged[remote[key]];
        if (table == 'account_pockets' &&
            current != null &&
            (current['account_id'] != remote['account_id'] ||
                current['currency_code'] != remote['currency_code'])) {
          throw const SyncAggregateFormatException();
        }
        // With no unsent account edit, the authenticated remote child is the
        // newer value. Local-only identities are retained in the union.
        if (current == null || pendingAccount == null) {
          merged[remote[key]] = remote;
        }
        if (table == 'account_pockets' && current != null) {
          final chosen = merged[remote[key]]!;
          merged[remote[key]] = {
            ...chosen,
            'archived': current['archived'] == 1 || remote['archived'] == 1
                ? 1
                : 0,
          };
        }
      }
      children[table] = merged.values.toList();
    }
    final remoteDefault = remoteChildren['account_pockets']!.values
        .where((row) => row['is_default'] == 1)
        .firstOrNull;
    final selectedDefault = pendingAccount == null
        ? remoteDefault ?? localDefault
        : localDefault ?? remoteDefault;
    if (selectedDefault != null) {
      children['account_pockets'] = [
        for (final pocket in _rows(children['account_pockets']))
          {
            ...pocket,
            'is_default': pocket['id'] == selectedDefault['id'] ? 1 : 0,
          },
      ];
    }
    return (
      root: pendingAccount == null ? latestRemoteRoot ?? localRoot : localRoot,
      children: children,
    );
  }

  @override
  Future<List<CloudSyncRecord>> replayCandidates(String vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT DISTINCT q.* FROM sync_quarantine q JOIN sync_dependency_pause p '
          'ON p.vault_id = q.vault_id AND (p.account_id = q.parent_account_id OR p.blocking_event_id = q.event_id) '
          'WHERE q.vault_id = ? AND q.replayed_at IS NULL '
          'AND p.permitted_restore_operation_id IS NULL AND p.accepted_restore_revision IS NOT NULL '
          'AND NOT EXISTS (SELECT 1 FROM json_each(q.authenticated_envelope, \'\$.blocked_account_ids\') dependency '
          'WHERE NOT EXISTS (SELECT 1 FROM accounts restored '
          'JOIN sync_dependency_pause ready ON ready.account_id = restored.id AND ready.vault_id = restored.vault_id '
          'WHERE restored.id = dependency.value AND restored.vault_id = q.vault_id '
          'AND restored.archived = 0 AND restored.deleted_at IS NULL '
          'AND ready.permitted_restore_operation_id IS NULL AND ready.accepted_restore_revision IS NOT NULL '
          'AND restored.revision >= ready.accepted_restore_revision '
          "AND (q.entity_type != 'account' OR ready.accepted_restore_revision > q.entity_revision))) "
          'ORDER BY q.server_version LIMIT 100',
          variables: [Variable(vaultId)],
        )
        .get();
    return rows.map((row) {
      final envelope =
          jsonDecode(row.read<String>('authenticated_envelope')) as Map;
      return CloudSyncRecord(
        serverVersion: row.read<int>('server_version'),
        record: EncryptedSyncRecord(
          identity: SyncRecordIdentity(
            vaultId: row.read<String>('vault_id'),
            recordId: row.read<String>('entity_id'),
            entityType: row.read<String>('entity_type'),
            revision: row.read<int>('entity_revision'),
          ),
          envelope: EncryptedPayloadEnvelope(
            cipherVersion: envelope['cipher_version'] as int,
            keyVersion: envelope['key_version'] as int,
            nonce: base64Decode(envelope['nonce'] as String),
            cipherText: base64Decode(envelope['cipher_text'] as String),
            mac: base64Decode(envelope['mac'] as String),
          ),
          isDeleted: envelope['is_deleted'] as bool,
        ),
      );
    }).toList();
  }

  @override
  Future<int> replayQuarantined({
    required List<AuthenticatedSyncReplay> records,
    required int nowMicros,
  }) => database.transaction(() async {
    var applied = 0;
    final vaults = <String>{};
    for (final replay in records) {
      final cloud = replay.cloudRecord;
      final identity = cloud.record.identity;
      final type = SyncEntityType.parse(identity.entityType);
      final payload = _validatePayload(
        replay.payload,
        vaultId: identity.vaultId,
        entityType: type,
        recordId: identity.recordId,
        revision: identity.revision,
      );
      final row = await database
          .customSelect(
            'SELECT * FROM sync_quarantine WHERE vault_id = ? AND server_version = ? '
            'AND entity_type = ? AND entity_id = ? AND replayed_at IS NULL',
            variables: [
              Variable(identity.vaultId),
              Variable(cloud.serverVersion),
              Variable(identity.entityType),
              Variable(identity.recordId),
            ],
          )
          .getSingleOrNull();
      if (row == null) continue;
      _assertStoredEnvelope(row, cloud);
      final stored =
          jsonDecode(row.read<String>('authenticated_envelope')) as Map;
      final dependencies = (stored['blocked_account_ids'] as List)
          .cast<String>();
      var ready = true;
      for (final accountId in dependencies) {
        final restored = await database
            .customSelect(
              'SELECT a.revision, p.accepted_restore_revision FROM accounts a '
              'JOIN sync_dependency_pause p ON p.account_id = a.id AND p.vault_id = a.vault_id '
              'WHERE a.id = ? AND a.vault_id = ? AND a.archived = 0 AND a.deleted_at IS NULL '
              'AND p.permitted_restore_operation_id IS NULL AND p.accepted_restore_revision IS NOT NULL '
              'AND a.revision >= p.accepted_restore_revision',
              variables: [Variable(accountId), Variable(identity.vaultId)],
            )
            .getSingleOrNull();
        if (restored == null ||
            (type == SyncEntityType.account &&
                restored.read<int>('accepted_restore_revision') <=
                    identity.revision)) {
          ready = false;
        }
      }
      if (!ready) continue;
      if (type != SyncEntityType.account) {
        final result = await reconcileRemote(
          vaultId: identity.vaultId,
          entityType: type,
          recordId: identity.recordId,
          revision: identity.revision,
          serverVersion: cloud.serverVersion,
          isDeleted: cloud.record.isDeleted,
          payload: payload,
        );
        if (result.remoteApplied) applied++;
        if (!await canPush(
          vaultId: identity.vaultId,
          entityType: type,
          recordId: identity.recordId,
        )) {
          continue;
        }
      }
      // Account events were superseded by the explicitly accepted restoration.
      await database.customStatement(
        "UPDATE sync_quarantine SET replay_state = 'replayed', replayed_at = ? WHERE event_id = ?",
        [nowMicros, row.read<String>('event_id')],
      );
      vaults.add(identity.vaultId);
    }
    for (final vaultId in vaults) {
      await database.customStatement(
        'DELETE FROM sync_dependency_pause WHERE vault_id = ? '
        'AND permitted_restore_operation_id IS NULL AND accepted_restore_revision IS NOT NULL '
        'AND NOT EXISTS (SELECT 1 FROM sync_quarantine q WHERE q.vault_id = sync_dependency_pause.vault_id '
        'AND q.replayed_at IS NULL AND (q.parent_account_id = sync_dependency_pause.account_id '
        'OR q.event_id = sync_dependency_pause.blocking_event_id '
        'OR EXISTS (SELECT 1 FROM json_each(q.authenticated_envelope, \'\$.blocked_account_ids\') dependency '
        'WHERE dependency.value = sync_dependency_pause.account_id)))',
        [vaultId],
      );
    }
    return applied;
  });

  @override
  Future<SyncReconciliation> receiveCloudRecord({
    required CloudSyncRecord cloudRecord,
    required Map<String, Object?> payload,
    required int nowMicros,
    bool advanceCursor = true,
  }) => database.transaction(() async {
    final record = cloudRecord.record;
    final identity = record.identity;
    final type = SyncEntityType.parse(identity.entityType);
    final normalized = _validatePayload(
      payload,
      vaultId: identity.vaultId,
      entityType: type,
      recordId: identity.recordId,
      revision: identity.revision,
    );
    if (type == SyncEntityType.account &&
        record.isDeleted !=
            ((normalized['root'] as Map)['deleted_at'] != null)) {
      throw const SyncAggregateFormatException();
    }
    final stored = await database
        .customSelect(
          'SELECT * FROM sync_quarantine WHERE vault_id = ? AND server_version = ? '
          'AND entity_type = ? AND entity_id = ?',
          variables: [
            Variable(identity.vaultId),
            Variable(cloudRecord.serverVersion),
            Variable(identity.entityType),
            Variable(identity.recordId),
          ],
        )
        .getSingleOrNull();
    if (stored != null) {
      _assertStoredEnvelope(stored, cloudRecord);
      await _advanceInboundCursor(cloudRecord, nowMicros, advanceCursor);
      return SyncReconciliation(
        conflictDetected:
            stored.readNullable<int>('replayed_at') == null ||
            stored.read<String>('replay_state') != 'replayed',
      );
    }
    final localRoot = await _one(_specs[type]!.table, 'id', identity.recordId);
    if (type != SyncEntityType.vault &&
        localRoot != null &&
        localRoot['vault_id'] != identity.vaultId) {
      throw const SyncAggregateFormatException();
    }
    final state = await database
        .customSelect(
          'SELECT server_version, sync_state FROM sync_entity_state WHERE entity_type = ? AND record_id = ?',
          variables: [
            Variable(identity.entityType),
            Variable(identity.recordId),
          ],
        )
        .getSingleOrNull();
    if ((state?.readNullable<int>('server_version') ?? 0) >=
            cloudRecord.serverVersion &&
        state?.read<String>('sync_state') != 'conflict') {
      await _advanceInboundCursor(cloudRecord, nowMicros, advanceCursor);
      return const SyncReconciliation();
    }
    final blockers = await _inboundBlockers(
      type: type,
      recordId: identity.recordId,
      payload: normalized,
      nowMicros: nowMicros,
    );
    if (blockers.isNotEmpty) {
      for (final blocker in blockers) {
        await _quarantine(
          cloudRecord: cloudRecord,
          accountId: blocker.$1,
          pocketId: blocker.$2,
          reason: blocker.$3,
          blockedAccountIds: blockers.map((entry) => entry.$1).toSet().toList(),
          nowMicros: nowMicros,
        );
      }
      await _advanceInboundCursor(cloudRecord, nowMicros, advanceCursor);
      return const SyncReconciliation(conflictDetected: true);
    }
    final result = await reconcileRemote(
      vaultId: identity.vaultId,
      entityType: type,
      recordId: identity.recordId,
      revision: identity.revision,
      serverVersion: cloudRecord.serverVersion,
      isDeleted: record.isDeleted,
      payload: normalized,
    );
    await _advanceInboundCursor(cloudRecord, nowMicros, advanceCursor);
    return result;
  });

  void _assertStoredEnvelope(QueryRow row, CloudSyncRecord cloudRecord) {
    final envelope = cloudRecord.record.envelope;
    final stored =
        jsonDecode(row.read<String>('authenticated_envelope')) as Map;
    if (row.read<int>('entity_revision') !=
            cloudRecord.record.identity.revision ||
        stored['cipher_version'] != envelope.cipherVersion ||
        stored['key_version'] != envelope.keyVersion ||
        stored['nonce'] != base64Encode(envelope.nonce) ||
        stored['cipher_text'] != base64Encode(envelope.cipherText) ||
        stored['mac'] != base64Encode(envelope.mac) ||
        stored['is_deleted'] != cloudRecord.record.isDeleted) {
      throw const SyncAggregateFormatException();
    }
  }

  Future<void> _advanceInboundCursor(
    CloudSyncRecord cloudRecord,
    int nowMicros,
    bool advance,
  ) async {
    if (!advance) return;
    final vaultId = cloudRecord.record.identity.vaultId;
    final current = await metadata.cursor(vaultId);
    if (cloudRecord.serverVersion <= current.lastServerVersion) return;
    await metadata.advanceCursor(
      vaultId: vaultId,
      serverVersion: cloudRecord.serverVersion,
      nowMicros: nowMicros,
    );
  }

  Future<List<(String, String?, String)>> _inboundBlockers({
    required SyncEntityType type,
    required String recordId,
    required Map<String, Object?> payload,
    required int nowMicros,
  }) async {
    if (type == SyncEntityType.account) {
      final root = payload['root'] as Map;
      final current = await _one('accounts', 'id', recordId);
      final history = Zone.current[_bootstrapHistoryKey] as _BootstrapHistory?;
      if (current == null &&
          history?.vaultId == root['vault_id'] &&
          !history!.knownAccounts.contains(recordId) &&
          root['archived'] == 1 &&
          root['deleted_at'] == null &&
          root['closed_on'] is String) {
        history.archivedAccounts.add(recordId);
      }
      if (current != null && current['vault_id'] != root['vault_id']) {
        throw const SyncAggregateFormatException();
      }
      final children = payload['children'] as Map;
      final incomingPockets = {
        for (final row in _rows(children['account_pockets'])) row['id']: row,
      };
      final incomingIds = incomingPockets.keys.toSet();
      final existing = await _many('account_pockets', 'account_id', recordId);
      if (payload['format_version'] == 2 &&
          existing.any((pocket) => !incomingIds.contains(pocket['id']))) {
        return [(recordId, null, 'account_omits_known_pocket')];
      }
      if (payload['format_version'] == 1 &&
          current != null &&
          (current['deleted_at'] != null ||
              current['archived'] == 1 ||
              current['closed_on'] != null ||
              (current['revision'] as int) > (root['revision'] as int) ||
              existing.any(
                (pocket) =>
                    !incomingIds.contains(pocket['id']) ||
                    (pocket['archived'] == 1 &&
                        incomingPockets[pocket['id']]?['archived'] != 1),
              ))) {
        return [(recordId, null, 'legacy_account_would_replace_local_state')];
      }
    }
    if (type == SyncEntityType.account &&
        (payload['root'] as Map)['deleted_at'] != null) {
      final reference = await database
          .customSelect(
            'SELECT p.id FROM account_pockets p '
            'JOIN account_movements m ON m.account_pocket_id = p.id '
            'WHERE p.account_id = ? LIMIT 1',
            variables: [Variable(recordId)],
          )
          .getSingleOrNull();
      final pending = await database
          .customSelect(
            'SELECT 1 FROM sync_outbox_dependencies d '
            'JOIN sync_outbox o ON o.operation_id = d.operation_id '
            'WHERE o.vault_id = ? AND d.account_id = ? '
            'AND o.entity_type = ? LIMIT 1',
            variables: [
              Variable((payload['root'] as Map)['vault_id']),
              Variable(recordId),
              Variable(SyncEntityType.transaction.wireName),
            ],
          )
          .getSingleOrNull();
      if (reference != null ||
          pending != null ||
          await _hasAccountReferences(recordId)) {
        return [
          (
            recordId,
            reference?.read<String>('id'),
            'account_tombstone_has_references',
          ),
        ];
      }
    }
    if (type == SyncEntityType.account &&
        (payload['root'] as Map)['archived'] == 1 &&
        (payload['root'] as Map)['deleted_at'] == null) {
      final root = payload['root'] as Map;
      final current = await _one('accounts', 'id', recordId);
      if (current != null) {
        if (current['deleted_at'] != null) {
          return [(recordId, null, 'account_archive_would_restore_deleted')];
        }
        final closedOn = root['closed_on'];
        if (closedOn is! String) {
          return [(recordId, null, 'account_archive_missing_close_date')];
        }
        final laterMovement = await database
            .customSelect(
              'SELECT 1 FROM transactions t '
              'JOIN account_movements m ON m.transaction_id = t.id '
              'JOIN account_pockets p ON p.id = m.account_pocket_id '
              'WHERE p.account_id = ? AND t.deleted_at IS NULL '
              "AND t.status != 'cancelled' AND t.financial_date > ? LIMIT 1",
              variables: [Variable(recordId), Variable(closedOn)],
            )
            .getSingleOrNull();
        if (laterMovement != null) {
          return [(recordId, null, 'account_archive_precedes_local_movement')];
        }
        if (current['archived'] != 1) {
          final assessment = await DriftAccountAggregateRepository(database)
              .assessRemoval(
                vaultId: EntityId.parse(root['vault_id'] as String),
                accountId: EntityId.parse(recordId),
                now: UtcInstant.fromEpochMicroseconds(nowMicros),
              );
          if (assessment.blockers.isNotEmpty) {
            return [(recordId, null, 'account_archive_has_obligations')];
          }
        }
        final pending = await database
            .customSelect(
              'SELECT 1 FROM sync_outbox_dependencies d '
              'JOIN sync_outbox o ON o.operation_id = d.operation_id '
              'WHERE o.vault_id = ? AND d.account_id = ? LIMIT 1',
              variables: [Variable(root['vault_id']), Variable(recordId)],
            )
            .getSingleOrNull();
        if (pending != null) {
          return [(recordId, null, 'account_archive_has_pending_mutations')];
        }
      }
    }
    final root = payload['root'] as Map;
    final children = Map<String, Object?>.from(payload['children']! as Map);
    final references = <(String?, String?)>[];
    void pocketRows(String table, String ownerColumn) {
      for (final row in _rows(children[table])) {
        if (row[ownerColumn] != recordId ||
            row['account_pocket_id'] is! String) {
          throw const SyncAggregateFormatException();
        }
        references.add((null, row['account_pocket_id'] as String));
      }
    }

    switch (type) {
      case SyncEntityType.transaction:
        pocketRows('account_movements', 'transaction_id');
      case SyncEntityType.recurringRule:
        pocketRows('recurring_template_movements', 'recurring_rule_id');
      case SyncEntityType.goal:
        pocketRows('goal_accounts', 'goal_id');
      case SyncEntityType.installmentPlan:
      case SyncEntityType.creditCardStatement:
        if (root['account_pocket_id'] is! String) {
          throw const SyncAggregateFormatException();
        }
        references.add((null, root['account_pocket_id'] as String));
      case SyncEntityType.budget:
        for (final row in _rows(children['budget_accounts'])) {
          if (row['budget_id'] != recordId || row['account_id'] is! String) {
            throw const SyncAggregateFormatException();
          }
          references.add((row['account_id'] as String, null));
        }
      case SyncEntityType.attachment:
        for (final row in _rows(children['attachment_links'])) {
          if (row['attachment_id'] != recordId) {
            throw const SyncAggregateFormatException();
          }
          if (row['entity_type'] == 'account') {
            if (row['entity_id'] is! String) {
              throw const SyncAggregateFormatException();
            }
            references.add((row['entity_id'] as String, null));
          } else if (row['entity_type'] == 'account_pocket') {
            if (row['entity_id'] is! String) {
              throw const SyncAggregateFormatException();
            }
            references.add((null, row['entity_id'] as String));
          }
        }
      default:
        break;
    }
    final blocked = <String, (String, String?, String)>{};
    for (final reference in references) {
      final account = await database
          .customSelect(
            'SELECT a.*, p.archived AS pocket_archived, '
            'EXISTS (SELECT 1 FROM sync_dependency_pause pause WHERE pause.vault_id = a.vault_id AND pause.account_id = a.id) AS paused '
            'FROM accounts a LEFT JOIN account_pockets p ON p.account_id = a.id '
            'WHERE ${reference.$1 == null ? 'p.id' : 'a.id'} = ? LIMIT 1',
            variables: [Variable(reference.$1 ?? reference.$2)],
          )
          .getSingleOrNull();
      if (account == null ||
          account.read<String>('vault_id') != root['vault_id']) {
        // No authenticated account identity can be inferred from an unknown
        // pocket. The caller keeps this event unacknowledged for a later pull.
        throw const SyncAggregateFormatException();
      }
      final accountId = account.read<String>('id');
      final inactive =
          account.read<int>('archived') == 1 ||
          (reference.$2 != null &&
              account.readNullable<int>('pocket_archived') == 1);
      var archiveConflict = inactive;
      final history = Zone.current[_bootstrapHistoryKey] as _BootstrapHistory?;
      final hydrating =
          history?.vaultId == root['vault_id'] &&
          history!.archivedAccounts.contains(accountId);
      if (inactive &&
          hydrating &&
          account.read<int>('archived') == 1 &&
          account.readNullable<int>('deleted_at') == null) {
        // Financial consistency and obligations are checked only after every
        // authenticated page has been applied in the enclosing transaction.
        archiveConflict =
            type == SyncEntityType.transaction &&
            (root['financial_date'] is! String ||
                account.readNullable<String>('closed_on') == null ||
                (root['financial_date'] as String).compareTo(
                      account.read<String>('closed_on'),
                    ) >
                    0);
      }
      if (inactive && !hydrating && type == SyncEntityType.transaction) {
        final current = await loadPayload(
          vaultId: root['vault_id'] as String,
          entityType: type,
          recordId: recordId,
        );
        final same =
            current != null &&
            CanonicalJson.encode(current) == CanonicalJson.encode(payload);
        archiveConflict = !same;
      }
      if (account.readNullable<int>('deleted_at') != null ||
          account.read<int>('paused') != 0 ||
          archiveConflict) {
        blocked[accountId] = (
          accountId,
          reference.$2,
          type == SyncEntityType.transaction
              ? 'transaction_references_inactive_account'
              : 'aggregate_references_inactive_account',
        );
      }
    }
    return blocked.values.toList();
  }

  Future<bool> _hasAccountReferences(String accountId) async {
    final row = await database
        .customSelect(
          'WITH scope AS (SELECT ? AS account_id), '
          'pockets AS (SELECT id FROM account_pockets WHERE account_id = ?) '
          'SELECT ('
          'EXISTS (SELECT 1 FROM account_movements WHERE account_pocket_id IN (SELECT id FROM pockets)) OR '
          'EXISTS (SELECT 1 FROM credit_card_statements WHERE account_pocket_id IN (SELECT id FROM pockets)) OR '
          'EXISTS (SELECT 1 FROM installment_plans WHERE account_pocket_id IN (SELECT id FROM pockets)) OR '
          'EXISTS (SELECT 1 FROM recurring_template_movements WHERE account_pocket_id IN (SELECT id FROM pockets)) OR '
          'EXISTS (SELECT 1 FROM goal_accounts WHERE account_pocket_id IN (SELECT id FROM pockets)) OR '
          'EXISTS (SELECT 1 FROM budget_accounts WHERE account_id = (SELECT account_id FROM scope)) OR '
          "EXISTS (SELECT 1 FROM attachment_links WHERE entity_type = 'account' AND entity_id = (SELECT account_id FROM scope)) OR "
          "EXISTS (SELECT 1 FROM attachment_links WHERE entity_type = 'account_pocket' AND entity_id IN (SELECT id FROM pockets))"
          ') AS referenced',
          variables: [Variable(accountId), Variable(accountId)],
        )
        .getSingle();
    return row.read<int>('referenced') != 0;
  }

  Future<void> _quarantine({
    required CloudSyncRecord cloudRecord,
    required String accountId,
    required String? pocketId,
    required String reason,
    required List<String> blockedAccountIds,
    required int nowMicros,
  }) async {
    final record = cloudRecord.record;
    final identity = record.identity;
    final envelope = record.envelope;
    await database.customStatement(
      'INSERT OR IGNORE INTO sync_quarantine '
      '(event_id, vault_id, server_version, entity_type, entity_id, '
      'entity_revision, parent_account_id, parent_pocket_id, '
      'authenticated_envelope, reason, detected_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        EntityId.generate().value,
        identity.vaultId,
        cloudRecord.serverVersion,
        identity.entityType,
        identity.recordId,
        identity.revision,
        accountId,
        pocketId,
        CanonicalJson.encode({
          'cipher_version': envelope.cipherVersion,
          'key_version': envelope.keyVersion,
          'nonce': base64Encode(envelope.nonce),
          'cipher_text': base64Encode(envelope.cipherText),
          'mac': base64Encode(envelope.mac),
          'is_deleted': record.isDeleted,
          'blocked_account_ids': blockedAccountIds,
        }),
        reason,
        nowMicros,
      ],
    );
    final event = await database
        .customSelect(
          'SELECT event_id FROM sync_quarantine WHERE vault_id = ? '
          'AND server_version = ? AND entity_type = ? AND entity_id = ?',
          variables: [
            Variable(identity.vaultId),
            Variable(cloudRecord.serverVersion),
            Variable(identity.entityType),
            Variable(identity.recordId),
          ],
        )
        .getSingle();
    await database.customStatement(
      'INSERT OR IGNORE INTO sync_dependency_pause '
      '(vault_id, account_id, blocking_event_id, created_at) '
      'VALUES (?, ?, ?, ?)',
      [identity.vaultId, accountId, event.read<String>('event_id'), nowMicros],
    );
    await metadata.recordActivity(
      vaultId: identity.vaultId,
      entityType: identity.entityType,
      recordId: identity.recordId,
      kind: 'conflict',
      localRevision: 0,
      remoteRevision: identity.revision,
      nowMicros: nowMicros,
    );
  }

  @override
  Future<bool> canPush({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  }) async {
    final blocked = await database
        .customSelect(
          'SELECT 1 FROM sync_conflicts WHERE vault_id = ? AND entity_type = ? '
          "AND record_id = ? AND resolved_at IS NULL AND resolution IN ('protected_legacy_format', 'protected_private_terms') LIMIT 1",
          variables: [
            Variable(vaultId),
            Variable(entityType.wireName),
            Variable(recordId),
          ],
        )
        .getSingleOrNull();
    return blocked == null;
  }

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
    await _assertInboundAccountSafety(
      entityType: entityType,
      recordId: recordId,
      isDeleted: isDeleted,
      payload: payload,
    );
    final state = await database
        .customSelect(
          'SELECT server_version, sync_state FROM sync_entity_state WHERE entity_type = ? AND record_id = ?',
          variables: [Variable(entityType.wireName), Variable(recordId)],
        )
        .getSingleOrNull();
    // Re-pulling the last confirmed cloud version after an offline edit is
    // not a competing write. A persisted review still needs re-evaluation.
    final knownServerVersion = state?.readNullable<int>('server_version') ?? 0;
    if (knownServerVersion > serverVersion ||
        (knownServerVersion == serverVersion &&
            state?.read<String>('sync_state') != 'conflict')) {
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
    if (entityType == SyncEntityType.transaction && local != null) {
      final hasLocalPrivate = await _hasPrivateLotData(recordId);
      final protectedLegacy = payload['format_version'] == 1 && hasLocalPrivate;
      final protectedPrivate =
          payload['format_version'] == 2 &&
          ((pending != null &&
                  _privateChildren(local) != _privateChildren(payload)) ||
              (hasLocalPrivate && _omitsPrivateRows(local, payload)));
      if (protectedLegacy || protectedPrivate) {
        await _protectConflict(
          vaultId: vaultId,
          entityType: entityType,
          recordId: recordId,
          pending: pending,
          local: local,
          remote: payload,
          remoteRevision: revision,
          serverVersion: serverVersion,
          reason: protectedLegacy
              ? 'protected_legacy_format'
              : 'protected_private_terms',
        );
        return const SyncReconciliation(conflictDetected: true);
      }
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
        await metadata.rebasePending(
          mutation: pending,
          baseRevision: revision,
          baseSnapshot: payload,
          newRevision: next,
        );
        if (entityType == SyncEntityType.account) {
          await database.customStatement(
            'UPDATE sync_dependency_pause SET accepted_restore_revision = ? '
            'WHERE vault_id = ? AND account_id = ? AND permitted_restore_operation_id = ?',
            [revision, vaultId, recordId, pending.operationId],
          );
        }
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
      if (identical &&
          pending != null &&
          entityType == SyncEntityType.account) {
        await metadata.confirmAccountRestore(
          vaultId: vaultId,
          accountId: recordId,
          operationId: pending.operationId,
          revision: revision,
        );
      }
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
    final protection = row.readNullable<String>('resolution');
    final protectedLegacy = protection == 'protected_legacy_format';
    final protectedTerms = protection == 'protected_private_terms';
    final protectedPrivate = protectedLegacy || protectedTerms;
    if ((protectedLegacy && resolution != SyncConflictResolution.keepLocal) ||
        (protectedTerms && resolution == SyncConflictResolution.merged)) {
      throw const SyncAggregateFormatException();
    }
    // The review snapshot can predate additional offline lot edits. Resolve
    // against the current aggregate while holding this database transaction.
    final current = protectedPrivate
        ? await loadPayload(
            vaultId: vaultId,
            entityType: type,
            recordId: recordId,
          )
        : null;
    if (protectedPrivate && current == null) {
      throw const SyncAggregateFormatException();
    }
    final preferred = switch (resolution) {
      SyncConflictResolution.keepRemote => remote,
      SyncConflictResolution.keepLocal =>
        current ?? _decodeSnapshot(row.read<String>('local_snapshot')),
      SyncConflictResolution.merged => mergedSnapshot!,
    };
    // A stale device can have a format-2 aggregate with no contract yet. A
    // choice of its ledger changes must not delete terms learned from the
    // other device. Rows absent from the chosen side are retained; for the
    // same ID, the explicit keepLocal/keepRemote choice selects the value.
    final selected = protectedTerms
        ? _unionPrivateChildren(
            preferred,
            resolution == SyncConflictResolution.keepLocal ? remote : current!,
          )
        : preferred;
    if (resolution == SyncConflictResolution.keepRemote && !protectedPrivate) {
      await database.customStatement(
        'DELETE FROM sync_outbox WHERE vault_id = ? AND entity_type = ? AND record_id = ?',
        [vaultId, type.wireName, recordId],
      );
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
      final localRevision =
          ((current ?? selected)['root'] as Map)['revision'] as int;
      final nextRevision =
          (protectedPrivate && localRevision > remoteRevision
              ? localRevision
              : remoteRevision) +
          1;
      final revised = _withRootRevision(selected, nextRevision);
      final normalized = _validatePayload(
        revised,
        vaultId: vaultId,
        entityType: type,
        recordId: recordId,
        revision: nextRevision,
      );
      await _replaceAggregate(type, recordId, normalized);
      await _enqueueRebased(
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
      final lotIds = _ids(children['investment_lots']);
      children['fixed_income_contracts'] = await _manyIn(
        'fixed_income_contracts',
        'lot_id',
        lotIds,
      );
      children['fixed_income_manual_values'] = await _manyIn(
        'fixed_income_manual_values',
        'lot_id',
        lotIds,
      );
    }
    if (entityType == SyncEntityType.attachment) {
      root.remove('local_path');
      root.remove('upload_state');
    }
    return {
      'format_version':
          entityType == SyncEntityType.transaction ||
              entityType == SyncEntityType.account
          ? 2
          : 1,
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
    await _assertInboundAccountSafety(
      entityType: entityType,
      recordId: recordId,
      isDeleted: isDeleted,
      payload: normalized,
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
    await _enqueueRebased(
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

  Future<void> _enqueueRebased({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int baseRevision,
    required Map<String, Object?> baseSnapshot,
    required int newRevision,
    required SyncOperation operation,
  }) async {
    final pending = await metadata.pendingFor(
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
    );
    if (pending != null) {
      await metadata.rebasePending(
        mutation: pending,
        baseRevision: baseRevision,
        baseSnapshot: baseSnapshot,
        newRevision: newRevision,
        operation: operation,
      );
    } else {
      await metadata.enqueue(
        vaultId: vaultId,
        entityType: entityType,
        recordId: recordId,
        baseRevision: baseRevision,
        baseSnapshot: baseSnapshot,
        newRevision: newRevision,
        operation: operation,
      );
    }
  }

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
    final format = payload['format_version'];
    if ((format != 1 &&
            !(format == 2 &&
                (entityType == SyncEntityType.transaction ||
                    entityType == SyncEntityType.account))) ||
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
        if (format == 2) ...{
          'fixed_income_contracts',
          'fixed_income_manual_values',
        },
      },
    };
    if (!children.keys.toSet().containsAll(allowed) ||
        children.keys.any((key) => !allowed.contains(key)) ||
        children.values.any((value) => value is! List)) {
      throw const SyncAggregateFormatException();
    }
    if (entityType == SyncEntityType.transaction) {
      final events = _rows(children['investment_events']);
      final eventIds = _ids(events).toSet();
      final lots = _rows(children['investment_lots']);
      final lotIds = lots.map((row) => row['id']).toSet();
      if (events.any((row) => row['transaction_id'] != recordId) ||
          lots.any((row) => !eventIds.contains(row['acquisition_event_id'])) ||
          _rows(
            children['investment_lot_disposals'],
          ).any((row) => !eventIds.contains(row['disposal_event_id'])) ||
          (format == 2 &&
              (_rows(
                    children['fixed_income_contracts'],
                  ).any((row) => !lotIds.contains(row['lot_id'])) ||
                  _rows(
                    children['fixed_income_manual_values'],
                  ).any((row) => !lotIds.contains(row['lot_id']))))) {
        throw const SyncAggregateFormatException();
      }
    }
    if (entityType == SyncEntityType.account) {
      final pockets = _rows(children['account_pockets']);
      final pocketIds = <String>{};
      final currencies = <String>{};
      var defaultCount = 0;
      for (final pocket in pockets) {
        final id = pocket['id'];
        final currency = pocket['currency_code'];
        if (id is! String ||
            !pocketIds.add(id) ||
            currency is! String ||
            !currencies.add(currency) ||
            (pocket['is_default'] != 0 && pocket['is_default'] != 1) ||
            pocket['account_id'] != recordId) {
          throw const SyncAggregateFormatException();
        }
        if (pocket['is_default'] == 1) defaultCount++;
      }
      if (defaultCount != 1) {
        throw const SyncAggregateFormatException();
      }
      final profiles = _rows(children['credit_card_profiles']);
      if (profiles.length > 1 ||
          profiles.any((row) => row['account_id'] != recordId)) {
        throw const SyncAggregateFormatException();
      }
      final limits = _rows(children['credit_card_limits']);
      final limitIds = <String>{};
      for (final limit in limits) {
        final id = limit['account_pocket_id'];
        if (id is! String || !pocketIds.contains(id) || !limitIds.add(id)) {
          throw const SyncAggregateFormatException();
        }
      }
    }
    return {
      'format_version': format,
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
    if (type == SyncEntityType.transaction) {
      await _replaceTransaction(recordId, payload);
      return;
    }
    if (type == SyncEntityType.account) {
      await _replaceAccount(recordId, payload);
      return;
    }
    final spec = _specs[type]!;
    final root = Map<String, Object?>.from(payload['root']! as Map);
    final children = Map<String, Object?>.from(payload['children']! as Map);
    for (final child in spec.children.reversed) {
      await database.customStatement(
        'DELETE FROM ${child.table} WHERE ${child.foreignKey} = ?',
        [recordId],
      );
    }
    await _upsert(spec.table, root);
    for (final child in spec.children) {
      for (final row in _rows(children[child.table])) {
        await _insert(child.table, row);
      }
    }
  }

  Future<void> _replaceAccount(
    String recordId,
    Map<String, Object?> payload,
  ) async {
    final root = Map<String, Object?>.from(payload['root']! as Map);
    final children = Map<String, Object?>.from(payload['children']! as Map);
    final current = await _one('accounts', 'id', recordId);
    if (current != null && current['vault_id'] != root['vault_id']) {
      throw const SyncAggregateFormatException();
    }
    final incomingPockets = _rows(children['account_pockets']);
    final incomingIds = incomingPockets.map((row) => row['id']).toSet();
    final existingPockets = await _many(
      'account_pockets',
      'account_id',
      recordId,
    );
    if (payload['format_version'] == 2 &&
        existingPockets.any((row) => !incomingIds.contains(row['id']))) {
      throw const SyncAggregateFormatException();
    }
    if (current != null &&
        payload['format_version'] == 1 &&
        (current['deleted_at'] != null ||
            current['archived'] == 1 ||
            current['closed_on'] != null ||
            (current['revision'] as int) > (root['revision'] as int))) {
      throw const SyncAggregateFormatException();
    }
    if (payload['format_version'] == 1) {
      for (final pocket in existingPockets) {
        final incoming = incomingPockets.where(
          (row) => row['id'] == pocket['id'],
        );
        if (incoming.isEmpty) {
          final referenced = await database
              .customSelect(
                'SELECT 1 FROM account_movements WHERE account_pocket_id = ? LIMIT 1',
                variables: [Variable(pocket['id'])],
              )
              .getSingleOrNull();
          if (referenced != null || pocket['archived'] == 1) {
            throw const SyncAggregateFormatException();
          }
        } else if (pocket['archived'] == 1 &&
            incoming.single['archived'] != 1) {
          throw const SyncAggregateFormatException();
        }
      }
    }
    if (root['deleted_at'] != null) {
      final references = await database
          .customSelect(
            'SELECT 1 FROM account_movements m '
            'JOIN account_pockets p ON p.id = m.account_pocket_id '
            'WHERE p.account_id = ? LIMIT 1',
            variables: [Variable(recordId)],
          )
          .getSingleOrNull();
      final pending = await database
          .customSelect(
            'SELECT 1 FROM sync_outbox_dependencies d '
            'JOIN sync_outbox o ON o.operation_id = d.operation_id '
            'WHERE o.vault_id = ? AND d.account_id = ? AND o.entity_type = ? LIMIT 1',
            variables: [
              Variable(root['vault_id']),
              Variable(recordId),
              Variable(SyncEntityType.transaction.wireName),
            ],
          )
          .getSingleOrNull();
      if (references != null ||
          pending != null ||
          await _hasAccountReferences(recordId)) {
        throw const SyncAggregateFormatException();
      }
    }
    await _upsert('accounts', root);
    for (final row in _rows(children['account_pockets'])) {
      final existing = await _one('account_pockets', 'id', row['id'] as String);
      if (existing != null && existing['account_id'] != recordId) {
        throw const SyncAggregateFormatException();
      }
      await _upsert('account_pockets', row);
    }
    for (final row in _rows(children['credit_card_profiles'])) {
      await _upsert('credit_card_profiles', row, key: 'account_id');
    }
    for (final row in _rows(children['credit_card_limits'])) {
      await _upsert('credit_card_limits', row, key: 'account_pocket_id');
    }
  }

  Future<void> _assertInboundAccountSafety({
    required SyncEntityType entityType,
    required String recordId,
    required bool isDeleted,
    required Map<String, Object?> payload,
  }) async {
    if (entityType == SyncEntityType.account) {
      final root = Map<String, Object?>.from(payload['root']! as Map);
      if (isDeleted != (root['deleted_at'] != null)) {
        throw const SyncAggregateFormatException();
      }
      return;
    }
    if (entityType != SyncEntityType.transaction) return;
    final children = Map<String, Object?>.from(payload['children']! as Map);
    for (final movement in _rows(children['account_movements'])) {
      if (movement['transaction_id'] != recordId ||
          movement['account_pocket_id'] is! String) {
        throw const SyncAggregateFormatException();
      }
      final deleted = await database
          .customSelect(
            'SELECT 1 FROM account_pockets p JOIN accounts a ON a.id = p.account_id '
            'WHERE p.id = ? AND a.deleted_at IS NOT NULL LIMIT 1',
            variables: [Variable(movement['account_pocket_id'])],
          )
          .getSingleOrNull();
      if (deleted != null) throw const SyncAggregateFormatException();
    }
  }

  Future<bool> _hasPrivateLotData(String transactionId) async {
    final row = await database
        .customSelect(
          'SELECT 1 FROM investment_lots l '
          'JOIN investment_events e ON e.id = l.acquisition_event_id '
          'WHERE e.transaction_id = ? AND ('
          'EXISTS (SELECT 1 FROM fixed_income_contracts c WHERE c.lot_id = l.id) '
          'OR EXISTS (SELECT 1 FROM fixed_income_manual_values m WHERE m.lot_id = l.id)) '
          'LIMIT 1',
          variables: [Variable(transactionId)],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<void> _protectConflict({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required PendingSyncMutation? pending,
    required Map<String, Object?> local,
    required Map<String, Object?> remote,
    required int remoteRevision,
    required int serverVersion,
    required String reason,
  }) async {
    await preserveConflict(
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
      baseRevision: pending?.baseRevision ?? 0,
      localRevision: (local['root'] as Map)['revision'] as int,
      remoteRevision: remoteRevision,
      serverVersion: serverVersion,
      baseSnapshot: pending?.baseSnapshot ?? const {},
      localSnapshot: local,
      remoteSnapshot: remote,
    );
    await database.customStatement(
      'UPDATE sync_conflicts SET resolution = ? '
      'WHERE vault_id = ? AND entity_type = ? AND record_id = ? '
      'AND remote_revision = ? AND resolved_at IS NULL',
      [reason, vaultId, entityType.wireName, recordId, remoteRevision],
    );
  }

  Future<void> _replaceTransaction(
    String recordId,
    Map<String, Object?> payload,
  ) async {
    if (payload['format_version'] == 1 && await _hasPrivateLotData(recordId)) {
      throw const SyncAggregateFormatException();
    }
    if (payload['format_version'] == 2 && await _hasPrivateLotData(recordId)) {
      final current = await loadPayload(
        vaultId: (payload['root'] as Map)['vault_id'] as String,
        entityType: SyncEntityType.transaction,
        recordId: recordId,
      );
      if (current != null && _omitsPrivateRows(current, payload)) {
        throw const SyncAggregateFormatException();
      }
    }
    final root = Map<String, Object?>.from(payload['root']! as Map);
    final children = Map<String, Object?>.from(payload['children']! as Map);
    final events = _rows(children['investment_events']);
    final lots = _rows(children['investment_lots']);
    final eventIds = _ids(events);
    final lotIds = _ids(lots);

    // Lots can be referenced by disposals in another transaction. Retain the
    // incoming identities while replacing this aggregate's children.
    await _deleteNested(
      'investment_lot_disposals',
      'disposal_event_id',
      'investment_events',
      'transaction_id',
      recordId,
    );
    for (final child in _specs[SyncEntityType.transaction]!.children.reversed) {
      if (child.table == 'investment_events') continue;
      await database.customStatement(
        'DELETE FROM ${child.table} WHERE ${child.foreignKey} = ?',
        [recordId],
      );
    }
    await _upsert('transactions', root);
    for (final event in events) {
      await _upsert('investment_events', event);
    }
    await database.customStatement(
      'DELETE FROM fixed_income_manual_values WHERE lot_id IN '
      '(SELECT l.id FROM investment_lots l JOIN investment_events e '
      'ON e.id = l.acquisition_event_id WHERE e.transaction_id = ?)',
      [recordId],
    );
    await database.customStatement(
      'DELETE FROM fixed_income_contracts WHERE lot_id IN '
      '(SELECT l.id FROM investment_lots l JOIN investment_events e '
      'ON e.id = l.acquisition_event_id WHERE e.transaction_id = ?)',
      [recordId],
    );
    await _deleteExcept(
      table: 'investment_lots',
      ownerColumn: 'acquisition_event_id',
      parentTable: 'investment_events',
      parentColumn: 'transaction_id',
      recordId: recordId,
      retainedIds: lotIds,
    );
    await _deleteExcept(
      table: 'investment_events',
      ownerColumn: 'transaction_id',
      recordId: recordId,
      retainedIds: eventIds,
    );
    for (final lot in lots) {
      await _upsert('investment_lots', lot);
    }
    for (final child in _specs[SyncEntityType.transaction]!.children) {
      if (child.table == 'investment_events') continue;
      for (final row in _rows(children[child.table])) {
        await _insert(child.table, row);
      }
    }
    for (final row in _rows(children['investment_lot_disposals'])) {
      await _insert('investment_lot_disposals', row);
    }
    if (payload['format_version'] == 2) {
      for (final row in _rows(children['fixed_income_contracts'])) {
        await _insert('fixed_income_contracts', row);
      }
      for (final row in _rows(children['fixed_income_manual_values'])) {
        await _insert('fixed_income_manual_values', row);
      }
    }
  }

  Future<void> _deleteExcept({
    required String table,
    required String ownerColumn,
    String? parentTable,
    String? parentColumn,
    required String recordId,
    required List<String> retainedIds,
  }) async {
    final owner = parentTable == null
        ? '$ownerColumn = ?'
        : '$ownerColumn IN (SELECT id FROM $parentTable WHERE $parentColumn = ?)';
    final retained = retainedIds.isEmpty
        ? ''
        : ' AND id NOT IN (${List.filled(retainedIds.length, '?').join(',')})';
    await database.customStatement('DELETE FROM $table WHERE $owner$retained', [
      recordId,
      ...retainedIds,
    ]);
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

  Future<void> _upsert(
    String table,
    Map<String, Object?> row, {
    String key = 'id',
  }) async {
    if (row[key] == null) throw const SyncAggregateFormatException();
    final columns = row.keys.toList()..sort();
    final updates = columns
        .where((column) => column != key)
        .map((column) => '$column = excluded.$column')
        .join(',');
    await database.customStatement(
      'INSERT INTO $table (${columns.join(',')}) VALUES '
      '(${List.filled(columns.length, '?').join(',')}) '
      'ON CONFLICT($key) DO UPDATE SET $updates',
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

String _privateChildren(Map<String, Object?> payload) {
  final children = Map<String, Object?>.from(payload['children']! as Map);
  List<Map<String, Object?>> sorted(String table, String key) {
    final rows = children[table] == null
        ? <Map<String, Object?>>[]
        : _rows(children[table]);
    rows.sort((a, b) => (a[key] as String).compareTo(b[key] as String));
    return rows;
  }

  return CanonicalJson.encode({
    'fixed_income_contracts': sorted('fixed_income_contracts', 'lot_id'),
    'fixed_income_manual_values': sorted('fixed_income_manual_values', 'id'),
  });
}

Map<String, Object?> _unionPrivateChildren(
  Map<String, Object?> preferred,
  Map<String, Object?> other,
) {
  final preferredChildren = Map<String, Object?>.from(
    preferred['children']! as Map,
  );
  final otherChildren = Map<String, Object?>.from(other['children']! as Map);

  List<Map<String, Object?>> union(String table, String key) {
    final byId = <String, Map<String, Object?>>{};
    for (final children in [otherChildren, preferredChildren]) {
      final seen = <String>{};
      for (final row in _rows(children[table])) {
        final id = row[key];
        if (id is! String || !seen.add(id)) {
          throw const SyncAggregateFormatException();
        }
        byId[id] = row;
      }
    }
    final ids = byId.keys.toList()..sort();
    return [for (final id in ids) byId[id]!];
  }

  preferredChildren['fixed_income_contracts'] = union(
    'fixed_income_contracts',
    'lot_id',
  );
  final manual = union('fixed_income_manual_values', 'id');
  final preferredManual = _rows(
    preferredChildren['fixed_income_manual_values'],
  );
  final preferredIds = preferredManual.map((row) => row['id']).toSet();
  final preferredDates = <String>{};
  String dateKey(Map<String, Object?> row) {
    final lotId = row['lot_id'];
    final date = row['value_date'];
    if (lotId is! String || date is! String) {
      throw const SyncAggregateFormatException();
    }
    return '$lotId|$date';
  }

  for (final row in preferredManual) {
    preferredDates.add(dateKey(row));
  }
  final resolvedAt = DateTime.now().toUtc().microsecondsSinceEpoch;
  for (final row in manual) {
    if (!preferredIds.contains(row['id']) &&
        preferredDates.contains(dateKey(row)) &&
        row['removed_at'] == null) {
      // Keep the other device's entry as history. The explicit resolution
      // selects the preferred value for this lot and date.
      row['removed_at'] = resolvedAt;
    }
  }
  preferredChildren['fixed_income_manual_values'] = manual;
  return {...preferred, 'children': preferredChildren};
}

bool _omitsPrivateRows(
  Map<String, Object?> local,
  Map<String, Object?> remote,
) {
  final localChildren = Map<String, Object?>.from(local['children']! as Map);
  final remoteChildren = Map<String, Object?>.from(remote['children']! as Map);
  bool missing(String table, String key) {
    final localIds = _rows(localChildren[table]).map((row) => row[key]).toSet();
    final remoteIds = _rows(
      remoteChildren[table],
    ).map((row) => row[key]).toSet();
    return !remoteIds.containsAll(localIds);
  }

  return missing('fixed_income_contracts', 'lot_id') ||
      missing('fixed_income_manual_values', 'id');
}

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
