import 'package:drift/drift.dart';

import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart'
    hide BudgetMonthlyConfiguration;
import '../persistence/database/budget_monthly_history_migration.dart';
import '../security/canonical_json.dart';
import 'drift_sync_aggregate_store.dart';

const budgetHistoryTables = [
  'budget_monthly_configurations',
  'budget_monthly_categories',
  'budget_monthly_accounts',
  'budget_monthly_tags',
];

List<Map<String, Object?>> budgetRows(Object? value) {
  if (value is! List || value.any((row) => row is! Map)) {
    throw const SyncAggregateFormatException();
  }
  return value.map((row) => Map<String, Object?>.from(row as Map)).toList();
}

void validateBudgetPayload(Map<String, Object?> payload) {
  final root = payload['root'] as Map;
  final children = payload['children'] as Map;
  final id = root['id'];
  const rootFields = {
    'id',
    'vault_id',
    'name',
    'currency_code',
    'limit_minor',
    'period_type',
    'starts_on',
    'ends_on',
    'warning_threshold_bps',
    'rollover_policy',
    'enabled',
    'revision',
    'created_at',
    'updated_at',
    'deleted_at',
    'monthly_history_edited',
  };
  if (root.keys.any((key) => !rootFields.contains(key)) ||
      root['name'] is! String ||
      (root['name'] as String).trim().isEmpty ||
      (root['enabled'] != 0 && root['enabled'] != 1) ||
      root['updated_at'] is! int ||
      (root['deleted_at'] != null && root['deleted_at'] is! int)) {
    throw const SyncAggregateFormatException();
  }
  if (root['currency_code'] is! String ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(root['currency_code'] as String) ||
      root['created_at'] is! int ||
      root['limit_minor'] is! int ||
      (root['limit_minor'] as int) <= 0 ||
      root['warning_threshold_bps'] is! int ||
      (root['warning_threshold_bps'] as int) < 1 ||
      (root['warning_threshold_bps'] as int) > 10000 ||
      ![
        'monthly',
        'weekly',
        'yearly',
        'custom',
      ].contains(root['period_type'])) {
    throw const SyncAggregateFormatException();
  }
  for (final link in [
    ('budget_categories', 'category_id'),
    ('budget_accounts', 'account_id'),
    ('budget_tags', 'tag_id'),
  ]) {
    final seen = <String>{};
    for (final row in budgetRows(children[link.$1])) {
      final allowedFields = {
        'budget_id',
        link.$2,
        if (link.$1 == 'budget_categories') 'include_descendants',
      };
      if (row.keys.toSet().length != allowedFields.length ||
          !row.keys.toSet().containsAll(allowedFields)) {
        throw const SyncAggregateFormatException();
      }
      if (row['budget_id'] != id ||
          row[link.$2] is! String ||
          !seen.add(row[link.$2] as String) ||
          (link.$1 == 'budget_categories' &&
              row['include_descendants'] != 0 &&
              row['include_descendants'] != 1)) {
        throw const SyncAggregateFormatException();
      }
    }
  }
  if (payload['format_version'] == 1) {
    if (root.containsKey('monthly_history_edited')) {
      throw const SyncAggregateFormatException();
    }
    return;
  }
  if (root['monthly_history_edited'] != 0 &&
      root['monthly_history_edited'] != 1) {
    throw const SyncAggregateFormatException();
  }
  final configurations = budgetRows(children['budget_monthly_configurations']);
  final ids = <String>{};
  final unique = <String>{};
  var standards = 0;
  for (final row in configurations) {
    const fields = {
      'id',
      'budget_id',
      'kind',
      'month_start',
      'limit_method',
      'amount_minor',
      'warning_threshold_bps',
    };
    if (row.keys.toSet().length != fields.length ||
        !row.keys.toSet().containsAll(fields)) {
      throw const SyncAggregateFormatException();
    }
    if (row['id'] is! String ||
        !ids.add(row['id'] as String) ||
        row['budget_id'] != id ||
        !['standard', 'override'].contains(row['kind']) ||
        row['month_start'] is! String ||
        !unique.add('${row['kind']}/${row['month_start']}') ||
        !['fixed', 'calendar_day', 'weekday'].contains(row['limit_method']) ||
        row['amount_minor'] is! int ||
        row['warning_threshold_bps'] is! int) {
      throw const SyncAggregateFormatException();
    }
    try {
      EntityId.parse(row['id'] as String);
      BudgetMonth.parse(row['month_start'] as String);
      BudgetMonthlyConfiguration(
        amountMinor: row['amount_minor'] as int,
        warningThresholdBps: row['warning_threshold_bps'] as int,
        limitMethod: row['limit_method'] == 'calendar_day'
            ? BudgetLimitMethod.calendarDay
            : row['limit_method'] == 'weekday'
            ? BudgetLimitMethod.weekday
            : BudgetLimitMethod.fixed,
        scope: BudgetScope(),
      ).limitFor(BudgetMonth(2024, 1));
    } catch (_) {
      throw const SyncAggregateFormatException();
    }
    if (row['kind'] == 'standard') standards++;
  }
  if ((root['period_type'] == 'monthly' && standards == 0) ||
      (root['period_type'] != 'monthly' &&
          (configurations.isNotEmpty || root['monthly_history_edited'] != 0))) {
    throw const SyncAggregateFormatException();
  }
  for (final link in [
    ('budget_monthly_categories', 'category_id'),
    ('budget_monthly_accounts', 'account_id'),
    ('budget_monthly_tags', 'tag_id'),
  ]) {
    final seen = <String>{};
    for (final row in budgetRows(children[link.$1])) {
      final fields = {
        'configuration_id',
        link.$2,
        if (link.$1 == 'budget_monthly_categories') 'include_descendants',
      };
      if (row.keys.toSet().length != fields.length ||
          !row.keys.toSet().containsAll(fields)) {
        throw const SyncAggregateFormatException();
      }
      if (!ids.contains(row['configuration_id']) ||
          row[link.$2] is! String ||
          !seen.add('${row['configuration_id']}/${row[link.$2]}') ||
          (link.$1 == 'budget_monthly_categories' &&
              row['include_descendants'] != 0 &&
              row['include_descendants'] != 1)) {
        throw const SyncAggregateFormatException();
      }
    }
  }
  if (root['monthly_history_edited'] == 0 &&
      root['period_type'] == 'monthly' &&
      (configurations.length != 1 ||
          configurations.single['kind'] != 'standard' ||
          configurations.single['limit_method'] != 'fixed' ||
          configurations.single['amount_minor'] != root['limit_minor'] ||
          configurations.single['warning_threshold_bps'] !=
              root['warning_threshold_bps'])) {
    throw const SyncAggregateFormatException();
  }
  if (root['monthly_history_edited'] == 0 && configurations.isNotEmpty) {
    for (final link in [
      ('categories', 'category_id'),
      ('accounts', 'account_id'),
      ('tags', 'tag_id'),
    ]) {
      final oldRows =
          budgetRows(children['budget_${link.$1}'])
              .map(
                (row) => '${row[link.$2]}:${row['include_descendants'] ?? ''}',
              )
              .toList()
            ..sort();
      final newRows =
          budgetRows(children['budget_monthly_${link.$1}'])
              .map(
                (row) => '${row[link.$2]}:${row['include_descendants'] ?? ''}',
              )
              .toList()
            ..sort();
      if (CanonicalJson.encode(oldRows) != CanonicalJson.encode(newRows)) {
        throw const SyncAggregateFormatException();
      }
    }
  }
}

