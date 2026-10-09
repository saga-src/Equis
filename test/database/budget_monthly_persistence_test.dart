import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:equis/application/ports/budget_repository.dart';
import 'package:equis/application/ports/sync_conflict_resolver.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide BudgetMonthlyConfiguration;
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:equis/infrastructure/portability/vault_plaintext_exporter.dart';
import 'package:equis/infrastructure/persistence/database/budget_monthly_history_migration.dart';
import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/repositories/drift_budget_repository.dart';
import 'package:equis/infrastructure/sync/budget_sync_history.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_mutation_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const account = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
final created = UtcInstant.fromDateTime(
  DateTime.utc(2026, 8, 1, 1),
); // July in São Paulo.

Future<void> seed(EquisDatabase db) async {
  await db.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'brl', 'R\$', 2)",
  );
  await db.customStatement(
    "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'America/Sao_Paulo', 1, 1)",
    [vault],
  );
  await db.customStatement(
    "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Bank', 'checking', 'asset', 1, 1)",
    [account, vault],
  );
}

DriftSyncAggregateStore store(EquisDatabase db) =>
    DriftSyncAggregateStore(database: db, metadata: DriftSyncMetadataStore(db));
DriftBudgetRepository repository(EquisDatabase db) => DriftBudgetRepository(
  db,
  syncRecorder: DriftSyncMutationRecorder(
    database: db,
    aggregates: store(db),
    metadata: DriftSyncMetadataStore(db),
  ),
);
BudgetDefinition definition() => BudgetDefinition(
  id: EntityId.generate(),
  vaultId: EntityId.parse(vault),
  name: 'Monthly',
  currency: CurrencyCode.brl,
  limitMinor: 100000,
  periodType: BudgetPeriodType.monthly,
  warningThresholdBps: 8000,
  scope: BudgetScope(),
  createdAt: created,
  updatedAt: created,
);
BudgetMonthlyConfiguration config(
  int amount, {
  bool withAccount = false,
  BudgetLimitMethod method = BudgetLimitMethod.fixed,
}) => BudgetMonthlyConfiguration(
  amountMinor: amount,
  limitMethod: method,
  warningThresholdBps: 7500,
  scope: BudgetScope(accountIds: {if (withAccount) EntityId.parse(account)}),
);
Future<BudgetDefinition> edit(
  DriftBudgetRepository repo,
  BudgetDefinition budget,
  int month,
  int amount, {
  BudgetMonthlyEditScope scope = BudgetMonthlyEditScope.onlyMonth,
  bool withAccount = false,
}) => repo.saveMonthlyEdit(
  budgetId: budget.id,
  vaultId: budget.vaultId,
  expectedRevision: budget.revision,
  month: BudgetMonth(2026, month),
  configuration: config(amount, withAccount: withAccount),
  scope: scope,
  now: UtcInstant.fromDateTime(DateTime.utc(2026, 8, 20)),
);
Future<Map<String, Object?>> payload(
  EquisDatabase db,
  BudgetDefinition budget,
) async => (await store(db).loadPayload(
  vaultId: vault,
  entityType: SyncEntityType.budget,
  recordId: budget.id.value,
))!;

