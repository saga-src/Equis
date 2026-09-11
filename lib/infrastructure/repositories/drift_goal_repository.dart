import 'package:drift/drift.dart';

import '../../application/ports/goal_repository.dart';
import '../../domain/goals/cash_flow_projection.dart';
import '../../domain/goals/goal_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart' hide GoalContribution;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftGoalRepository implements GoalRepository {
  const DriftGoalRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(GoalDefinition goal) =>
      syncRecorder?.run(
        vaultId: goal.vaultId.value,
        entityType: SyncEntityType.goal,
        recordId: goal.id.value,
        newRevision: goal.revision,
        operation: goal.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(goal),
      ) ??
      _save(goal);

  Future<void> _save(GoalDefinition goal) => database.transaction(() async {
    final current = await database
        .customSelect(
          'SELECT revision FROM goals WHERE id = ?',
          variables: [Variable<String>(goal.id.value)],
          readsFrom: {database.goals},
        )
        .getSingleOrNull();
    if (current == null) {
      if (goal.revision != 1) {
        throw GoalRevisionConflict(
          id: goal.id,
          expected: goal.revision - 1,
          actual: null,
        );
      }
      await database.customStatement(
        'INSERT INTO goals '
        '(id, vault_id, name, goal_type, currency_code, target_minor, '
        'starts_on, target_date, planned_monthly_minor, tracking_mode, '
        'priority, status, revision, created_at, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          goal.id.value,
          goal.vaultId.value,
          goal.name,
          goal.type.stored,
          goal.currency.value,
          goal.targetMinor,
          goal.startsOn?.toString(),
          goal.targetDate?.toString(),
          goal.plannedMonthlyMinor,
          goal.trackingMode.stored,
          goal.priority,
          goal.status.name,
          goal.revision,
          goal.createdAt.epochMicroseconds,
          goal.updatedAt.epochMicroseconds,
          goal.deletedAt?.epochMicroseconds,
        ],
      );
    } else {
      final actual = current.read<int>('revision');
      final expected = goal.revision - 1;
      if (actual != expected) {
        throw GoalRevisionConflict(
          id: goal.id,
          expected: expected,
          actual: actual,
        );
      }
      final changed = await database.customUpdate(
        'UPDATE goals SET name = ?, goal_type = ?, currency_code = ?, '
        'target_minor = ?, starts_on = ?, target_date = ?, '
        'planned_monthly_minor = ?, tracking_mode = ?, priority = ?, '
        'status = ?, revision = ?, updated_at = ?, deleted_at = ? '
        'WHERE id = ? AND revision = ?',
        variables: _variables([
          goal.name,
          goal.type.stored,
          goal.currency.value,
          goal.targetMinor,
          goal.startsOn?.toString(),
          goal.targetDate?.toString(),
          goal.plannedMonthlyMinor,
          goal.trackingMode.stored,
          goal.priority,
          goal.status.name,
          goal.revision,
          goal.updatedAt.epochMicroseconds,
          goal.deletedAt?.epochMicroseconds,
          goal.id.value,
          expected,
        ]),
        updates: {database.goals},
      );
      if (changed != 1) {
        throw GoalRevisionConflict(
          id: goal.id,
          expected: expected,
          actual: actual,
        );
      }
      await database.customStatement(
        'DELETE FROM goal_accounts WHERE goal_id = ?',
        [goal.id.value],
      );
    }
    for (final pocketId in goal.accountPocketIds) {
      await database.customStatement(
        'INSERT INTO goal_accounts (goal_id, account_pocket_id) VALUES (?, ?)',
        [goal.id.value, pocketId.value],
      );
    }
  });

  @override
  Future<GoalDefinition?> find(EntityId id) async {
    final row = await database
        .customSelect(
          'SELECT * FROM goals WHERE id = ? AND deleted_at IS NULL',
          variables: [Variable<String>(id.value)],
          readsFrom: {database.goals},
        )
        .getSingleOrNull();
    return row == null ? null : _load(row.data);
  }

  @override
  Future<List<GoalDefinition>> listForVault(EntityId vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM goals WHERE vault_id = ? AND deleted_at IS NULL '
          "AND status != 'cancelled' ORDER BY priority DESC, name, id",
          variables: [Variable<String>(vaultId.value)],
          readsFrom: {database.goals},
        )
        .get();
    final result = <GoalDefinition>[];
    for (final row in rows) {
      result.add(await _load(row.data));
    }
    return result;
  }

  Future<GoalDefinition> _load(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final accounts = await database
        .customSelect(
          'SELECT account_pocket_id FROM goal_accounts WHERE goal_id = ?',
          variables: [Variable<String>(id)],
          readsFrom: {database.goalAccounts},
        )
        .get();
    return GoalDefinition(
      id: EntityId.parse(id),
      vaultId: EntityId.parse(row['vault_id']! as String),
      name: row['name']! as String,
      type: GoalType.fromStorage(row['goal_type']! as String),
      currency: CurrencyCode(row['currency_code']! as String),
      targetMinor: row['target_minor']! as int,
      startsOn: row['starts_on'] == null
          ? null
          : LocalDate.parse(row['starts_on']! as String),
      targetDate: row['target_date'] == null
          ? null
          : LocalDate.parse(row['target_date']! as String),
      plannedMonthlyMinor: row['planned_monthly_minor'] as int?,
      trackingMode: GoalTrackingMode.fromStorage(
        row['tracking_mode']! as String,
      ),
      priority: row['priority']! as int,
      status: GoalStatus.values.byName(row['status']! as String),
      accountPocketIds: {
        for (final account in accounts)
          EntityId.parse(account.read<String>('account_pocket_id')),
      },
      revision: row['revision']! as int,
      createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
      updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
    );
  }

  @override
  Future<void> addContribution(GoalContribution contribution) async {
    final goal = await database
        .customSelect(
          'SELECT vault_id, revision FROM goals WHERE id = ?',
          variables: [Variable(contribution.goalId.value)],
        )
        .getSingle();
    final revision = goal.read<int>('revision') + 1;
    Future<void> action() => database.transaction(() async {
      await database.customStatement(
        'INSERT INTO goal_contributions '
        '(id, goal_id, transaction_id, amount_minor, contribution_date, notes) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          contribution.id.value,
          contribution.goalId.value,
          contribution.transactionId?.value,
          contribution.amountMinor,
          contribution.date.toString(),
          contribution.notes,
        ],
      );
      final changed = await database.customUpdate(
        'UPDATE goals SET revision = ?, updated_at = ? '
        'WHERE id = ? AND revision = ?',
        variables: [
          Variable(revision),
          Variable(DateTime.now().toUtc().microsecondsSinceEpoch),
          Variable(contribution.goalId.value),
          Variable(revision - 1),
        ],
      );
      if (changed != 1) {
        throw GoalRevisionConflict(
          id: contribution.goalId,
          expected: revision - 1,
          actual: null,
        );
      }
    });
    await (syncRecorder?.run(
          vaultId: goal.read<String>('vault_id'),
          entityType: SyncEntityType.goal,
          recordId: contribution.goalId.value,
          newRevision: revision,
          operation: SyncOperation.upsert,
          action: action,
        ) ??
        action());
  }

  @override
  Future<List<GoalContribution>> contributions(
    EntityId goalId, {
    required LocalDate through,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM goal_contributions WHERE goal_id = ? '
          'AND contribution_date <= ? ORDER BY contribution_date, id',
          variables: [
            Variable<String>(goalId.value),
            Variable<String>(through.toString()),
          ],
          readsFrom: {database.goalContributions},
        )
        .get();
    return [
      for (final row in rows)
        GoalContribution(
          id: EntityId.parse(row.read<String>('id')),
          goalId: goalId,
          transactionId: row.readNullable<String>('transaction_id') == null
              ? null
              : EntityId.parse(row.read<String>('transaction_id')),
          amountMinor: row.read<int>('amount_minor'),
          date: LocalDate.parse(row.read<String>('contribution_date')),
          notes: row.readNullable<String>('notes'),
        ),
    ];
  }

  @override
  Future<List<GoalAccountBalance>> linkedBalances(
    GoalDefinition goal, {
    required LocalDate asOf,
  }) async {
    if (goal.accountPocketIds.isEmpty) return const [];
    final placeholders = List.filled(
      goal.accountPocketIds.length,
      '?',
    ).join(',');
    final rows = await database
        .customSelect(
          'SELECT pocket.id, pocket.currency_code, '
          'COALESCE(SUM(CASE WHEN parent.id IS NOT NULL '
          "AND parent.status != 'cancelled' AND parent.deleted_at IS NULL "
          'AND parent.financial_date <= ? '
          "AND NOT (parent.status = 'pending' AND parent.recurring_rule_id IS NOT NULL) "
          'THEN movement.amount_minor ELSE 0 END), 0) AS balance_minor '
          'FROM account_pockets AS pocket '
          'LEFT JOIN account_movements AS movement '
          'ON movement.account_pocket_id = pocket.id '
          'LEFT JOIN transactions AS parent ON parent.id = movement.transaction_id '
          'WHERE pocket.id IN ($placeholders) GROUP BY pocket.id, pocket.currency_code',
          variables: _variables([
            asOf.toString(),
            ...goal.accountPocketIds.map((id) => id.value),
          ]),
          readsFrom: {
            database.accountPockets,
            database.accountMovements,
            database.transactions,
          },
        )
        .get();
    return [
      for (final row in rows)
        GoalAccountBalance(
          pocketId: EntityId.parse(row.read<String>('id')),
          currency: CurrencyCode(row.read<String>('currency_code')),
          balanceMinor: row.read<int>('balance_minor'),
        ),
    ];
  }

  @override
  Future<List<CashFlowSourceRow>> cashFlowSources({
    required EntityId vaultId,
    required LocalDate after,
    required LocalDate through,
  }) async {
    final installments = await database
        .customSelect(
          'SELECT item.id, item.expected_date, item.amount_minor, '
          'plan.currency_code, plan.description '
          'FROM installments AS item INNER JOIN installment_plans AS plan '
          'ON plan.id = item.installment_plan_id '
          'WHERE plan.vault_id = ? AND plan.deleted_at IS NULL '
          "AND plan.status = 'active' AND item.status = 'scheduled' "
          'AND item.expected_date > ? AND item.expected_date <= ?',
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(after.toString()),
            Variable<String>(through.toString()),
          ],
          readsFrom: {database.installments, database.installmentPlans},
        )
        .get();
    final statements = await database
        .customSelect(
          'SELECT statement.id, statement.due_date, pocket.currency_code, '
          'account.name, COALESCE(SUM(CASE WHEN parent.id IS NOT NULL '
          "AND parent.status != 'cancelled' AND parent.deleted_at IS NULL "
          'THEN movement.amount_minor ELSE 0 END), 0) AS due_minor '
          'FROM credit_card_statements AS statement '
          'INNER JOIN account_pockets AS pocket '
          'ON pocket.id = statement.account_pocket_id '
          'INNER JOIN accounts AS account ON account.id = pocket.account_id '
          'LEFT JOIN account_movements AS movement '
          'ON movement.statement_id = statement.id '
          'LEFT JOIN transactions AS parent ON parent.id = movement.transaction_id '
          'WHERE statement.vault_id = ? AND statement.deleted_at IS NULL '
          "AND statement.status NOT IN ('paid', 'cancelled') "
          'AND statement.due_date > ? AND statement.due_date <= ? '
          'GROUP BY statement.id, statement.due_date, pocket.currency_code, account.name',
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(after.toString()),
            Variable<String>(through.toString()),
          ],
          readsFrom: {
            database.creditCardStatements,
            database.accountPockets,
            database.accounts,
            database.accountMovements,
            database.transactions,
          },
        )
        .get();
    return [
      for (final row in installments)
        CashFlowSourceRow(
          id: EntityId.parse(row.read<String>('id')),
          type: CashFlowEventType.installment,
          date: LocalDate.parse(row.read<String>('expected_date')),
          currency: CurrencyCode(row.read<String>('currency_code')),
          amountMinor: -row.read<int>('amount_minor'),
          name: row.readNullable<String>('description'),
        ),
      for (final row in statements)
        if (row.read<int>('due_minor') > 0)
          CashFlowSourceRow(
            id: EntityId.parse(row.read<String>('id')),
            type: CashFlowEventType.cardStatement,
            date: LocalDate.parse(row.read<String>('due_date')),
            currency: CurrencyCode(row.read<String>('currency_code')),
            amountMinor: -row.read<int>('due_minor'),
            name: row.read<String>('name'),
          ),
    ];
  }
}

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map(Variable<Object>.new).toList(growable: false);
