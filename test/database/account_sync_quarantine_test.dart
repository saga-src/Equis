import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ready quarantine events are not starved by 100 partial dependencies',
    _checkReplaySelectionDoesNotStarve,
  );
  test(
    'fresh bootstrap preserves balanced archived history and blocks later backdating',
    () => _checkArchivedBootstrap(balanced: true),
  );
  test(
    'incomplete archived bootstrap rolls back history, account and cursor',
    () => _checkArchivedBootstrap(balanced: false),
  );
  test(
    'bootstrap accepts balanced history on the archive day',
    () => _checkArchivedBootstrap(balanced: true, onArchiveDay: true),
  );
  for (final tombstoneFirst in [false, true]) {
    test(
      'authenticated quarantine preserves both orders ($tombstoneFirst)',
      () async {
        final source = EquisDatabase(NativeDatabase.memory());
        final target = EquisDatabase(NativeDatabase.memory());
        addTearDown(source.close);
        addTearDown(target.close);
        await _seed(source);
        await _seed(target);
        final sourceStore = _store(source);
        final targetStore = _store(target);
        await _movement(source);
        final transaction = (await sourceStore.loadPayload(
          vaultId: _vault,
          entityType: SyncEntityType.transaction,
          recordId: _transaction,
        ))!;
        final account = (await sourceStore.loadPayload(
          vaultId: _vault,
          entityType: SyncEntityType.account,
          recordId: _account,
        ))!;
        final tombstone = {
          ...account,
          'root': {
            ...account['root'] as Map<String, Object?>,
            'revision': 2,
            'deleted_at': 100,
            'updated_at': 100,
          },
        };
        final keys = VaultKeyManager(store: _Secrets());
        await keys.loadOrCreateMasterKey();
        final cipher = SyncPayloadCipher(keys: keys);
        final firstPayload = tombstoneFirst ? tombstone : transaction;
        final secondPayload = tombstoneFirst ? transaction : tombstone;
        final first = await _cloudRecord(cipher, firstPayload, 1);
        final second = await _cloudRecord(cipher, secondPayload, 2);
        final cloud = _PullCloud([first, second]);
        final result = await SyncEngine(
          cloud: cloud,
          metadata: DriftSyncMetadataStore(target),
          aggregates: targetStore,
          cipher: cipher,
        ).synchronize(vaultId: _vault, deviceId: 'receiver');
        expect(result.status, SyncRunStatus.succeeded);
        expect(result.pulled, 1);
        expect(result.conflicts, 1);
        expect(cloud.acknowledged, [2]);
        expect(
          (await DriftSyncMetadataStore(
            target,
          ).cursor(_vault)).lastServerVersion,
          2,
        );
        final rows = await target
            .customSelect('SELECT * FROM sync_quarantine')
            .get();
        expect(rows, hasLength(1));
        final envelope =
            jsonDecode(rows.single.read<String>('authenticated_envelope'))
                as Map;
        expect(
          base64Decode(envelope['cipher_text'] as String),
          second.record.envelope.cipherText,
        );
        expect(
          base64Decode(envelope['nonce'] as String),
          second.record.envelope.nonce,
        );
        expect(
          base64Decode(envelope['mac'] as String),
          second.record.envelope.mac,
        );
        expect(
          await target
              .customSelect('SELECT * FROM sync_dependency_pause')
              .get(),
          hasLength(1),
        );
        expect(
          await target.customSelect('SELECT * FROM account_pockets').get(),
          hasLength(1),
        );
        expect(
          await target.customSelect('SELECT * FROM account_movements').get(),
          hasLength(tombstoneFirst ? 0 : 1),
        );
        expect(
          await target.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        // Retry through a new store instance retains one event and the pause.
        await _store(target).receiveCloudRecord(
          cloudRecord: second,
          payload: secondPayload,
          nowMicros: 102,
        );
        expect(
          await target.customSelect('SELECT * FROM sync_quarantine').get(),
          hasLength(1),
        );
        await expectLater(
          VaultLogicalSnapshotStore(
            target,
          ).capture(_vault, requireSyncSettled: false),
          throwsA(isA<VaultSnapshotUnresolvedSyncConflict>()),
        );
        final current = await target
            .customSelect('SELECT revision FROM accounts')
            .getSingle();
        final revision = await _store(target, cipher: cipher)
            .requestAccountRestore(
              vaultId: _vault,
              accountId: _account,
              expectedRevision: current.read<int>('revision'),
              nowMicros: 103,
            );
        expect(revision, 3);
        expect(await targetStore.replayCandidates(_vault), isEmpty);
        expect(
          await DriftSyncMetadataStore(
            target,
          ).readyMutations(vaultId: _vault, nowMicros: 104),
          everyElement(
            isA<PendingSyncMutation>().having(
              (row) => row.entityType,
              'type',
              SyncEntityType.account,
            ),
          ),
        );
        if (tombstoneFirst) {
          await target.customStatement(
            "CREATE TRIGGER fail_replay BEFORE UPDATE ON sync_quarantine WHEN NEW.replay_state = 'replayed' BEGIN SELECT RAISE(ABORT, 'test replay failure'); END",
          );
          final interrupted = await SyncEngine(
            cloud: cloud,
            metadata: DriftSyncMetadataStore(target),
            aggregates: targetStore,
            cipher: cipher,
          ).synchronize(vaultId: _vault, deviceId: 'receiver');
          expect(interrupted.status, SyncRunStatus.permanentFailure);
          expect(await targetStore.unresolvedQuarantineCount(_vault), 1);
          expect(
            await target
                .customSelect('SELECT * FROM sync_dependency_pause')
                .get(),
            hasLength(1),
          );
          expect(
            await target.customSelect('SELECT * FROM account_movements').get(),
            isEmpty,
          );
          await target.customStatement('DROP TRIGGER fail_replay');
        }
        final recovered = await SyncEngine(
          cloud: cloud,
          metadata: DriftSyncMetadataStore(target),
          aggregates: targetStore,
          cipher: cipher,
        ).synchronize(vaultId: _vault, deviceId: 'receiver');
        expect(recovered.status, SyncRunStatus.succeeded);
        expect(recovered.conflicts, 0);
        expect(recovered.pushed, tombstoneFirst ? 0 : 1);
        expect(
          await target
              .customSelect('SELECT * FROM sync_dependency_pause')
              .get(),
          isEmpty,
        );
        expect(await targetStore.unresolvedQuarantineCount(_vault), 0);
        expect(
          await target.customSelect('SELECT * FROM account_movements').get(),
          hasLength(1),
        );
        expect(
          (await target
                  .customSelect('SELECT deleted_at FROM accounts')
                  .getSingle())
              .readNullable<int>('deleted_at'),
          isNull,
        );
        expect(
          await target.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await VaultLogicalSnapshotStore(
          target,
        ).capture(_vault, requireSyncSettled: false);
        // A delivered event remains resolved even after restarting the store.
        final cursorBeforeDuplicate = (await DriftSyncMetadataStore(
          target,
        ).cursor(_vault)).lastServerVersion;
        final duplicate = await _store(target).receiveCloudRecord(
          cloudRecord: second,
          payload: secondPayload,
          nowMicros: 200,
        );
        expect(duplicate.conflictDetected, isFalse);
        expect(await targetStore.unresolvedQuarantineCount(_vault), 0);
        expect(
          await target
              .customSelect('SELECT * FROM sync_dependency_pause')
              .get(),
          isEmpty,
        );
        expect(
          (await DriftSyncMetadataStore(
            target,
          ).cursor(_vault)).lastServerVersion,
          cursorBeforeDuplicate,
        );
      },
    );
  }

  test(
    'quarantine and cursor roll back together when pause persistence fails',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      await _movement(db);
      final store = _store(db);
      final account = (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final payload = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'deleted_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final record = await _cloudRecord(
        SyncPayloadCipher(keys: keys),
        payload,
        1,
      );
      await db.customStatement(
        "CREATE TRIGGER fail_pause BEFORE INSERT ON sync_dependency_pause BEGIN SELECT RAISE(ABORT, 'test pause failure'); END",
      );
      await expectLater(
        store.receiveCloudRecord(
          cloudRecord: record,
          payload: payload,
          nowMicros: 100,
        ),
        throwsA(anything),
      );
      expect(
        await db.customSelect('SELECT * FROM sync_quarantine').get(),
        isEmpty,
      );
      expect(
        (await DriftSyncMetadataStore(db).cursor(_vault)).lastServerVersion,
        0,
      );
      expect(
        (await db.customSelect('SELECT deleted_at FROM accounts').getSingle())
            .readNullable<int>('deleted_at'),
        isNull,
      );
    },
  );

  test(
    'old queued movements are paused after dependency backfill and coalescing',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      await _movement(db);
      final metadata = DriftSyncMetadataStore(db);
      await metadata.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
        baseRevision: null,
        baseSnapshot: null,
        newRevision: 1,
        operation: SyncOperation.upsert,
      );
      // Simulate an outbox row persisted by the older schema/client.
      await db.customStatement('DELETE FROM sync_outbox_dependencies');
      final account = (await _store(db).loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final tombstone = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'deleted_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final record = await _cloudRecord(
        SyncPayloadCipher(keys: keys),
        tombstone,
        1,
      );
      await _store(db).receiveCloudRecord(
        cloudRecord: record,
        payload: tombstone,
        nowMicros: 100,
      );
      expect(
        await metadata.readyMutations(vaultId: _vault, nowMicros: 200),
        isEmpty,
      );
      await metadata.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
        baseRevision: null,
        baseSnapshot: null,
        newRevision: 2,
        operation: SyncOperation.upsert,
      );
      expect(
        await DriftSyncMetadataStore(
          db,
        ).readyMutations(vaultId: _vault, nowMicros: 200),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT * FROM sync_outbox').get(),
        hasLength(1),
      );
      expect(
        await db.customSelect('SELECT * FROM sync_outbox_dependencies').get(),
        hasLength(1),
      );
    },
  );

  test('legacy active account cannot reactivate an archived pocket', () async {
    final db = EquisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final store = _store(db);
    final active = (await store.loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!;
    await db.customStatement(
      'UPDATE account_pockets SET archived = 1 WHERE id = ?',
      [_pocket],
    );
    final legacy = {...active, 'format_version': 1};
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    final record = await _cloudRecord(cipher, legacy, 1);
    final result = await SyncEngine(
      cloud: _PullCloud([record]),
      metadata: DriftSyncMetadataStore(db),
      aggregates: store,
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(result.status, SyncRunStatus.succeeded);
    expect(result.conflicts, 1);
    expect(
      (await db
              .customSelect('SELECT archived FROM account_pockets')
              .getSingle())
          .read<int>('archived'),
      1,
    );
    expect(
      (await DriftSyncMetadataStore(db).cursor(_vault)).lastServerVersion,
      1,
    );
    expect(
      await db.customSelect('SELECT * FROM sync_quarantine').get(),
      hasLength(1),
    );
  });

  test(
    'accepted restore with a lost push response is confirmed by authenticated pull',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      await _movement(db);
      final store = _store(db);
      final account = (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final tombstone = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'deleted_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      final record = await _cloudRecord(cipher, tombstone, 1);
      final cloud = _PullCloud([record]);
      await store.receiveCloudRecord(
        cloudRecord: record,
        payload: tombstone,
        nowMicros: 100,
      );
      await _store(db, cipher: cipher).requestAccountRestore(
        vaultId: _vault,
        accountId: _account,
        expectedRevision: 1,
        nowMicros: 101,
      );
      cloud.loseNextAcceptedResponse = true;
      final failed = await SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(db),
        aggregates: store,
        cipher: cipher,
      ).synchronize(vaultId: _vault, deviceId: 'receiver');
      expect(failed.status, SyncRunStatus.offline);
      expect(await store.unresolvedQuarantineCount(_vault), 1);
      final recovered = await SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(db),
        aggregates: _store(db),
        cipher: cipher,
      ).synchronize(vaultId: _vault, deviceId: 'receiver');
      expect(recovered.status, SyncRunStatus.succeeded);
      expect(recovered.conflicts, 0);
      expect(
        await db.customSelect('SELECT * FROM sync_dependency_pause').get(),
        isEmpty,
      );
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
      expect(
        await db.customSelect('SELECT * FROM account_movements').get(),
        hasLength(1),
      );
    },
  );

  test(
    'restore rebase preserves its permitted operation and prevents a second request',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);
      await _movement(db);
      final store = _store(db);
      final account = (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final tombstone = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'deleted_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      await store.receiveCloudRecord(
        cloudRecord: await _cloudRecord(cipher, tombstone, 1),
        payload: tombstone,
        nowMicros: 100,
      );
      expect(
        (await store.accountRecoveryStates(_vault)).single.restorationPending,
        isFalse,
      );
      await _store(db, cipher: cipher).requestAccountRestore(
        vaultId: _vault,
        accountId: _account,
        expectedRevision: 1,
        nowMicros: 103,
      );
      final pending = (await DriftSyncMetadataStore(db).pendingFor(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      await expectLater(
        store.requestAccountRestore(
          vaultId: _vault,
          accountId: _account,
          expectedRevision: 3,
          nowMicros: 104,
        ),
        throwsA(isA<SyncAggregateFormatException>()),
      );
      final competing = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 3,
          'updated_at': 102,
          'name': 'Remote edit',
        },
      };
      await store.receiveCloudRecord(
        cloudRecord: await _cloudRecord(cipher, competing, 2),
        payload: competing,
        nowMicros: 105,
      );
      final rebased = (await DriftSyncMetadataStore(db).pendingFor(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      expect(rebased.operationId, pending.operationId);
      expect(rebased.baseRevision, 3);
      expect(rebased.newRevision, 4);
      final pause = await db
          .customSelect('SELECT * FROM sync_dependency_pause')
          .getSingle();
      expect(
        pause.read<String>('permitted_restore_operation_id'),
        pending.operationId,
      );
      expect(pause.read<int>('accepted_restore_revision'), 3);
      expect(
        (await store.accountRecoveryStates(_vault)).single.restorationPending,
        isTrue,
      );
      expect(
        await store.accountRecoveryStates(
          '018f47c2-9b72-7cc1-8b83-5d0fead0a099',
        ),
        isEmpty,
      );
    },
  );

  test(
    'fresh receiver imports tombstone parent before earlier movement',
    () async {
      final source = EquisDatabase(NativeDatabase.memory());
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(target.close);
      await _seed(source);
      await _movement(source);
      await _seed(target);
      await target.customStatement('DELETE FROM account_pockets');
      await target.customStatement('DELETE FROM accounts');
      final sourceStore = _store(source);
      final transaction = (await sourceStore.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
      ))!;
      final account = (await sourceStore.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final tombstone = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'deleted_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      final cloud = _PullCloud([
        await _cloudRecord(cipher, transaction, 1),
        await _cloudRecord(cipher, tombstone, 2),
      ]);
      final store = _store(target);
      final result = await SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(target),
        aggregates: store,
        cipher: cipher,
        pullTransaction: (action) => target.transaction(() async {
          await target.customStatement('PRAGMA defer_foreign_keys = ON');
          await action();
        }),
      ).synchronize(vaultId: _vault, deviceId: 'fresh');
      expect(result.status, SyncRunStatus.succeeded);
      expect(result.conflicts, 1);
      expect(cloud.acknowledged, [2]);
      expect(
        (await target
                .customSelect('SELECT deleted_at FROM accounts')
                .getSingle())
            .readNullable<int>('deleted_at'),
        100,
      );
      expect(
        await target.customSelect('SELECT * FROM account_movements').get(),
        isEmpty,
      );
      expect(
        await target.customSelect('SELECT * FROM sync_quarantine').get(),
        hasLength(1),
      );
      expect(
        await target.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'empty account tombstone is pushed and applied on another device',
    () async {
      final source = EquisDatabase(NativeDatabase.memory());
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(target.close);
      await _seed(source);
      await _seed(target);
      final sourceMeta = DriftSyncMetadataStore(source);
      final accountId = EntityId.parse(_account);
      final vaultId = EntityId.parse(_vault);
      const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
      final removed = await DriftAccountAggregateRepository(source).remove(
        vaultId: vaultId,
        accountId: accountId,
        expectedRevision: 1,
        now: now,
      );
      expect(removed.aggregate.account.deletedAt, isNotNull);
      await sourceMeta.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
        baseRevision: null,
        baseSnapshot: null,
        newRevision: 2,
        operation: SyncOperation.delete,
      );
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      final cloud = _PullCloud([]);
      final sender = await SyncEngine(
        cloud: cloud,
        metadata: sourceMeta,
        aggregates: _store(source),
        cipher: cipher,
      ).synchronize(vaultId: _vault, deviceId: 'sender');
      expect(sender.status, SyncRunStatus.succeeded);
      expect(sender.pushed, 1);
      expect(cloud.records.single.record.isDeleted, isTrue);
      final receiver = await SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(target),
        aggregates: _store(target),
        cipher: cipher,
        pullTransaction: (action) => target.transaction(action),
      ).synchronize(vaultId: _vault, deviceId: 'receiver');
      expect(receiver.status, SyncRunStatus.succeeded);
      expect(receiver.pulled, 1);
      final fetched = await DriftAccountAggregateRepository(
        target,
      ).findAggregate(accountId);
      expect(fetched!.account.deletedAt, isNotNull);
      expect(fetched.pockets.single.id.value, _pocket);
      expect(
        await target.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test('pull rollback never acknowledges a cursor', () async {
    final source = EquisDatabase(NativeDatabase.memory());
    final target = EquisDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await _seed(source);
    await _seed(target);
    final account = (await _store(source).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!;
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    final cloud = _PullCloud([await _cloudRecord(cipher, account, 1)]);
    final result = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(target),
      aggregates: _store(target),
      cipher: cipher,
      pullTransaction: (action) => target.transaction(() async {
        await action();
        throw StateError('simulated commit failure');
      }),
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(result.status, SyncRunStatus.permanentFailure);
    expect(cloud.acknowledged, isEmpty);
    expect(
      (await DriftSyncMetadataStore(target).cursor(_vault)).lastServerVersion,
      0,
    );
  });

  test('invalid authenticated account pockets do not advance cursor', () async {
    final db = EquisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final account = (await _store(db).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!;
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    for (final pockets in [
      <Map<String, Object?>>[],
      [
        for (final row
            in (account['children'] as Map)['account_pockets'] as List)
          {...row as Map<String, Object?>, 'is_default': 0},
      ],
    ]) {
      final invalid = {
        ...account,
        'children': {
          ...account['children'] as Map<String, Object?>,
          'account_pockets': pockets,
        },
      };
      final record = await _cloudRecord(cipher, invalid, 1);
      await expectLater(
        _store(db).receiveCloudRecord(
          cloudRecord: record,
          payload: invalid,
          nowMicros: 100,
        ),
        throwsA(isA<SyncAggregateFormatException>()),
      );
      expect(
        (await DriftSyncMetadataStore(db).cursor(_vault)).lastServerVersion,
        0,
      );
      expect(
        await db.customSelect('SELECT * FROM sync_quarantine').get(),
        isEmpty,
      );
    }
  });

  test('recurring rule referencing a tombstoned account is quarantined', () async {
    final source = EquisDatabase(NativeDatabase.memory());
    final target = EquisDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await _seed(source);
    await _seed(target);
    final ruleId = EntityId.generate().value;
    await source.customStatement(
      "INSERT INTO recurring_rules (id, vault_id, name, rrule, timezone, starts_on, created_at, updated_at) "
      "VALUES (?, ?, 'Monthly', 'FREQ=MONTHLY', 'UTC', '2026-09-01', 1, 1)",
      [ruleId, _vault],
    );
    await source.customStatement(
      'INSERT INTO recurring_template_movements '
      '(id, recurring_rule_id, account_pocket_id, amount_minor) VALUES (?, ?, ?, 100)',
      [EntityId.generate().value, ruleId, _pocket],
    );
    final payload = (await _store(source).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.recurringRule,
      recordId: ruleId,
    ))!;
    final account = (await _store(source).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!;
    final tombstone = {
      ...account,
      'root': {
        ...account['root'] as Map<String, Object?>,
        'revision': 2,
        'deleted_at': 100,
        'updated_at': 100,
      },
    };
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    final cloud = _PullCloud([
      await _cloudRecord(cipher, tombstone, 1),
      await _cloudRecord(cipher, payload, 2),
    ]);
    final result = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(target),
      aggregates: _store(target),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(result.status, SyncRunStatus.succeeded);
    expect(result.conflicts, 1);
    expect(cloud.acknowledged, [2]);
    expect(
      (await DriftSyncMetadataStore(target).cursor(_vault)).lastServerVersion,
      2,
    );
    expect(
      await target.customSelect('SELECT * FROM recurring_rules').get(),
      isEmpty,
    );
    expect(
      await target.customSelect('SELECT * FROM sync_quarantine').get(),
      hasLength(1),
    );
    expect(
      await target.customSelect('SELECT * FROM sync_dependency_pause').get(),
      hasLength(1),
    );
    expect(
      await target.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    await _store(target, cipher: cipher).requestAccountRestore(
      vaultId: _vault,
      accountId: _account,
      expectedRevision: 2,
      nowMicros: 103,
    );
    final recovered = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(target),
      aggregates: _store(target),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(recovered.status, SyncRunStatus.succeeded);
    expect(
      await target.customSelect('SELECT * FROM recurring_rules').get(),
      hasLength(1),
    );
    expect(await _store(target).unresolvedQuarantineCount(_vault), 0);
    expect(
      await target.customSelect('SELECT * FROM sync_dependency_pause').get(),
      isEmpty,
    );
    expect(
      await target.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('late historical movement cannot change an archived account', () async {
    final source = EquisDatabase(NativeDatabase.memory());
    final target = EquisDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await _seed(source);
    await _seed(target);
    await _movement(source);
    await target.customStatement(
      "UPDATE accounts SET archived = 1, closed_on = '2026-08-23', revision = 2 "
      'WHERE id = ?',
      [_account],
    );
    final payload = (await _store(source).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.transaction,
      recordId: _transaction,
    ))!;
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    final cloud = _PullCloud([await _cloudRecord(cipher, payload, 1)]);
    final result = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(target),
      aggregates: _store(target),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(result.status, SyncRunStatus.succeeded);
    expect(result.conflicts, 1);
    expect(cloud.acknowledged, [1]);
    expect(
      await target.customSelect('SELECT * FROM account_movements').get(),
      isEmpty,
    );
    expect(
      await target.customSelect('SELECT * FROM sync_quarantine').get(),
      hasLength(1),
    );
    expect(
      await target.customSelect('SELECT * FROM sync_dependency_pause').get(),
      hasLength(1),
    );
    expect(
      await target.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test(
    'remote archive waits while receiver has an unpaid local movement',
    () async {
      final source = EquisDatabase(NativeDatabase.memory());
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(target.close);
      await _seed(source);
      await _seed(target);
      await _movement(target);
      final account = (await _store(source).loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final archive = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'archived': 1,
          'closed_on': '2026-08-23',
          'updated_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      final cloud = _PullCloud([await _cloudRecord(cipher, archive, 1)]);
      final result = await SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(target),
        aggregates: _store(target),
        cipher: cipher,
      ).synchronize(vaultId: _vault, deviceId: 'receiver');
      expect(result.status, SyncRunStatus.succeeded);
      expect(result.conflicts, 1);
      expect(cloud.acknowledged, [1]);
      expect(
        (await target.customSelect('SELECT archived FROM accounts').getSingle())
            .read<int>('archived'),
        0,
      );
      expect(
        await target.customSelect('SELECT * FROM account_movements').get(),
        hasLength(1),
      );
      expect(
        await target.customSelect('SELECT * FROM sync_quarantine').get(),
        hasLength(1),
      );
      expect(
        await target.customSelect('SELECT * FROM sync_dependency_pause').get(),
        hasLength(1),
      );
    },
  );

  for (final alreadyArchived in [false, true]) {
    test(
      'late pull cannot archive past balanced local history ($alreadyArchived)',
      () async {
        final source = EquisDatabase(NativeDatabase.memory());
        final target = EquisDatabase(NativeDatabase.memory());
        addTearDown(source.close);
        addTearDown(target.close);
        await _seed(source);
        await _seed(target);
        await _movement(target);
        final balancingId = EntityId.generate().value;
        await target.customStatement(
          "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, revision, created_at, updated_at) "
          "VALUES (?, ?, 'adjustment', '2026-08-22', 1, 1, 2)",
          [balancingId, _vault],
        );
        await target.customStatement(
          'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) '
          'VALUES (?, ?, ?, -100)',
          [EntityId.generate().value, balancingId, _pocket],
        );
        if (alreadyArchived) {
          await target.customStatement(
            "UPDATE accounts SET archived = 1, closed_on = '2026-08-25', revision = 2 WHERE id = ?",
            [_account],
          );
        }
        final account = (await _store(source).loadPayload(
          vaultId: _vault,
          entityType: SyncEntityType.account,
          recordId: _account,
        ))!;
        final archive = {
          ...account,
          'root': {
            ...account['root'] as Map<String, Object?>,
            'revision': alreadyArchived ? 3 : 2,
            'archived': 1,
            'closed_on': '2026-08-21',
            'updated_at': 100,
          },
        };
        final keys = VaultKeyManager(store: _Secrets());
        await keys.loadOrCreateMasterKey();
        final cipher = SyncPayloadCipher(keys: keys);
        final cloud = _PullCloud([await _cloudRecord(cipher, archive, 1)]);
        final result = await SyncEngine(
          cloud: cloud,
          metadata: DriftSyncMetadataStore(target),
          aggregates: _store(target),
          cipher: cipher,
        ).synchronize(vaultId: _vault, deviceId: 'receiver');
        expect(result.status, SyncRunStatus.succeeded);
        expect(result.conflicts, 1);
        expect(cloud.acknowledged, [1]);
        expect(
          (await target
                  .customSelect('SELECT archived FROM accounts')
                  .getSingle())
              .read<int>('archived'),
          alreadyArchived ? 1 : 0,
        );
        if (alreadyArchived) {
          expect(
            (await target
                    .customSelect('SELECT closed_on FROM accounts')
                    .getSingle())
                .read<String>('closed_on'),
            '2026-08-25',
          );
        }
        expect(
          await target.customSelect('SELECT * FROM account_movements').get(),
          hasLength(2),
        );
        expect(
          await target.customSelect('SELECT * FROM sync_quarantine').get(),
          hasLength(1),
        );
      },
    );
  }

  test('remote tombstone preserves a pocket attachment link', () async {
    final source = EquisDatabase(NativeDatabase.memory());
    final target = EquisDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await _seed(source);
    await _seed(target);
    await source.customStatement(
      'UPDATE account_pockets SET archived = 1 WHERE id = ?',
      [_pocket],
    );
    final attachmentId = EntityId.generate().value;
    await target.customStatement(
      "INSERT INTO attachments (id, vault_id, byte_size, sha256, created_at, updated_at) VALUES (?, ?, 1, 'hash', 1, 1)",
      [attachmentId, _vault],
    );
    await target.customStatement(
      "INSERT INTO attachment_links (attachment_id, entity_type, entity_id) VALUES (?, 'account_pocket', ?)",
      [attachmentId, _pocket],
    );
    final account = (await _store(source).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!;
    final tombstone = {
      ...account,
      'root': {
        ...account['root'] as Map<String, Object?>,
        'revision': 2,
        'deleted_at': 100,
        'updated_at': 100,
      },
    };
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    final cloud = _PullCloud([await _cloudRecord(cipher, tombstone, 1)]);
    final result = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(target),
      aggregates: _store(target),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(result.status, SyncRunStatus.succeeded);
    expect(result.conflicts, 1);
    expect(cloud.acknowledged, [1]);
    expect(
      (await target.customSelect('SELECT deleted_at FROM accounts').getSingle())
          .readNullable<int>('deleted_at'),
      isNull,
    );
    expect(
      await target.customSelect('SELECT * FROM attachment_links').get(),
      hasLength(1),
    );
    expect(
      await target.customSelect('SELECT * FROM sync_quarantine').get(),
      hasLength(1),
    );
    expect(
      await target.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    await _store(target, cipher: cipher).requestAccountRestore(
      vaultId: _vault,
      accountId: _account,
      expectedRevision: 1,
      nowMicros: 103,
    );
    expect(
      (await target
              .customSelect('SELECT archived FROM account_pockets')
              .getSingle())
          .read<int>('archived'),
      1,
    );
  });

  test('restore preserves pockets known only by the tombstone sender', () async {
    final sender = EquisDatabase(NativeDatabase.memory());
    final receiver = EquisDatabase(NativeDatabase.memory());
    addTearDown(sender.close);
    addTearDown(receiver.close);
    await _seed(sender);
    await _seed(receiver);
    const extraPocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a008';
    await sender.customStatement(
      "UPDATE accounts SET name = 'Remote account' WHERE id = ?",
      [_account],
    );
    await receiver.customStatement(
      "UPDATE accounts SET name = 'Stale account' WHERE id = ?",
      [_account],
    );
    for (final db in [sender, receiver]) {
      await db.customStatement(
        "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('USD', 'usd', 'USD', 2)",
      );
    }
    await sender.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code) VALUES (?, ?, 'USD')",
      [extraPocket, _account],
    );
    await sender.customStatement(
      "UPDATE account_pockets SET name = 'Remote pocket' WHERE id = ?",
      [_pocket],
    );
    await receiver.customStatement(
      "UPDATE account_pockets SET name = 'Stale pocket' WHERE id = ?",
      [_pocket],
    );
    await sender.customStatement(
      'INSERT INTO credit_card_profiles (account_id, default_closing_day, default_due_day) '
      'VALUES (?, 15, 5)',
      [_account],
    );
    await receiver.customStatement(
      'INSERT INTO credit_card_profiles (account_id, default_closing_day, default_due_day) '
      'VALUES (?, 20, 10)',
      [_account],
    );
    await sender.customStatement(
      'INSERT INTO credit_card_limits (account_pocket_id, limit_minor) VALUES (?, 500000)',
      [_pocket],
    );
    await receiver.customStatement(
      'INSERT INTO credit_card_limits (account_pocket_id, limit_minor) VALUES (?, 100000)',
      [_pocket],
    );
    await _movement(receiver);
    final account = (await _store(sender).loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!;
    final tombstone = {
      ...account,
      'root': {
        ...account['root'] as Map<String, Object?>,
        'revision': 2,
        'deleted_at': 100,
        'updated_at': 100,
      },
    };
    await sender.customStatement(
      'UPDATE accounts SET deleted_at = 100, updated_at = 100, revision = 2 WHERE id = ?',
      [_account],
    );
    final keys = VaultKeyManager(store: _Secrets());
    await keys.loadOrCreateMasterKey();
    final cipher = SyncPayloadCipher(keys: keys);
    final cloud = _PullCloud([await _cloudRecord(cipher, tombstone, 1)]);
    final first = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(receiver),
      aggregates: _store(receiver),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(first.status, SyncRunStatus.succeeded);
    expect(first.conflicts, 1);
    await _store(receiver, cipher: cipher).requestAccountRestore(
      vaultId: _vault,
      accountId: _account,
      expectedRevision: 1,
      nowMicros: 103,
    );
    expect(
      (await receiver
              .customSelect('SELECT id FROM account_pockets ORDER BY id')
              .get())
          .map((row) => row.read<String>('id')),
      containsAll([_pocket, extraPocket]),
    );
    expect(
      (await receiver.customSelect('SELECT name FROM accounts').getSingle())
          .read<String>('name'),
      'Remote account',
    );
    expect(
      (await receiver
              .customSelect(
                'SELECT name FROM account_pockets WHERE id = ?',
                variables: [Variable(_pocket)],
              )
              .getSingle())
          .read<String>('name'),
      'Remote pocket',
    );
    expect(
      (await receiver
              .customSelect(
                'SELECT default_closing_day FROM credit_card_profiles',
              )
              .getSingle())
          .read<int>('default_closing_day'),
      15,
    );
    expect(
      (await receiver
              .customSelect('SELECT limit_minor FROM credit_card_limits')
              .getSingle())
          .read<int>('limit_minor'),
      500000,
    );
    final restored = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(receiver),
      aggregates: _store(receiver),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'receiver');
    expect(restored.status, SyncRunStatus.succeeded);
    expect(await _store(receiver).unresolvedQuarantineCount(_vault), 0);
    final onSender = await SyncEngine(
      cloud: cloud,
      metadata: DriftSyncMetadataStore(sender),
      aggregates: _store(sender),
      cipher: cipher,
    ).synchronize(vaultId: _vault, deviceId: 'sender');
    expect(onSender.status, SyncRunStatus.succeeded);
    expect(onSender.conflicts, 0);
    expect(
      (await sender.customSelect('SELECT deleted_at FROM accounts').getSingle())
          .readNullable<int>('deleted_at'),
      isNull,
    );
    expect(
      (await sender.customSelect('SELECT id FROM account_pockets').get()).map(
        (row) => row.read<String>('id'),
      ),
      containsAll([_pocket, extraPocket]),
    );
    expect(
      await sender.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    expect(
      await receiver.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test(
    'restore keeps one default pocket with a pending local account edit',
    () async {
      final source = EquisDatabase(NativeDatabase.memory());
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(target.close);
      await _seed(source);
      await _seed(target);
      const extraPocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a008';
      await source.customStatement(
        "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('USD', 'usd', 'USD', 2)",
      );
      await target.customStatement(
        "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('USD', 'usd', 'USD', 2)",
      );
      await source.customStatement(
        'UPDATE account_pockets SET is_default = 0 WHERE id = ?',
        [_pocket],
      );
      await source.customStatement(
        "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'USD', 1)",
        [extraPocket, _account],
      );
      await _movement(target);
      final account = (await _store(source).loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
      ))!;
      final tombstone = {
        ...account,
        'root': {
          ...account['root'] as Map<String, Object?>,
          'revision': 2,
          'deleted_at': 100,
          'updated_at': 100,
        },
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      final cloud = _PullCloud([await _cloudRecord(cipher, tombstone, 1)]);
      final first = await SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(target),
        aggregates: _store(target),
        cipher: cipher,
      ).synchronize(vaultId: _vault, deviceId: 'receiver');
      expect(first.status, SyncRunStatus.succeeded);
      expect(first.conflicts, 1);
      await DriftSyncMetadataStore(target).enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: _account,
        baseRevision: 1,
        baseSnapshot: null,
        newRevision: 2,
        operation: SyncOperation.upsert,
      );
      await _store(target, cipher: cipher).requestAccountRestore(
        vaultId: _vault,
        accountId: _account,
        expectedRevision: 1,
        nowMicros: 103,
      );
      final defaults = await target
          .customSelect('SELECT id FROM account_pockets WHERE is_default = 1')
          .get();
      expect(defaults.map((row) => row.read<String>('id')), [_pocket]);
      expect(
        await target.customSelect('SELECT * FROM account_pockets').get(),
        hasLength(2),
      );
      expect(
        await target.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

Future<void> _checkArchivedBootstrap({
  required bool balanced,
  bool onArchiveDay = false,
}) async {
  final source = EquisDatabase(NativeDatabase.memory());
  final target = EquisDatabase(NativeDatabase.memory());
  addTearDown(source.close);
  addTearDown(target.close);
  await _seed(source);
  await _seed(target);
  await target.customStatement('DELETE FROM account_pockets');
  await target.customStatement('DELETE FROM accounts');
  await _movement(source);
  final opposite = EntityId.generate().value;
  await source.customStatement(
    "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, revision, created_at, updated_at) VALUES (?, ?, 'adjustment', '2026-08-22', 1, 1, 2)",
    [opposite, _vault],
  );
  await source.customStatement(
    'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) VALUES (?, ?, ?, -100)',
    [EntityId.generate().value, opposite, _pocket],
  );
  if (onArchiveDay) {
    await source.customStatement(
      "UPDATE transactions SET financial_date = '2026-08-23'",
    );
  }
  final store = _store(source);
  final payloads = <Map<String, Object?>>[];
  for (final id in [_transaction, if (balanced) opposite]) {
    payloads.add(
      (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: id,
      ))!,
    );
  }
  await source.customStatement(
    "UPDATE accounts SET archived = 1, closed_on = '2026-08-23', revision = 2 WHERE id = ?",
    [_account],
  );
  payloads.add(
    (await store.loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.account,
      recordId: _account,
    ))!,
  );
  final keys = VaultKeyManager(store: _Secrets());
  await keys.loadOrCreateMasterKey();
  final cipher = SyncPayloadCipher(keys: keys);
  final records = <CloudSyncRecord>[];
  for (var index = 0; index < payloads.length; index++) {
    records.add(await _cloudRecord(cipher, payloads[index], index + 1));
  }
  final cloud = _PullCloud(records);
  final engine = SyncEngine(
    cloud: cloud,
    metadata: DriftSyncMetadataStore(target),
    aggregates: _store(target),
    cipher: cipher,
  );
  final result = await engine.synchronize(
    vaultId: _vault,
    deviceId: 'new-device',
  );
  if (!balanced) {
    expect(result.status, SyncRunStatus.permanentFailure);
    expect(await target.customSelect('SELECT * FROM accounts').get(), isEmpty);
    expect(
      await target.customSelect('SELECT * FROM account_movements').get(),
      isEmpty,
    );
    expect(
      (await DriftSyncMetadataStore(target).cursor(_vault)).lastServerVersion,
      0,
    );
    expect(cloud.acknowledged, isEmpty);
    return;
  }
  expect(result.status, SyncRunStatus.succeeded);
  expect(result.conflicts, 0);
  expect(
    await target.customSelect('SELECT * FROM account_movements').get(),
    hasLength(2),
  );
  final account = await target
      .customSelect('SELECT archived, closed_on FROM accounts')
      .getSingle();
  expect(account.read<int>('archived'), 1);
  expect(account.read<String>('closed_on'), '2026-08-23');
  expect(
    await target.customSelect('SELECT * FROM sync_quarantine').get(),
    isEmpty,
  );
  expect(await target.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  expect(cloud.acknowledged, [3]);
  final late = EntityId.generate().value;
  await source.customStatement(
    "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, revision, created_at, updated_at) VALUES (?, ?, 'adjustment', '2026-08-21', 1, 1, 2)",
    [late, _vault],
  );
  await source.customStatement(
    'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) VALUES (?, ?, ?, 1)',
    [EntityId.generate().value, late, _pocket],
  );
  final latePayload = (await store.loadPayload(
    vaultId: _vault,
    entityType: SyncEntityType.transaction,
    recordId: late,
  ))!;
  records.add(await _cloudRecord(cipher, latePayload, 4));
  final next = await engine.synchronize(
    vaultId: _vault,
    deviceId: 'new-device',
  );
  expect(next.conflicts, 1);
  expect(
    await target.customSelect('SELECT * FROM account_movements').get(),
    hasLength(2),
  );
  expect(
    await target.customSelect('SELECT * FROM sync_quarantine').get(),
    hasLength(1),
  );
}

// More than one page of partially restored dependencies must not prevent an
// independent, fully restored account from recovering its authenticated event.
Future<void> _checkReplaySelectionDoesNotStarve() async {
  final db = EquisDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await _seed(db);
  final other = EntityId.generate().value;
  final ready = EntityId.generate().value;
  for (final account in [other, ready]) {
    await db.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, revision, created_at, updated_at) VALUES (?, ?, 'Account', 'checking', 'asset', 2, 1, 1)",
      [account, _vault],
    );
  }
  await db.customStatement('UPDATE accounts SET revision = 2 WHERE id = ?', [
    _account,
  ]);
  final keys = VaultKeyManager(store: _Secrets());
  await keys.loadOrCreateMasterKey();
  final cipher = SyncPayloadCipher(keys: keys);
  await _movement(db);
  final payload = (await _store(db).loadPayload(
    vaultId: _vault,
    entityType: SyncEntityType.transaction,
    recordId: _transaction,
  ))!;
  final record = await _cloudRecord(cipher, payload, 1);
  final envelope = record.record.envelope;
  final eventIds = <String>[];
  for (var version = 1; version <= 101; version++) {
    final id = EntityId.generate().value;
    eventIds.add(id);
    await db.customStatement(
      'INSERT INTO sync_quarantine (event_id, vault_id, server_version, entity_type, entity_id, entity_revision, parent_account_id, authenticated_envelope, reason, detected_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, 1)',
      [
        id,
        _vault,
        version,
        'transaction',
        _transaction,
        version <= 100 ? _account : ready,
        jsonEncode({
          'cipher_version': envelope.cipherVersion,
          'key_version': envelope.keyVersion,
          'nonce': base64Encode(envelope.nonce),
          'cipher_text': base64Encode(envelope.cipherText),
          'mac': base64Encode(envelope.mac),
          'is_deleted': false,
          'blocked_account_ids': version <= 100 ? [_account, other] : [ready],
        }),
        'test_dependency',
      ],
    );
  }
  for (final account in [_account, other, ready]) {
    await db.customStatement(
      'INSERT INTO sync_dependency_pause (vault_id, account_id, blocking_event_id, accepted_restore_revision, created_at) VALUES (?, ?, ?, ?, 1)',
      [
        _vault,
        account,
        account == ready ? eventIds.last : eventIds.first,
        account == other ? null : 2,
      ],
    );
  }
  final candidates = await _store(db).replayCandidates(_vault);
  expect(candidates.map((value) => value.serverVersion), [101]);
  expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
}

class _PullCloud implements CloudSyncGateway, CloudSyncAggregateFormatGateway {
  _PullCloud(this.records);
  final List<CloudSyncRecord> records;
  final acknowledged = <int>[];
  bool loseNextAcceptedResponse = false;
  @override
  Future<void> activateAggregateFormat2({required String vaultId}) async {}
  @override
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  }) async {}
  @override
  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  }) async {
    final results = <CloudPushResult>[];
    for (final mutation in mutations) {
      final identity = mutation.record.identity;
      final prior =
          records
              .where(
                (record) =>
                    record.record.identity.recordId == identity.recordId,
              )
              .toList()
            ..sort(
              (left, right) =>
                  left.serverVersion.compareTo(right.serverVersion),
            );
      final expected = prior.isEmpty ? 0 : prior.last.record.identity.revision;
      if ((mutation.expectedRevision ?? 0) != expected) {
        results.add(
          CloudPushResult(
            operationId: mutation.operationId,
            status: CloudPushStatus.conflict,
            serverVersion: prior.isEmpty ? null : prior.last.serverVersion,
            remoteRevision: expected,
          ),
        );
      } else {
        final version = records.isEmpty
            ? 1
            : records
                      .map((record) => record.serverVersion)
                      .reduce((a, b) => a > b ? a : b) +
                  1;
        records.add(
          CloudSyncRecord(record: mutation.record, serverVersion: version),
        );
        results.add(
          CloudPushResult(
            operationId: mutation.operationId,
            status: CloudPushStatus.accepted,
            revision: identity.revision,
            serverVersion: version,
          ),
        );
      }
    }
    if (loseNextAcceptedResponse &&
        results.any((row) => row.status == CloudPushStatus.accepted)) {
      loseNextAcceptedResponse = false;
      throw const CloudSyncFailure(CloudSyncFailureCode.network);
    }
    return results;
  }

  @override
  Future<List<CloudSyncRecord>> pull({
    required String vaultId,
    required int afterServerVersion,
    int limit = 100,
  }) async => records
      .where((record) => record.serverVersion > afterServerVersion)
      .take(limit)
      .toList();
  @override
  Future<CloudSyncRecord?> fetch({
    required String vaultId,
    required String entityType,
    required String recordId,
  }) async => null;
  @override
  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  }) async {
    acknowledged.add(serverVersion);
  }
}

DriftSyncAggregateStore _store(EquisDatabase db, {SyncPayloadCipher? cipher}) =>
    DriftSyncAggregateStore(
      database: db,
      metadata: DriftSyncMetadataStore(db),
      cipher: cipher,
    );

Future<CloudSyncRecord> _cloudRecord(
  SyncPayloadCipher cipher,
  Map<String, Object?> payload,
  int serverVersion,
) async {
  final root = payload['root'] as Map;
  final identity = SyncRecordIdentity(
    vaultId: _vault,
    recordId: root['id'] as String,
    entityType: payload['entity_type'] as String,
    revision: root['revision'] as int,
  );
  return CloudSyncRecord(
    record: EncryptedSyncRecord(
      identity: identity,
      envelope: await cipher.encrypt(identity: identity, payload: payload),
      isDeleted: root['deleted_at'] != null,
    ),
    serverVersion: serverVersion,
  );
}

Future<void> _seed(EquisDatabase db) async {
  await db.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'brl', 'BRL', 2)",
  );
  await db.customStatement(
    "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
    [_vault],
  );
  await db.customStatement(
    "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Account', 'checking', 'asset', 1, 1)",
    [_account, _vault],
  );
  await db.customStatement(
    "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'BRL', 1)",
    [_pocket, _account],
  );
}

Future<void> _movement(EquisDatabase db) async {
  await db.customStatement(
    "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, revision, created_at, updated_at) VALUES (?, ?, 'adjustment', '2026-08-22', 1, 1, 2)",
    [_transaction, _vault],
  );
  await db.customStatement(
    'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) VALUES (?, ?, ?, 100)',
    [EntityId.generate().value, _transaction, _pocket],
  );
}

const _vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const _account = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
const _pocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
const _transaction = '018f47c2-9b72-7cc1-8b83-5d0fead0a007';

class _Secrets implements SecureStringStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
