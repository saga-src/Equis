import 'package:drift/drift.dart';

import '../../application/ports/budget_repository.dart';
import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftBudgetRepository implements BudgetRepository {
  const DriftBudgetRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(BudgetDefinition budget) =>
      syncRecorder?.run(
        vaultId: budget.vaultId.value,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        newRevision: budget.revision,
        operation: budget.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(budget),
      ) ??
      _save(budget);

  Future<void> _save(BudgetDefinition budget) => database.transaction(() async {
    final current = await database
        .customSelect(
          'SELECT revision FROM budgets WHERE id = ?',
          variables: [Variable<String>(budget.id.value)],
          readsFrom: {database.budgets},
        )
        .getSingleOrNull();
    if (current == null) {
      if (budget.revision != 1) {
        throw BudgetRevisionConflict(
          id: budget.id,
          expected: budget.revision - 1,
          actual: null,
        );
      }
      await database.customStatement(
        'INSERT INTO budgets '
        '(id, vault_id, name, currency_code, limit_minor, period_type, '
        'starts_on, ends_on, warning_threshold_bps, rollover_policy, enabled, '
        'revision, created_at, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          budget.id.value,
          budget.vaultId.value,
          budget.name,
          budget.currency.value,
          budget.limitMinor,
          budget.periodType.name,
          budget.startsOn?.toString(),
          budget.endsOn?.toString(),
          budget.warningThresholdBps,
          budget.rolloverPolicy,
          budget.enabled ? 1 : 0,
          budget.revision,
          budget.createdAt.epochMicroseconds,
          budget.updatedAt.epochMicroseconds,
          budget.deletedAt?.epochMicroseconds,
        ],
      );
    } else {
      final actual = current.read<int>('revision');
      final expected = budget.revision - 1;
      if (actual != expected) {
        throw BudgetRevisionConflict(
          id: budget.id,
          expected: expected,
          actual: actual,
        );
      }
      final changed = await database.customUpdate(
        'UPDATE budgets SET name = ?, currency_code = ?, limit_minor = ?, '
        'period_type = ?, starts_on = ?, ends_on = ?, '
        'warning_threshold_bps = ?, rollover_policy = ?, enabled = ?, '
        'revision = ?, updated_at = ?, deleted_at = ? '
        'WHERE id = ? AND revision = ?',
        variables: _variables([
          budget.name,
          budget.currency.value,
          budget.limitMinor,
          budget.periodType.name,
          budget.startsOn?.toString(),
          budget.endsOn?.toString(),
          budget.warningThresholdBps,
          budget.rolloverPolicy,
          budget.enabled ? 1 : 0,
          budget.revision,
          budget.updatedAt.epochMicroseconds,
          budget.deletedAt?.epochMicroseconds,
          budget.id.value,
          expected,
        ]),
        updates: {database.budgets},
      );
      if (changed != 1) {
        throw BudgetRevisionConflict(
          id: budget.id,
          expected: expected,
          actual: actual,
        );
      }
      await database.customStatement(
        'DELETE FROM budget_categories WHERE budget_id = ?',
        [budget.id.value],
      );
      await database.customStatement(
        'DELETE FROM budget_accounts WHERE budget_id = ?',
        [budget.id.value],
      );
      await database.customStatement(
        'DELETE FROM budget_tags WHERE budget_id = ?',
        [budget.id.value],
      );
    }
    for (final category in budget.scope.categories) {
      await database.customStatement(
        'INSERT INTO budget_categories '
        '(budget_id, category_id, include_descendants) VALUES (?, ?, ?)',
        [
          budget.id.value,
          category.categoryId.value,
          category.includeDescendants ? 1 : 0,
        ],
      );
    }
    for (final accountId in budget.scope.accountIds) {
      await database.customStatement(
        'INSERT INTO budget_accounts (budget_id, account_id) VALUES (?, ?)',
        [budget.id.value, accountId.value],
      );
    }
    for (final tagId in budget.scope.tagIds) {
      await database.customStatement(
        'INSERT INTO budget_tags (budget_id, tag_id) VALUES (?, ?)',
        [budget.id.value, tagId.value],
      );
    }
  });

  @override
  Future<BudgetDefinition?> find(EntityId id) async {
    final row = await database
        .customSelect(
          'SELECT * FROM budgets WHERE id = ? AND deleted_at IS NULL',
          variables: [Variable<String>(id.value)],
          readsFrom: {database.budgets},
        )
        .getSingleOrNull();
    return row == null ? null : _load(row.data);
  }

  @override
  Future<List<BudgetDefinition>> listForVault(EntityId vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM budgets WHERE vault_id = ? AND deleted_at IS NULL '
          'ORDER BY enabled DESC, name, id',
          variables: [Variable<String>(vaultId.value)],
          readsFrom: {database.budgets},
        )
        .get();
    final result = <BudgetDefinition>[];
    for (final row in rows) {
      result.add(await _load(row.data));
    }
    return result;
  }

  Future<BudgetDefinition> _load(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final categories = await database
        .customSelect(
          'SELECT category_id, include_descendants FROM budget_categories '
          'WHERE budget_id = ? ORDER BY category_id',
          variables: [Variable<String>(id)],
          readsFrom: {database.budgetCategories},
        )
        .get();
    final accounts = await _scopeIds(
      'SELECT account_id AS id FROM budget_accounts WHERE budget_id = ?',
      id,
      {database.budgetAccounts},
    );
    final tags = await _scopeIds(
      'SELECT tag_id AS id FROM budget_tags WHERE budget_id = ?',
      id,
      {database.budgetTags},
    );
    return BudgetDefinition(
      id: EntityId.parse(id),
      vaultId: EntityId.parse(row['vault_id']! as String),
      name: row['name']! as String,
      currency: CurrencyCode(row['currency_code']! as String),
      limitMinor: row['limit_minor']! as int,
      periodType: BudgetPeriodType.values.byName(row['period_type']! as String),
      startsOn: row['starts_on'] == null
          ? null
          : LocalDate.parse(row['starts_on']! as String),
      endsOn: row['ends_on'] == null
          ? null
          : LocalDate.parse(row['ends_on']! as String),
      warningThresholdBps: row['warning_threshold_bps']! as int,
      rolloverPolicy: row['rollover_policy']! as String,
      enabled: (row['enabled']! as int) == 1,
      revision: row['revision']! as int,
      createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
      updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
      scope: BudgetScope(
        categories: [
          for (final category in categories)
            BudgetCategoryScope(
              categoryId: EntityId.parse(category.read<String>('category_id')),
              includeDescendants:
                  category.read<int>('include_descendants') == 1,
            ),
        ],
        accountIds: accounts,
        tagIds: tags,
      ),
    );
  }

  Future<Set<EntityId>> _scopeIds(
    String sql,
    String budgetId,
    Set<ResultSetImplementation> readsFrom,
  ) async {
    final rows = await database
        .customSelect(
          sql,
          variables: [Variable<String>(budgetId)],
          readsFrom: readsFrom,
        )
        .get();
    return {for (final row in rows) EntityId.parse(row.read<String>('id'))};
  }

  @override
  Future<List<BudgetUsageRow>> loadUsageRows({
    required EntityId vaultId,
    required LocalDate from,
    required LocalDate through,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT parent.id AS transaction_id, split.category_id, '
          'split.currency_code, split.amount_minor, parent.financial_date, '
          'parent.transaction_type, '
          '(SELECT GROUP_CONCAT(DISTINCT account.id) '
          'FROM account_movements AS movement '
          'INNER JOIN account_pockets AS pocket '
          'ON pocket.id = movement.account_pocket_id '
          'INNER JOIN accounts AS account ON account.id = pocket.account_id '
          'WHERE movement.transaction_id = parent.id) AS account_ids, '
          '(SELECT GROUP_CONCAT(tag_id) FROM transaction_tags '
          'WHERE transaction_id = parent.id) AS tag_ids '
          'FROM transaction_splits AS split '
          'INNER JOIN transactions AS parent ON parent.id = split.transaction_id '
          'WHERE parent.vault_id = ? AND parent.financial_date >= ? '
          'AND parent.financial_date <= ? AND parent.status != ? '
          'AND parent.deleted_at IS NULL '
          "AND NOT (parent.status = 'pending' AND parent.recurring_rule_id IS NOT NULL) "
          "AND parent.transaction_type IN ('expense', 'credit_card_purchase', "
          "'fee', 'refund') ORDER BY parent.financial_date, split.id",
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(from.toString()),
            Variable<String>(through.toString()),
            const Variable<String>('cancelled'),
          ],
          readsFrom: {
            database.transactions,
            database.transactionSplits,
            database.accountMovements,
            database.accountPockets,
            database.accounts,
            database.transactionTags,
          },
        )
        .get();
    return [
      for (final row in rows)
        BudgetUsageRow(
          transactionId: EntityId.parse(row.read<String>('transaction_id')),
          categoryId: EntityId.parse(row.read<String>('category_id')),
          currency: CurrencyCode(row.read<String>('currency_code')),
          amountMinor: row.read<int>('amount_minor'),
          date: LocalDate.parse(row.read<String>('financial_date')),
          accountIds: _ids(row.readNullable<String>('account_ids')),
          tagIds: _ids(row.readNullable<String>('tag_ids')),
        ),
    ];
  }

  @override
  Future<Map<EntityId, EntityId?>> loadCategoryParents(EntityId vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT id, parent_id FROM categories '
          'WHERE vault_id = ? AND deleted_at IS NULL',
          variables: [Variable<String>(vaultId.value)],
          readsFrom: {database.categories},
        )
        .get();
    return {
      for (final row in rows)
        EntityId.parse(
          row.read<String>('id'),
        ): row.readNullable<String>('parent_id') == null
            ? null
            : EntityId.parse(row.read<String>('parent_id')),
    };
  }
}

Set<EntityId> _ids(String? value) => value == null || value.isEmpty
    ? const {}
    : value.split(',').map(EntityId.parse).toSet();

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map(Variable<Object>.new).toList(growable: false);