final class BudgetSyncHistory {
  const BudgetSyncHistory(this.database);
  final EquisDatabase database;

  Future<bool> hasActiveAccountReference(
    Map<String, Object?> payload,
    String accountId,
    int nowMicros,
  ) async {
    final root = payload['root'] as Map;
    if (root['enabled'] != 1 || root['deleted_at'] != null) return false;
    final children = payload['children'] as Map;
    if (payload['format_version'] == 1 || root['period_type'] != 'monthly') {
      return budgetRows(
        children['budget_accounts'],
      ).any((row) => row['account_id'] == accountId);
    }
    final vault = await database
        .customSelect(
          'SELECT timezone FROM vaults WHERE id = ?',
          variables: [Variable(root['vault_id'])],
        )
        .getSingle();
    final current = BudgetMonth.fromDate(
      budgetCreationMonth(nowMicros, vault.read<String>('timezone')),
    );
    final accountLinks = budgetRows(children['budget_monthly_accounts']);
    final entries = budgetRows(children['budget_monthly_configurations'])
        .map(
          (row) => BudgetMonthlyEntry(
            id: EntityId.parse(row['id'] as String),
            budgetId: EntityId.parse(root['id'] as String),
            kind: BudgetMonthlyEntryKind.values.byName(row['kind'] as String),
            month: BudgetMonth.parse(row['month_start'] as String),
            configuration: BudgetMonthlyConfiguration(
              amountMinor: row['amount_minor'] as int,
              warningThresholdBps: row['warning_threshold_bps'] as int,
              scope: BudgetScope(
                accountIds: {
                  for (final link in accountLinks)
                    if (link['configuration_id'] == row['id'])
                      EntityId.parse(link['account_id'] as String),
                },
              ),
            ),
          ),
        )
        .toList();
    final history = BudgetMonthlyHistory(entries);
    final candidates = {
      current,
      BudgetMonth.fromDate(current.end.addDays(1)),
      for (final entry in entries) ...[
        entry.month,
        BudgetMonth.fromDate(entry.month.end.addDays(1)),
      ],
    };
    return candidates
        .where((month) => month.compareTo(current) >= 0)
        .any(
          (month) =>
              history
                  .resolve(month)
                  ?.scope
                  .accountIds
                  .contains(EntityId.parse(accountId)) ??
              false,
        );
  }

