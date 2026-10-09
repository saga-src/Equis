import 'package:drift/drift.dart';

import '../../application/ports/budget_repository.dart';
import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart'
    hide BudgetMonthlyConfiguration;
import '../persistence/database/budget_monthly_history_migration.dart';
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftBudgetRepository implements BudgetRepository {
  const DriftBudgetRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<BudgetMonthlyHistory> loadMonthlyHistory(EntityId budgetId) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM budget_monthly_configurations WHERE budget_id = ? ORDER BY month_start, kind, id',
          variables: [Variable(budgetId.value)],
        )
        .get();
    final entries = <BudgetMonthlyEntry>[];
    for (final row in rows) {
      final id = row.read<String>('id');
      final categories = await database
          .customSelect(
            'SELECT * FROM budget_monthly_categories WHERE configuration_id = ? ORDER BY category_id',
            variables: [Variable(id)],
          )
          .get();
      entries.add(
        BudgetMonthlyEntry(
          id: EntityId.parse(id),
          budgetId: budgetId,
          kind: BudgetMonthlyEntryKind.values.byName(row.read<String>('kind')),
          month: BudgetMonth.parse(row.read<String>('month_start')),
          configuration: BudgetMonthlyConfiguration(
            limitMethod: _limitMethod(row.read<String>('limit_method')),
            amountMinor: row.read<int>('amount_minor'),
            warningThresholdBps: row.read<int>('warning_threshold_bps'),
            scope: BudgetScope(
              categories: [
                for (final category in categories)
                  BudgetCategoryScope(
                    categoryId: EntityId.parse(
                      category.read<String>('category_id'),
                    ),
                    includeDescendants:
                        category.read<int>('include_descendants') == 1,
                  ),
              ],
              accountIds: await _scopeIds(
                'SELECT account_id AS id FROM budget_monthly_accounts WHERE configuration_id = ?',
                id,
                {database.budgetMonthlyAccounts},
              ),
              tagIds: await _scopeIds(
                'SELECT tag_id AS id FROM budget_monthly_tags WHERE configuration_id = ?',
                id,
                {database.budgetMonthlyTags},
              ),
            ),
          ),
        ),
      );
    }
    return BudgetMonthlyHistory(entries);
  }

  @override
  Future<BudgetDefinition> saveMonthlyEdit({
    required EntityId budgetId,
    required EntityId vaultId,
    required int expectedRevision,
    required BudgetMonth month,
    required BudgetMonthlyConfiguration configuration,
    required BudgetMonthlyEditScope scope,
    required UtcInstant now,
    String? name,
  }) {
    Future<BudgetDefinition> action() => database.transaction(() async {
      final budget = await find(budgetId);
      if (budget == null || budget.revision != expectedRevision) {
        throw BudgetRevisionConflict(
          id: budgetId,
          expected: expectedRevision,
          actual: budget?.revision,
        );
      }
      if (budget.vaultId != vaultId ||
          budget.deletedAt != null ||
          budget.periodType != BudgetPeriodType.monthly) {
        throw StateError('Budget is unavailable for monthly editing.');
      }
      final vault = await database
          .customSelect(
            'SELECT timezone FROM vaults WHERE id = ?',
            variables: [Variable(vaultId.value)],
          )
          .getSingle();
      final first = BudgetMonth.fromDate(
        budgetCreationMonth(
          budget.createdAt.epochMicroseconds,
          vault.read<String>('timezone'),
        ),
      );
      if (month.compareTo(first) < 0) {
        throw ArgumentError('Month precedes budget creation.');
      }
      final history = await loadMonthlyHistory(budgetId);
      if (!history.entries.any(
        (entry) =>
            entry.kind == BudgetMonthlyEntryKind.standard &&
            entry.month == first,
      )) {
        throw StateError('Monthly budget base is missing.');
      }
      // Validate the highest possible monthly multiplier, not just this month.
      configuration.limitFor(BudgetMonth(2024, 1));
      final updatedName = name?.trim() ?? budget.name;
      if (updatedName.isEmpty) throw ArgumentError.value(name, 'name');
      await _validateScope(vaultId, configuration.scope, requireActive: true);
      final changed = await database.customUpdate(
        'UPDATE budgets SET revision = ?, updated_at = ?, monthly_history_edited = 1, name = ? WHERE id = ? AND vault_id = ? AND revision = ? AND deleted_at IS NULL',
        variables: _variables([
          expectedRevision + 1,
          now.epochMicroseconds,
          updatedName,
          budgetId.value,
          vaultId.value,
          expectedRevision,
        ]),
        updates: {database.budgets},
      );
      if (changed != 1) {
        throw BudgetRevisionConflict(
          id: budgetId,
          expected: expectedRevision,
          actual: budget.revision,
        );
      }
      final kind = scope == BudgetMonthlyEditScope.onlyMonth
          ? 'override'
          : 'standard';
      // Delete children explicitly as migration connections may defer FKs.
      final replaced = await database
          .customSelect(
            "SELECT id, month_start FROM budget_monthly_configurations WHERE budget_id = ? AND kind = ? AND month_start ${scope == BudgetMonthlyEditScope.onlyMonth ? '=' : '>='} ?",
            variables: [
              Variable(budgetId.value),
              Variable(kind),
              Variable(month.toString()),
            ],
          )
          .get();
      String? retainedId;
      for (final row in replaced) {
        if (row.read<String>('month_start') == month.toString()) {
          retainedId = row.read<String>('id');
        }
        await _deleteConfiguration(row.read<String>('id'));
      }
      await _writeConfiguration(
        budgetId,
        month,
        kind,
        configuration,
        retainedId: retainedId,
      );
      if (scope == BudgetMonthlyEditScope.fromMonth) {
        final selectedOverride = await database
            .customSelect(
              "SELECT id FROM budget_monthly_configurations WHERE budget_id = ? AND kind = 'override' AND month_start = ?",
              variables: [Variable(budgetId.value), Variable(month.toString())],
            )
            .getSingleOrNull();
        if (selectedOverride != null) {
          await _deleteConfiguration(selectedOverride.read<String>('id'));
          await _writeConfiguration(
            budgetId,
            month,
            'override',
            configuration,
            retainedId: selectedOverride.read<String>('id'),
          );
        }
      }
      return (await find(budgetId))!;
    });
    return syncRecorder?.run(
          vaultId: vaultId.value,
          entityType: SyncEntityType.budget,
          recordId: budgetId.value,
          newRevision: expectedRevision + 1,
          operation: SyncOperation.upsert,
          action: action,
        ) ??
        action();
  }

  Future<void> _deleteConfiguration(String id) async {
    for (final table in [
      'budget_monthly_categories',
      'budget_monthly_accounts',
      'budget_monthly_tags',
    ]) {
      await database.customStatement(
        'DELETE FROM $table WHERE configuration_id = ?',
        [id],
      );
    }
    await database.customStatement(
      'DELETE FROM budget_monthly_configurations WHERE id = ?',
      [id],
    );
  }

  Future<void> _writeConfiguration(
    EntityId budgetId,
    BudgetMonth month,
    String kind,
    BudgetMonthlyConfiguration configuration, {
    String? retainedId,
  }) async {
    final id = retainedId ?? EntityId.generate().value;
    await database.customStatement(
      'INSERT INTO budget_monthly_configurations (id, budget_id, kind, month_start, limit_method, amount_minor, warning_threshold_bps) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        budgetId.value,
        kind,
        month.toString(),
        _limitMethodWire(configuration.limitMethod),
        configuration.amountMinor,
        configuration.warningThresholdBps,
      ],
    );
    for (final category in configuration.scope.categories) {
      await database.customStatement(
        'INSERT INTO budget_monthly_categories VALUES (?, ?, ?)',
        [id, category.categoryId.value, category.includeDescendants ? 1 : 0],
      );
    }
    for (final account in configuration.scope.accountIds) {
      await database.customStatement(
        'INSERT INTO budget_monthly_accounts VALUES (?, ?)',
        [id, account.value],
      );
    }
    for (final tag in configuration.scope.tagIds) {
      await database.customStatement(
        'INSERT INTO budget_monthly_tags VALUES (?, ?)',
        [id, tag.value],
      );
    }
  }

  Future<void> _validateScope(
    EntityId vaultId,
    BudgetScope scope, {
    required bool requireActive,
  }) async {
    for (final link in [
      ('categories', scope.categories.map((entry) => entry.categoryId)),
      ('accounts', scope.accountIds),
      ('tags', scope.tagIds),
    ]) {
      final seen = <EntityId>{};
      for (final id in link.$2) {
        if (!seen.add(id)) throw ArgumentError('Duplicate budget filter.');
        final row = await database
            .customSelect(
              'SELECT * FROM ${link.$1} WHERE id = ?',
              variables: [Variable(id.value)],
            )
            .getSingleOrNull();
        if (row == null ||
            row.read<String>('vault_id') != vaultId.value ||
            (requireActive &&
                (row.readNullable<int>('deleted_at') != null ||
                    (link.$1 == 'accounts' &&
                        row.read<int>('archived') != 0)))) {
          throw StateError(
            'Budget filter is unavailable or outside the vault.',
          );
        }
      }
    }
  }

  @override
  Future<void> save(
    BudgetDefinition budget, {
    BudgetMonthlyConfiguration? initialMonthlyConfiguration,
  }) =>
      syncRecorder?.run(
        vaultId: budget.vaultId.value,
        entityType: SyncEntityType.budget,
        recordId: budget.id.value,
        newRevision: budget.revision,
        operation: budget.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(budget, initialMonthlyConfiguration),
      ) ??
      _save(budget, initialMonthlyConfiguration);

  Future<void> _save(
    BudgetDefinition budget,
    BudgetMonthlyConfiguration? initialConfiguration,
  ) => database.transaction(() async {
    final current = await database
        .customSelect(
          'SELECT * FROM budgets WHERE id = ?',
          variables: [Variable<String>(budget.id.value)],
          readsFrom: {database.budgets},
        )
        .getSingleOrNull();
    if (initialConfiguration != null &&
        (current != null || budget.periodType != BudgetPeriodType.monthly)) {
      throw ArgumentError(
        'Initial monthly configuration requires a new monthly budget.',
      );
    }
    if (current != null &&
        (current.read<String>('vault_id') != budget.vaultId.value ||
            current.readNullable<int>('deleted_at') != null)) {
      throw StateError('Budget identity or deletion state cannot be replaced.');
    }
    if (current != null &&
        current.read<int>('revision') != budget.revision - 1) {
      throw BudgetRevisionConflict(
        id: budget.id,
        expected: budget.revision - 1,
        actual: current.read<int>('revision'),
      );
    }
    if (current != null &&
        (current.read<String>('currency_code') != budget.currency.value ||
            (current.read<String>('period_type') == 'monthly' &&
                (budget.periodType != BudgetPeriodType.monthly ||
                    current.read<int>('limit_minor') != budget.limitMinor ||
                    current.read<int>('warning_threshold_bps') !=
                        budget.warningThresholdBps)))) {
      throw StateError(
        'Monthly configuration must be edited through saveMonthlyEdit.',
      );
    }
    if (current != null && current.read<String>('period_type') == 'monthly') {
      final persisted = await _load(current.data);
      if (budget.deletedAt == null &&
          !_sameScope(persisted.scope, budget.scope)) {
        throw StateError(
          'Monthly filters must be edited through saveMonthlyEdit.',
        );
      }
    }
    await _validateScope(budget.vaultId, budget.scope, requireActive: false);
    final existingLinks = await database
        .customSelect(
          'SELECT account_id FROM budget_accounts WHERE budget_id = ?',
          variables: [Variable<String>(budget.id.value)],
          readsFrom: {database.budgetAccounts},
        )
        .get();
    final existingAccountIds = {
      for (final row in existingLinks) row.read<String>('account_id'),
    };
    final persistedAccountIds = {
      ...budget.scope.accountIds.map((id) => id.value),
      if (budget.deletedAt != null) ...existingAccountIds,
    };
    if (current != null &&
        current.read<String>('period_type') == 'monthly' &&
        current.read<int>('enabled') == 0 &&
        budget.enabled &&
        budget.deletedAt == null) {
      final vault = await database
          .customSelect(
            'SELECT timezone FROM vaults WHERE id = ?',
            variables: [Variable(budget.vaultId.value)],
          )
          .getSingle();
      final month = BudgetMonth.fromDate(
        budgetCreationMonth(
          UtcInstant.now().epochMicroseconds,
          vault.read<String>('timezone'),
        ),
      );
      final history = await loadMonthlyHistory(budget.id);
      final candidates = <BudgetMonth>{month};
      for (final entryMonth in [
        month,
        ...history.entries.map((entry) => entry.month),
      ]) {
        if (entryMonth.compareTo(month) >= 0) candidates.add(entryMonth);
        if (entryMonth.start.year < 9999 || entryMonth.start.month < 12) {
          final next = BudgetMonth.fromDate(entryMonth.end.addDays(1));
          if (next.compareTo(month) >= 0) candidates.add(next);
        }
      }
      for (final candidate in candidates) {
        final configuration = history.resolve(candidate);
        if (configuration != null) {
          await _validateScope(
            budget.vaultId,
            configuration.scope,
            requireActive: true,
          );
        }
      }
    }
    final requiresActive =
        budget.enabled &&
        budget.deletedAt == null &&
        (current == null || budget.periodType != BudgetPeriodType.monthly);
    for (final accountId in persistedAccountIds) {
      final account = await database
          .customSelect(
            'SELECT vault_id, archived, deleted_at FROM accounts WHERE id = ?',
            variables: [Variable<String>(accountId)],
            readsFrom: {database.accounts},
          )
          .getSingleOrNull();
      final needsActive =
          requiresActive || !existingAccountIds.contains(accountId);
      if (account == null ||
          account.read<String>('vault_id') != budget.vaultId.value ||
          (needsActive &&
              (account.read<int>('archived') != 0 ||
                  account.readNullable<int>('deleted_at') != null))) {
        throw StateError('Budget account is inactive or outside the vault.');
      }
    }
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
      if (budget.deletedAt != null) return;
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
    for (final accountId in persistedAccountIds) {
      await database.customStatement(
        'INSERT INTO budget_accounts (budget_id, account_id) VALUES (?, ?)',
        [budget.id.value, accountId],
      );
    }
    for (final tagId in budget.scope.tagIds) {
      await database.customStatement(
        'INSERT INTO budget_tags (budget_id, tag_id) VALUES (?, ?)',
        [budget.id.value, tagId.value],
      );
    }
    await initializeBudgetMonthlyHistory(database, budgetId: budget.id.value);
    if (initialConfiguration != null) {
      initialConfiguration.limitFor(BudgetMonth(2024, 1));
      if (!_sameScope(initialConfiguration.scope, budget.scope) ||
          initialConfiguration.warningThresholdBps !=
              budget.warningThresholdBps) {
        throw ArgumentError(
          'Initial monthly configuration differs from definition.',
        );
      }
      final history = await loadMonthlyHistory(budget.id);
      final base = history.entries.single;
      if (initialConfiguration.limitFor(base.month) != budget.limitMinor) {
        throw ArgumentError(
          'Initial monthly limit differs from creation month.',
        );
      }
      await _deleteConfiguration(base.id.value);
      await _writeConfiguration(
        budget.id,
        base.month,
        'standard',
        initialConfiguration,
        retainedId: base.id.value,
      );
      await database.customStatement(
        'UPDATE budgets SET monthly_history_edited = ? WHERE id = ?',
        [
          initialConfiguration.limitMethod == BudgetLimitMethod.fixed ? 0 : 1,
          budget.id.value,
        ],
      );
    }
  });

  @override
  Future<BudgetDefinition?> find(EntityId id) async {
    final row = await database
        .customSelect(
          'SELECT * FROM budgets WHERE id = ?',
          variables: [Variable<String>(id.value)],
          readsFrom: {database.budgets},
        )
        .getSingleOrNull();
    return row == null ? null : _load(row.data);
  }

  @override
  Future<List<BudgetDefinition>> listForVault(
    EntityId vaultId, {
    bool includeDeleted = false,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM budgets WHERE vault_id = ? '
          '${includeDeleted ? '' : 'AND deleted_at IS NULL '}'
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
      monthlyHistoryEdited: row['monthly_history_edited'] == 1,
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
          'WHERE vault_id = ?',
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

BudgetLimitMethod _limitMethod(String value) => switch (value) {
  'fixed' => BudgetLimitMethod.fixed,
  'calendar_day' => BudgetLimitMethod.calendarDay,
  'weekday' => BudgetLimitMethod.weekday,
  _ => throw FormatException('Invalid budget limit method.'),
};
String _limitMethodWire(BudgetLimitMethod value) => switch (value) {
  BudgetLimitMethod.fixed => 'fixed',
  BudgetLimitMethod.calendarDay => 'calendar_day',
  BudgetLimitMethod.weekday => 'weekday',
};
bool _sameScope(BudgetScope a, BudgetScope b) =>
    a.accountIds.length == b.accountIds.length &&
    a.accountIds.containsAll(b.accountIds) &&
    a.tagIds.length == b.tagIds.length &&
    a.tagIds.containsAll(b.tagIds) &&
    a.categories.length == b.categories.length &&
    a.categories.every(
      (left) => b.categories.any(
        (right) =>
            left.categoryId == right.categoryId &&
            left.includeDescendants == right.includeDescendants,
      ),
    );

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map(Variable<Object>.new).toList(growable: false);