void main() {
  late EquisDatabase db;
  setUp(() async {
    db = EquisDatabase(NativeDatabase.memory());
    await seed(db);
  });
  tearDown(() => db.close());

  for (final resolution in [
    SyncConflictResolution.keepLocal,
    SyncConflictResolution.keepRemote,
    SyncConflictResolution.merged,
  ]) {
    test(
      'ordinary budget conflict preserves current revision after later edits: $resolution',
      () async {
        final repo = repository(db);
        var budget = definition();
        await repo.save(budget);
        budget = await edit(repo, budget, 8, 120000);
        final reviewed = await payload(db, budget);
        final remote = {
          ...reviewed,
          'root': {...reviewed['root'] as Map, 'name': 'Remote'},
        };
        await store(db).preserveConflict(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
          baseRevision: 1,
          localRevision: 2,
          remoteRevision: 2,
          serverVersion: 2,
          baseSnapshot: {},
          localSnapshot: reviewed,
          remoteSnapshot: remote,
        );
        budget = await edit(repo, budget, 9, 150000);
        final conflict = (await store(db).unresolved(vault)).single;
        if (resolution == SyncConflictResolution.keepRemote) {
          await expectLater(
            store(db).resolve(conflictId: conflict.id, resolution: resolution),
            throwsA(isA<SyncAggregateFormatException>()),
          );
          expect((await repo.find(budget.id))!.revision, 3);
          expect((await store(db).unresolved(vault)).single.id, conflict.id);
          expect(
            (await repo.loadMonthlyHistory(
              budget.id,
            )).resolve(BudgetMonth(2026, 9))!.amountMinor,
            150000,
          );
          return;
        }
        await store(db).resolve(
          conflictId: conflict.id,
          resolution: resolution,
          mergedSnapshot: resolution == SyncConflictResolution.merged
              ? await payload(db, budget)
              : null,
        );
        expect((await repo.find(budget.id))!.revision, 4);
        if (resolution != SyncConflictResolution.keepRemote) {
          expect(
            (await repo.loadMonthlyHistory(
              budget.id,
            )).resolve(BudgetMonth(2026, 9))!.amountMinor,
            150000,
          );
        } else {
          expect((await repo.find(budget.id))!.name, 'Remote');
        }
        final pending = (await DriftSyncMetadataStore(db).pendingFor(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
        ))!;
        expect(pending.baseRevision, 2);
        expect(pending.newRevision, 4);
      },
    );
  }

  test(
    'fresh budget conflict can keep remote with a rebased revision',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      budget = await edit(repo, budget, 8, 120000);
      final reviewed = await payload(db, budget);
      final remote = {
        ...reviewed,
        'root': {...reviewed['root'] as Map, 'name': 'Remote'},
      };
      await store(db).preserveConflict(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        baseRevision: 1,
        localRevision: 2,
        remoteRevision: 2,
        serverVersion: 2,
        baseSnapshot: {},
        localSnapshot: reviewed,
        remoteSnapshot: remote,
      );
      final conflict = (await store(db).unresolved(vault)).single;
      await store(db).resolve(
        conflictId: conflict.id,
        resolution: SyncConflictResolution.keepRemote,
      );
      expect((await repo.find(budget.id))!.revision, 3);
      expect((await repo.find(budget.id))!.name, 'Remote');
      expect(await store(db).unresolved(vault), isEmpty);
    },
  );

  test('direct budget merge rebases above newer local revision', () async {
    final repo = repository(db);
    var budget = definition();
    await repo.save(budget);
    budget = await edit(repo, budget, 8, 120000);
    final remote = await payload(db, budget);
    budget = await edit(repo, budget, 9, 150000);
    await expectLater(
      store(db).applyMerged(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        remoteRevision: 2,
        serverVersion: 2,
        remoteSnapshot: remote,
        mergedSnapshot: remote,
      ),
      throwsA(isA<SyncAggregateFormatException>()),
    );
    expect((await repo.find(budget.id))!.revision, 3);
    await store(db).applyMerged(
      vaultId: vault,
      entityType: SyncEntityType.budget,
      recordId: budget.id.value,
      remoteRevision: 2,
      serverVersion: 2,
      remoteSnapshot: remote,
      mergedSnapshot: await payload(db, budget),
    );
    expect((await repo.find(budget.id))!.revision, 4);
    expect(
      (await repo.loadMonthlyHistory(
        budget.id,
      )).resolve(BudgetMonth(2026, 9))!.amountMinor,
      150000,
    );
  });

  test(
    're-pulling the exact acknowledged legacy base leaves the new monthly edit eligible to push',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      final legacy = await payload(db, budget);
      await store(db).applyRemote(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        revision: 1,
        serverVersion: 1,
        isDeleted: false,
        payload: legacy,
      );
      await db.customStatement(
        "INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, 'fixture', 1, 1)",
        [vault],
      );
      budget = await edit(repo, budget, 8, 120000);
      final before = await payload(db, budget);
      final result = await store(db).reconcileRemote(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        revision: 1,
        serverVersion: 1,
        isDeleted: false,
        payload: legacy,
      );
      expect(result.conflictDetected, isFalse);
      expect(await payload(db, budget), before);
      expect(
        (await DriftSyncMetadataStore(db).pendingFor(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
        ))!.newRevision,
        2,
      );
      expect(
        await store(db).canPush(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
        ),
        isTrue,
      );
    },
  );

  test(
    'failed child insertion rolls back root, configurations and outbox together',
    () async {
      await db.customStatement(
        "INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, 'fixture', 1, 1)",
        [vault],
      );
      final repo = repository(db);
      final budget = definition();
      await repo.save(budget);
      final before = await payload(db, budget);
      await db.customStatement(
        "CREATE TRIGGER reject_history_account BEFORE INSERT ON budget_monthly_accounts BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      await expectLater(
        edit(repo, budget, 8, 120000, withAccount: true),
        throwsA(anything),
      );
      expect(await payload(db, budget), before);
      expect(
        (await DriftSyncMetadataStore(db).pendingFor(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
        ))!.newRevision,
        1,
      );
    },
  );

  test(
    'first-month replacement remains format 2; flags cannot be reset',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      budget = await edit(
        repo,
        budget,
        7,
        100000,
        scope: BudgetMonthlyEditScope.fromMonth,
      );
      expect((await repo.loadMonthlyHistory(budget.id)).entries, hasLength(1));
      final advanced = await payload(db, budget);
      expect(advanced['format_version'], 2);
      final downgrade = {
        ...advanced,
        'root': {...advanced['root'] as Map, 'monthly_history_edited': 0},
      };
      await expectLater(
        store(db).applyRemote(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
          revision: budget.revision,
          serverVersion: 2,
          isDeleted: false,
          payload: downgrade,
        ),
        throwsA(isA<SyncAggregateFormatException>()),
      );
      // Threshold matches the legacy base, making an otherwise valid downgrade.
      final structurallyValid = {
        ...downgrade,
        'root': {...downgrade['root'] as Map, 'warning_threshold_bps': 7500},
      };
      await expectLater(
        store(db).applyRemote(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
          revision: budget.revision,
          serverVersion: 2,
          isDeleted: false,
          payload: structurallyValid,
        ),
        throwsA(isA<BudgetHistoryCompatibilityException>()),
      );
      expect(await payload(db, budget), advanced);
    },
  );

  test(
    'historical accounts remain references but only resolved/future configurations block archive',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      budget = await edit(repo, budget, 8, 110000, withAccount: true);
      budget = await edit(repo, budget, 9, 150000, withAccount: true);
      expect(
        await hasActiveMonthlyBudgetAccountReference(
          db,
          account,
          BudgetMonth(2026, 8).start,
        ),
        isTrue,
      );
      expect(
        await hasActiveMonthlyBudgetAccountReference(
          db,
          account,
          BudgetMonth(2026, 10).start,
        ),
        isFalse,
      );
      await db.customStatement(
        'UPDATE accounts SET archived = 1 WHERE id = ?',
        [account],
      );
      final advanced = await payload(db, budget);
      expect(
        await BudgetSyncHistory(db).hasActiveAccountReference(
          advanced,
          account,
          DateTime.utc(2026, 10, 7).microsecondsSinceEpoch,
        ),
        isFalse,
      );
      expect(
        await db.customSelect('SELECT * FROM budget_monthly_accounts').get(),
        hasLength(2),
      );
      // Archived historical bindings remain restorable.
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await VaultLogicalSnapshotStore(
        target,
      ).restore(await VaultLogicalSnapshotStore(db).capture(vault));
      expect(
        (await repository(target).loadMonthlyHistory(
          budget.id,
        )).resolve(BudgetMonth(2026, 9))!.scope.accountIds,
        {EntityId.parse(account)},
      );
    },
  );

  test(
    'JSON export preserves monthly history and malformed v8 dates roll back restore',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      budget = await edit(repo, budget, 8, 120000, withAccount: true);
      final directory = await Directory.systemTemp.createTemp(
        'equis-history-json-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/vault.json');
      await VaultPlaintextExporter(
        VaultLogicalSnapshotStore(db),
      ).exportJson(vaultId: vault, destination: file);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final snapshot = VaultLogicalSnapshot.fromJson(json);
      expect(snapshot.tables['budget_monthly_accounts'], hasLength(1));
      expect(snapshot.tables.keys, isNot(contains('sync_outbox')));
      final invalidTables = {
        ...snapshot.tables,
        'budget_monthly_configurations': [
          for (final row in snapshot.tables['budget_monthly_configurations']!)
            {...row, 'month_start': '2026-02-30'},
        ],
      };
      final invalid = VaultLogicalSnapshot(
        schemaVersion: 8,
        createdAtMicros: 1,
        tables: invalidTables,
      );
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await expectLater(
        VaultLogicalSnapshotStore(target).restore(invalid),
        throwsA(anything),
      );
      expect(await target.customSelect('SELECT * FROM vaults').get(), isEmpty);
    },
  );

  test(
    'authenticated legacy pull saves protected conflict and cursor atomically',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      final legacy = await payload(db, budget);
      budget = await edit(repo, budget, 8, 120000);
      final remote = {
        ...legacy,
        'root': {...legacy['root'] as Map, 'revision': 99},
      };
      final keys = VaultKeyManager(store: _Secrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      final identity = SyncRecordIdentity(
        vaultId: vault,
        entityType: 'budget',
        recordId: budget.id.value,
        revision: 99,
      );
      final envelope = await cipher.encrypt(
        identity: identity,
        payload: remote,
      );
      final clear = await cipher.decrypt(
        identity: identity,
        envelope: envelope,
      );
      final record = CloudSyncRecord(
        record: EncryptedSyncRecord(
          identity: identity,
          envelope: envelope,
          isDeleted: false,
        ),
        serverVersion: 7,
      );
      final before = await payload(db, budget);
      await db.customStatement(
        "CREATE TRIGGER reject_cursor BEFORE INSERT ON sync_cursors BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      await expectLater(
        store(
          db,
        ).receiveCloudRecord(cloudRecord: record, payload: clear, nowMicros: 1),
        throwsA(anything),
      );
      expect(await store(db).unresolved(vault), isEmpty);
      expect(await payload(db, budget), before);
      await db.customStatement('DROP TRIGGER reject_cursor');
      expect(
        (await store(db).receiveCloudRecord(
          cloudRecord: record,
          payload: clear,
          nowMicros: 1,
        )).conflictDetected,
        isTrue,
      );
      expect(
        (await DriftSyncMetadataStore(db).cursor(vault)).lastServerVersion,
        7,
      );
      expect(
        (await store(db).unresolved(vault)).single.protectionReason,
        'protected_budget_history',
      );
      expect(await payload(db, budget), before);
    },
  );

  test(
    'isolated and future edits preserve prior months and future overrides',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      expect(
        (await repo.loadMonthlyHistory(
          budget.id,
        )).resolve(BudgetMonth(2026, 7))!.amountMinor,
        100000,
      );
      budget = await edit(repo, budget, 8, 110000);
      budget = await edit(repo, budget, 9, 150000, withAccount: true);
      budget = await edit(
        repo,
        budget,
        8,
        120000,
        scope: BudgetMonthlyEditScope.fromMonth,
      );
      final history = await repo.loadMonthlyHistory(budget.id);
      expect(history.resolve(BudgetMonth(2026, 7))!.amountMinor, 100000);
      expect(history.resolve(BudgetMonth(2026, 8))!.amountMinor, 120000);
      expect(history.resolve(BudgetMonth(2026, 9))!.amountMinor, 150000);
      expect(history.resolve(BudgetMonth(2026, 9))!.scope.accountIds, {
        EntityId.parse(account),
      });
      expect(history.resolve(BudgetMonth(2026, 10))!.amountMinor, 120000);
      await repo.save(budget.revise(deletedAt: created, at: created));
      expect(await repo.listForVault(budget.vaultId), isEmpty);
      expect(
        await repo.listForVault(budget.vaultId, includeDeleted: true),
        hasLength(1),
      );
      expect((await repo.loadMonthlyHistory(budget.id)).entries, hasLength(4));
    },
  );

  test(
    'CAS, ownership, inactive account and precreation edits roll back root/history/outbox',
    () async {
      await db.customStatement(
        "INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, 'fixture-user', 1, 1)",
        [vault],
      );
      final repo = repository(db);
      final old = definition();
      await repo.save(old);
      final current = await edit(repo, old, 8, 120000, withAccount: true);
      final before = await payload(db, current);
      final pending = (await DriftSyncMetadataStore(db).pendingFor(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: old.id.value,
      ))!;
      await expectLater(
        edit(repo, old, 9, 1),
        throwsA(isA<BudgetRevisionConflict>()),
      );
      await expectLater(edit(repo, current, 6, 1), throwsArgumentError);
      await db.customStatement(
        'UPDATE accounts SET archived = 1 WHERE id = ?',
        [account],
      );
      await expectLater(
        edit(repo, current, 9, 1, withAccount: true),
        throwsStateError,
      );
      final bad = config(1);
      await expectLater(
        repo.saveMonthlyEdit(
          budgetId: current.id,
          vaultId: EntityId.generate(),
          expectedRevision: current.revision,
          month: BudgetMonth(2026, 9),
          configuration: bad,
          scope: BudgetMonthlyEditScope.onlyMonth,
          now: created,
        ),
        throwsStateError,
      );
      expect(await payload(db, current), before);
      expect(
        (await DriftSyncMetadataStore(db).pendingFor(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: old.id.value,
        ))!.newRevision,
        pending.newRevision,
      );
      expect(
        (await db
                .customSelect(
                  'SELECT account_id FROM sync_outbox_dependencies WHERE operation_id = ?',
                  variables: [Variable(pending.operationId)],
                )
                .get())
            .single
            .read<String>('account_id'),
        account,
      );
    },
  );

  for (final syncEnabled in [false, true]) {
    test(
      'legacy higher revision is protected (pending: $syncEnabled); resolution reads current local',
      () async {
        if (syncEnabled) {
          await db.customStatement(
            "INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, 'fixture', 1, 1)",
            [vault],
          );
        }
        final repo = repository(db);
        var budget = definition();
        await repo.save(budget);
        final legacy = await payload(db, budget);
        expect(legacy['format_version'], 1);
        budget = await edit(repo, budget, 8, 120000);
        final before = await payload(db, budget);
        final remote = {
          ...legacy,
          'root': {...legacy['root'] as Map, 'revision': 99},
        };
        await expectLater(
          store(db).applyRemote(
            vaultId: vault,
            entityType: SyncEntityType.budget,
            recordId: budget.id.value,
            revision: 99,
            serverVersion: 2,
            isDeleted: false,
            payload: remote,
          ),
          throwsA(isA<BudgetHistoryCompatibilityException>()),
        );
        expect(await payload(db, budget), before);
        expect(
          (await store(db).reconcileRemote(
            vaultId: vault,
            entityType: SyncEntityType.budget,
            recordId: budget.id.value,
            revision: 99,
            serverVersion: 2,
            isDeleted: false,
            payload: remote,
          )).conflictDetected,
          isTrue,
        );
        expect(
          await store(db).canPush(
            vaultId: vault,
            entityType: SyncEntityType.budget,
            recordId: budget.id.value,
          ),
          isFalse,
        );
        final conflict = (await store(db).unresolved(vault)).single;
        expect(conflict.protectionReason, 'protected_budget_history');
        if (syncEnabled) {
          expect(
            (await DriftSyncMetadataStore(db).pendingFor(
              vaultId: vault,
              entityType: SyncEntityType.budget,
              recordId: budget.id.value,
            ))!.newRevision,
            budget.revision,
          );
        }
        await expectLater(
          store(db).applyMerged(
            vaultId: vault,
            entityType: SyncEntityType.budget,
            recordId: budget.id.value,
            remoteRevision: 99,
            serverVersion: 2,
            remoteSnapshot: remote,
            mergedSnapshot: before,
          ),
          throwsA(isA<BudgetHistoryCompatibilityException>()),
        );
        await expectLater(
          store(db).resolve(
            conflictId: conflict.id,
            resolution: SyncConflictResolution.keepRemote,
          ),
          throwsA(isA<SyncAggregateFormatException>()),
        );
        budget = await edit(repo, budget, 9, 150000);
        await store(db).resolve(
          conflictId: conflict.id,
          resolution: SyncConflictResolution.keepLocal,
        );
        final updated = (await repo.find(budget.id))!;
        expect(updated.revision, 100);
        expect(
          (await repo.loadMonthlyHistory(
            budget.id,
          )).resolve(BudgetMonth(2026, 9))!.amountMinor,
          150000,
        );
        final pending = (await DriftSyncMetadataStore(db).pendingFor(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
        ))!;
        expect(pending.baseRevision, 99);
        expect((await payload(db, budget))['format_version'], 2);
      },
    );
  }

  test(
    'new sync format and tombstone round trip complete history; malformed children and downgrade rejected',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      budget = await edit(repo, budget, 9, 150000, withAccount: true);
      final other = EquisDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await seed(other);
      final advanced = await payload(db, budget);
      await store(other).applyRemote(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        revision: budget.revision,
        serverVersion: 1,
        isDeleted: false,
        payload: advanced,
      );
      expect(await payload(other, budget), advanced);
      final invalid = {
        ...advanced,
        'children': {
          ...advanced['children'] as Map,
          'budget_monthly_accounts': [
            {
              'configuration_id': EntityId.generate().value,
              'account_id': account,
            },
          ],
        },
      };
      await expectLater(
        store(other).applyRemote(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
          revision: budget.revision,
          serverVersion: 2,
          isDeleted: false,
          payload: invalid,
        ),
        throwsA(isA<SyncAggregateFormatException>()),
      );
      expect(await payload(other, budget), advanced);
      await repo.save(budget.revise(deletedAt: created, at: created));
      budget = (await repo.find(budget.id))!;
      final deleted = await payload(db, budget);
      await store(other).applyRemote(
        vaultId: vault,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        revision: budget.revision,
        serverVersion: 3,
        isDeleted: true,
        payload: deleted,
      );
      expect((await repository(other).find(budget.id))!.deletedAt, isNotNull);
      expect(
        (await repository(other).loadMonthlyHistory(budget.id)).entries,
        hasLength(2),
      );
      await expectLater(
        store(other).applyRemote(
          vaultId: vault,
          entityType: SyncEntityType.budget,
          recordId: budget.id.value,
          revision: 2,
          serverVersion: 4,
          isDeleted: false,
          payload: advanced,
        ),
        throwsA(isA<BudgetHistoryCompatibilityException>()),
      );
    },
  );

  test(
    'v8 backup preserves history/deleted roots; real v7 shape reconstructs base and malformed v8 rolls back',
    () async {
      final repo = repository(db);
      var budget = definition();
      await repo.save(budget);
      final base = await VaultLogicalSnapshotStore(db).capture(vault);
      final legacyTables = {
        for (final entry in base.tables.entries)
          if (!budgetHistoryTables.contains(entry.key) &&
              entry.key != 'recurring_rule_versions')
            entry.key: [
              for (final row in entry.value)
                {...row}
                  ..remove('monthly_history_edited')
                  ..remove('schedule_history_edited'),
            ],
      };
      final legacy = VaultLogicalSnapshot.fromJson({
        ...base.toJson(),
        'schema_version': 7,
        'tables': legacyTables,
      });
      final oldTarget = EquisDatabase(NativeDatabase.memory());
      addTearDown(oldTarget.close);
      await VaultLogicalSnapshotStore(oldTarget).restore(legacy);
      expect(
        (await repository(oldTarget).loadMonthlyHistory(
          budget.id,
        )).resolve(BudgetMonth(2026, 7))!.amountMinor,
        100000,
      );
      budget = await edit(repo, budget, 8, 120000, withAccount: true);
      await repo.save(budget.revise(deletedAt: created, at: created));
      final snapshot = await VaultLogicalSnapshotStore(db).capture(vault);
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await VaultLogicalSnapshotStore(target).restore(snapshot);
      expect((await repository(target).find(budget.id))!.deletedAt, isNotNull);
      expect(
        (await repository(target).loadMonthlyHistory(
          budget.id,
        )).resolve(BudgetMonth(2026, 8))!.amountMinor,
        120000,
      );
      final broken = {
        ...snapshot.toJson(),
        'tables': {...snapshot.tables}..remove('budget_monthly_tags'),
      };
      expect(
        () => VaultLogicalSnapshot.fromJson(broken),
        throwsA(isA<VaultSnapshotFormatException>()),
      );
    },
  );

  test(
    'offline restart keeps daily method, rate and exception filters',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'equis-budget-history-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/fixture.sqlite');
      var disk = EquisDatabase(NativeDatabase(file));
      await seed(disk);
      var budget = definition();
      await repository(disk).save(budget);
      budget = await repository(disk).saveMonthlyEdit(
        budgetId: budget.id,
        vaultId: budget.vaultId,
        expectedRevision: 1,
        month: BudgetMonth(2026, 8),
        configuration: config(
          1000,
          method: BudgetLimitMethod.calendarDay,
          withAccount: true,
        ),
        scope: BudgetMonthlyEditScope.fromMonth,
        now: created,
      );
      await disk.close();
      disk = EquisDatabase(NativeDatabase(file));
      try {
        final configuration = (await repository(
          disk,
        ).loadMonthlyHistory(budget.id)).resolve(BudgetMonth(2026, 8))!;
        expect(configuration.amountMinor, 1000);
        expect(configuration.limitFor(BudgetMonth(2026, 8)), 31000);
        expect(configuration.scope.accountIds, {EntityId.parse(account)});
        expect(
          (await repository(disk).find(budget.id))!.monthlyHistoryEdited,
          isTrue,
        );
      } finally {
        await disk.close();
      }
    },
  );
}

final class _Secrets implements SecureStringStore {
  final Map<String, String> values = {};
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