  Future<List<Map<String, Object?>>> _query(String sql, String id) async => [
    for (final row
        in await database.customSelect(sql, variables: [Variable(id)]).get())
      row.data,
  ];

  Future<bool> append(
    Map<String, Object?> root,
    Map<String, Object?> children,
  ) async {
    final id = root['id'] as String;
    final history = await _query(
      'SELECT * FROM budget_monthly_configurations WHERE budget_id = ? ORDER BY id',
      id,
    );
    final advanced =
        root['monthly_history_edited'] == 1 ||
        (root['period_type'] == 'monthly' &&
            (history.length != 1 ||
                history.single['limit_method'] != 'fixed' ||
                history.single['kind'] != 'standard' ||
                history.single['amount_minor'] != root['limit_minor'] ||
                history.single['warning_threshold_bps'] !=
                    root['warning_threshold_bps']));
    children['budget_monthly_configurations'] = history;
    for (final table in budgetHistoryTables.skip(1)) {
      children[table] = await _query(
        'SELECT * FROM $table WHERE configuration_id IN (SELECT id FROM budget_monthly_configurations WHERE budget_id = ?) ORDER BY configuration_id, 2',
        id,
      );
    }
    if (!advanced) {
      validateBudgetPayload({
        'format_version': 2,
        'root': root,
        'children': children,
      });
      await validateRelationships(root, children, 2);
      for (final table in budgetHistoryTables) {
        children.remove(table);
      }
      root.remove('monthly_history_edited');
      return false;
    }
    return true;
  }

  Future<void> validateStored(String vaultId) async {
    for (final root in await _query(
      'SELECT * FROM budgets WHERE vault_id = ?',
      vaultId,
    )) {
      final children = <String, Object?>{};
      final id = root['id'] as String;
      for (final table in [
        'budget_categories',
        'budget_accounts',
        'budget_tags',
        'budget_monthly_configurations',
      ]) {
        children[table] = await _query(
          'SELECT * FROM $table WHERE budget_id = ? ORDER BY 1, 2',
          id,
        );
      }
      for (final table in budgetHistoryTables.skip(1)) {
        children[table] = await _query(
          'SELECT * FROM $table WHERE configuration_id IN (SELECT id FROM budget_monthly_configurations WHERE budget_id = ?) ORDER BY 1, 2',
          id,
        );
      }
      validateBudgetPayload({
        'format_version': 2,
        'root': root,
        'children': children,
      });
      await validateRelationships(root, children, 2);
    }
  }

