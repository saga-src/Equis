import 'package:drift/native.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/goals/goal_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_budget_repository.dart';
import 'package:equis/infrastructure/repositories/drift_goal_repository.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_mutation_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = UtcInstant.fromEpochMicroseconds(1786636800123456);

void main() {
  late EquisDatabase database;
  late DriftGoalRepository goals;
  late DriftBudgetRepository budgets;
  late _Fixture fixture;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    fixture = await _seed(database);
    final metadata = DriftSyncMetadataStore(database);
    final recorder = DriftSyncMutationRecorder(
      database: database,
      metadata: metadata,
      aggregates: DriftSyncAggregateStore(
        database: database,
        metadata: metadata,
      ),
    );
    goals = DriftGoalRepository(database, syncRecorder: recorder);
    budgets = DriftBudgetRepository(database, syncRecorder: recorder);
  });
  tearDown(() => database.close());

  for (final deleted in [false, true]) {
    final stateName = deleted ? 'deleted' : 'archived';

    test('new goal and budget reject $stateName account without rows or outbox', () async {
      await _inactivate(database, fixture.accountId, deleted: deleted);
      final before = await _snapshot(database);
      for (final status in [GoalStatus.active, GoalStatus.completed]) {
        await expectLater(
          goals.save(_goal(fixture, status: status)),
          throwsStateError,
        );
      }
      for (final enabled in [false, true]) {
        await expectLater(
          budgets.save(_budget(fixture, enabled: enabled)),
          throwsStateError,
        );
      }
      expect(await _snapshot(database), before);
    });

    test('existing inert links to $stateName account reject reactivation atomically', () async {
      final goal = _goal(fixture, status: GoalStatus.completed);
      final budget = _budget(fixture, enabled: false);
      await goals.save(goal);
      await budgets.save(budget);
      await _inactivate(database, fixture.accountId, deleted: deleted);
      final before = await _snapshot(database);

      await expectLater(
        goals.save(goal.revise(status: GoalStatus.active, at: _now)),
        throwsStateError,
      );
      await expectLater(
        budgets.save(budget.revise(enabled: true, at: _now)),
        throwsStateError,
      );
      expect(await _snapshot(database), before);
    });

    test('unchanged inert links to $stateName account remain historical', () async {
      final goal = _goal(fixture, status: GoalStatus.completed);
      final budget = _budget(fixture, enabled: false);
      await goals.save(goal);
      await budgets.save(budget);
      await _inactivate(database, fixture.accountId, deleted: deleted);

      await goals.save(goal.revise(name: 'Historical goal', at: _now));
      await budgets.save(budget.revise(name: 'Historical budget', at: _now));

      final loadedGoal = await goals.find(goal.id);
      final loadedBudget = await budgets.find(budget.id);
      expect(loadedGoal?.accountPocketIds, {fixture.pocketId});
      expect(loadedGoal?.status, GoalStatus.completed);
      expect(loadedGoal?.revision, 2);
      expect(loadedBudget?.scope.accountIds, {fixture.accountId});
      expect(loadedBudget?.enabled, isFalse);
      expect(loadedBudget?.revision, 2);
      expect(await database.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  }

  test('inert existing goal and budget cannot add a new inactive link', () async {
    final goal = _goal(fixture, status: GoalStatus.completed);
    final budget = _budget(fixture, enabled: false);
    await goals.save(goal);
    await budgets.save(budget);
    final otherAccount = EntityId.generate();
    final otherPocket = EntityId.generate();
    await _account(database, fixture.vaultId, otherAccount, otherPocket);
    await _inactivate(database, otherAccount, deleted: true);
    final before = await _snapshot(database);

    await expectLater(
      goals.save(goal.revise(
        accountPocketIds: {fixture.pocketId, otherPocket},
        at: _now,
      )),
      throwsStateError,
    );
    await expectLater(
      budgets.save(budget.revise(
        scope: BudgetScope(accountIds: {fixture.accountId, otherAccount}),
        at: _now,
      )),
      throwsStateError,
    );
    expect(await _snapshot(database), before);
  });

  test('goal requires active pocket even when account remains active', () async {
    final goal = _goal(fixture, status: GoalStatus.completed);
    await goals.save(goal);
    await database.customStatement(
      'UPDATE account_pockets SET archived = 1 WHERE id = ?',
      [fixture.pocketId.value],
    );
    final before = await _snapshot(database);
    await expectLater(goals.save(_goal(fixture)), throwsStateError);
    await expectLater(
      goals.save(goal.revise(status: GoalStatus.active, at: _now)),
      throwsStateError,
    );
    expect(await _snapshot(database), before);
  });

  test('cross-vault goal and budget references are rejected before writes', () async {
    final otherVault = EntityId.generate();
    final otherAccount = EntityId.generate();
    final otherPocket = EntityId.generate();
    await _vault(database, otherVault);
    await _account(database, otherVault, otherAccount, otherPocket);
    final before = await _snapshot(database);
    await expectLater(
      goals.save(_goal(fixture, pocketIds: {otherPocket})),
      throwsStateError,
    );
    await expectLater(
      budgets.save(_budget(fixture, accountIds: {otherAccount})),
      throwsStateError,
    );
    expect(await _snapshot(database), before);
  });

  test('goal and budget tombstones keep old links and reject resurrection', () async {
    final goal = _goal(fixture, status: GoalStatus.completed);
    final budget = _budget(fixture, enabled: false);
    await goals.save(goal);
    await budgets.save(budget);
    await _inactivate(database, fixture.accountId, deleted: false);

    await goals.save(goal.revise(
      trackingMode: GoalTrackingMode.manual,
      accountPocketIds: {},
      deletedAt: _now,
      at: _now,
    ));
    await budgets.save(budget.revise(
      scope: BudgetScope(),
      deletedAt: _now,
      at: _now,
    ));
    expect(await goals.find(goal.id), isNull);
    expect(await budgets.find(budget.id), isNull);
    final goalLinks = await database.customSelect(
      'SELECT account_pocket_id FROM goal_accounts',
    ).get();
    final budgetLinks = await database.customSelect(
      'SELECT account_id FROM budget_accounts',
    ).get();
    expect(goalLinks.single.read<String>('account_pocket_id'), fixture.pocketId.value);
    expect(budgetLinks.single.read<String>('account_id'), fixture.accountId.value);
    final before = await _snapshot(database);
    await expectLater(
      goals.save(_goal(fixture, id: goal.id, revision: 3, pocketIds: {})),
      throwsStateError,
    );
    await expectLater(
      budgets.save(_budget(fixture, id: budget.id, revision: 3, accountIds: {})),
      throwsStateError,
    );
    expect(await _snapshot(database), before);
  });
}

GoalDefinition _goal(
  _Fixture fixture, {
  EntityId? id,
  int revision = 1,
  GoalStatus status = GoalStatus.active,
  Set<EntityId>? pocketIds,
}) => GoalDefinition(
  id: id ?? EntityId.generate(),
  vaultId: fixture.vaultId,
  name: 'Goal',
  type: GoalType.emergencyFund,
  currency: CurrencyCode.brl,
  targetMinor: 100,
  trackingMode: GoalTrackingMode.manual,
  priority: 0,
  accountPocketIds: pocketIds ?? {fixture.pocketId},
  status: status,
  revision: revision,
  createdAt: _now,
  updatedAt: _now,
);

BudgetDefinition _budget(
  _Fixture fixture, {
  EntityId? id,
  int revision = 1,
  bool enabled = true,
  Set<EntityId>? accountIds,
}) => BudgetDefinition(
  id: id ?? EntityId.generate(),
  vaultId: fixture.vaultId,
  name: 'Budget',
  currency: CurrencyCode.brl,
  limitMinor: 100,
  periodType: BudgetPeriodType.monthly,
  warningThresholdBps: 8000,
  scope: BudgetScope(accountIds: accountIds ?? {fixture.accountId}),
  enabled: enabled,
  revision: revision,
  createdAt: _now,
  updatedAt: _now,
);

Future<_Fixture> _seed(EquisDatabase database) async {
  final fixture = _Fixture(
    vaultId: EntityId.generate(),
    accountId: EntityId.generate(),
    pocketId: EntityId.generate(),
  );
  await _vault(database, fixture.vaultId);
  await database.customStatement(
    'INSERT INTO currencies (code, name_key, symbol, minor_units) '
    "VALUES ('BRL', 'currency.brl', 'BRL', 2)",
  );
  await _account(database, fixture.vaultId, fixture.accountId, fixture.pocketId);
  await database.customStatement(
    'INSERT INTO vault_cloud_bindings '
    '(vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, ?, 1, 1)',
    [fixture.vaultId.value, '11111111-1111-4111-8111-111111111111'],
  );
  return fixture;
}

Future<void> _vault(EquisDatabase database, EntityId id) => database.customStatement(
  'INSERT INTO vaults '
  '(id, name, base_currency_code, timezone, created_at, updated_at) '
  "VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
  [id.value],
);

Future<void> _account(
  EquisDatabase database,
  EntityId vaultId,
  EntityId accountId,
  EntityId pocketId,
) async {
  await database.customStatement(
    'INSERT INTO accounts '
    '(id, vault_id, name, account_type, nature, created_at, updated_at) '
    "VALUES (?, ?, 'Account', 'checking', 'asset', 1, 1)",
    [accountId.value, vaultId.value],
  );
  await database.customStatement(
    'INSERT INTO account_pockets '
    '(id, account_id, currency_code, is_default) VALUES (?, ?, ?, 1)',
    [pocketId.value, accountId.value, 'BRL'],
  );
}

Future<void> _inactivate(
  EquisDatabase database,
  EntityId accountId, {
  required bool deleted,
}) => database.customStatement(
  'UPDATE accounts SET archived = ?, deleted_at = ?, revision = revision + 1 '
  'WHERE id = ?',
  [deleted ? 0 : 1, deleted ? _now.epochMicroseconds : null, accountId.value],
);

Future<Map<String, List<Map<String, Object?>>>> _snapshot(EquisDatabase database) async {
  final snapshot = <String, List<Map<String, Object?>>>{};
  for (final table in [
    'goals',
    'goal_accounts',
    'budgets',
    'budget_accounts',
    'sync_outbox',
    'sync_entity_state',
  ]) {
    snapshot[table] = [
      for (final row in await database.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        row.data,
    ];
  }
  return snapshot;
}

final class _Fixture {
  const _Fixture({required this.vaultId, required this.accountId, required this.pocketId});
  final EntityId vaultId;
  final EntityId accountId;
  final EntityId pocketId;
}