  Future<String?> protection(String id, Map<String, Object?> incoming) async {
    final current = await database
        .customSelect(
          'SELECT * FROM budgets WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (current == null) return null;
    final root = incoming['root'] as Map;
    if (current.read<String>('vault_id') != root['vault_id'] ||
        current.read<String>('currency_code') != root['currency_code'] ||
        current.read<int>('created_at') != root['created_at']) {
      throw const SyncAggregateFormatException();
    }
    if (current.read<String>('period_type') == 'monthly' &&
        root['period_type'] != 'monthly') {
      return 'protected_budget_history';
    }
    if (current.readNullable<int>('deleted_at') != null &&
        root['deleted_at'] == null) {
      return 'protected_budget_history';
    }
    final localRoot = Map<String, Object?>.from(current.data);
    final localChildren = <String, Object?>{};
    for (final table in [
      'budget_categories',
      'budget_accounts',
      'budget_tags',
    ]) {
      localChildren[table] = await _query(
        'SELECT * FROM $table WHERE budget_id = ? ORDER BY 1, 2',
        id,
      );
    }
    final advanced = await append(localRoot, localChildren);
    if (advanced &&
        (incoming['format_version'] == 1 ||
            root['monthly_history_edited'] != 1)) {
      return 'protected_budget_history';
    }
    return null;
  }

  Future<void> replace(
    String id,
    Map<String, Object?> payload,
    Future<void> Function(String table, Map<String, Object?> row) insert,
    Future<void> Function(Map<String, Object?> row) upsertRoot,
  ) async {
    validateBudgetPayload(payload);
    if (await protection(id, payload) != null) {
      throw const BudgetHistoryCompatibilityException();
    }
    final root = Map<String, Object?>.from(payload['root'] as Map);
    final children = payload['children'] as Map;
    await validateRelationships(
      root,
      children,
      payload['format_version'] as int,
    );
    if (payload['format_version'] == 1) {
      root['monthly_history_edited'] = 0;
    }
    for (final table in budgetHistoryTables.skip(1)) {
      await database.customStatement(
        'DELETE FROM $table WHERE configuration_id IN (SELECT id FROM budget_monthly_configurations WHERE budget_id = ?)',
        [id],
      );
    }
    await database.customStatement(
      'DELETE FROM budget_monthly_configurations WHERE budget_id = ?',
      [id],
    );
    for (final table in [
      'budget_categories',
      'budget_accounts',
      'budget_tags',
    ]) {
      await database.customStatement('DELETE FROM $table WHERE budget_id = ?', [
        id,
      ]);
    }
    await upsertRoot(root);
    for (final table in [
      'budget_categories',
      'budget_accounts',
      'budget_tags',
      if (payload['format_version'] == 2) ...budgetHistoryTables,
    ]) {
      for (final row in budgetRows(children[table])) {
        await insert(table, row);
      }
    }
    if (payload['format_version'] == 1) {
      await initializeBudgetMonthlyHistory(database, budgetId: id);
    }
  }

  Future<void> validateRelationships(
    Map<String, Object?> root,
    Map children,
    int format,
  ) async {
    final id = root['id'] as String;
    final vaultId = root['vault_id'] as String;
    final vault = await database
        .customSelect(
          'SELECT timezone FROM vaults WHERE id = ?',
          variables: [Variable(vaultId)],
        )
        .getSingle();
    final first = budgetCreationMonth(
      root['created_at'] as int,
      vault.read<String>('timezone'),
    );
    if (format == 2) {
      final rows = budgetRows(children['budget_monthly_configurations']);
      if (rows.any(
            (row) =>
                LocalDate.parse(row['month_start'] as String).compareTo(first) <
                0,
          ) ||
          (root['period_type'] == 'monthly' &&
              !rows.any(
                (row) =>
                    row['kind'] == 'standard' &&
                    row['month_start'] == first.toString(),
              ))) {
        throw const SyncAggregateFormatException();
      }
      for (final row in rows) {
        final existing = await database
            .customSelect(
              'SELECT budget_id FROM budget_monthly_configurations WHERE id = ?',
              variables: [Variable(row['id'])],
            )
            .getSingleOrNull();
        if (existing != null && existing.read<String>('budget_id') != id) {
          throw const SyncAggregateFormatException();
        }
      }
    }
    for (final link in [
      ('categories', 'category_id'),
      ('accounts', 'account_id'),
      ('tags', 'tag_id'),
    ]) {
      final links = [
        ...budgetRows(children['budget_${link.$1}']),
        if (format == 2) ...budgetRows(children['budget_monthly_${link.$1}']),
      ];
      for (final row in links) {
        final referenced = await database
            .customSelect(
              'SELECT vault_id FROM ${link.$1} WHERE id = ?',
              variables: [Variable(row[link.$2])],
            )
            .getSingleOrNull();
        if (referenced == null ||
            referenced.read<String>('vault_id') != vaultId) {
          throw const SyncAggregateFormatException();
        }
      }
    }
  }
}

final class BudgetHistoryCompatibilityException implements Exception {
  const BudgetHistoryCompatibilityException();
  @override
  String toString() =>
      'Update the other device before synchronizing budget history. Keep the current local history to resolve this conflict.';
}
