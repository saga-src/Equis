import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../domain/shared/local_date.dart';
import '../../../domain/shared/uuid_v7.dart';
import '../../../domain/shared/zoned_recurrence.dart';
import '../../../domain/budgeting/budget_models.dart';
import 'equis_database.dart';

LocalDate budgetCreationMonth(int createdAtMicros, String timezone) {
  ZonedRecurrenceClock.initialize();
  final date = tz.TZDateTime.from(
    DateTime.fromMicrosecondsSinceEpoch(createdAtMicros, isUtc: true),
    timezone == 'UTC' ? tz.UTC : tz.getLocation(timezone),
  );
  return LocalDate(date.year, date.month, 1);
}

/// Test only the currently resolved and future configurations. Past references
/// still prevent physical removal, but are not active archive obligations.
Future<bool> hasActiveMonthlyBudgetAccountReference(
  EquisDatabase database,
  String accountId,
  LocalDate date,
) async {
  final current = BudgetMonth.fromDate(date);
  final budgets = await database
      .customSelect(
        "SELECT id FROM budgets WHERE period_type = 'monthly' AND enabled = 1 AND deleted_at IS NULL",
      )
      .get();
  for (final budget in budgets) {
    final configurations = await database
        .customSelect(
          'SELECT c.*, EXISTS(SELECT 1 FROM budget_monthly_accounts a WHERE a.configuration_id = c.id AND a.account_id = ?1) AS matches '
          'FROM budget_monthly_configurations c WHERE c.budget_id = ?2 ORDER BY c.month_start',
          variables: [Variable(accountId), Variable(budget.read<String>('id'))],
        )
        .get();
    if (configurations.isEmpty) {
      // A malformed/legacy fixture must never permit account removal simply
      // because its monthly base is absent. Keep the existing link protected.
      final legacy = await database
          .customSelect(
            'SELECT 1 FROM budget_accounts WHERE budget_id = ? AND account_id = ?',
            variables: [
              Variable(budget.read<String>('id')),
              Variable(accountId),
            ],
          )
          .get();
      if (legacy.isNotEmpty) return true;
      continue;
    }
    final candidates = <BudgetMonth>{current};
    for (final row in configurations) {
      final month = BudgetMonth.parse(row.read<String>('month_start'));
      if (month.compareTo(current) >= 0) candidates.add(month);
      final next = BudgetMonth.fromDate(month.end.addDays(1));
      if (next.compareTo(current) >= 0) candidates.add(next);
    }
    candidates.add(BudgetMonth.fromDate(current.end.addDays(1)));
    for (final month in candidates) {
      QueryRow? standard;
      QueryRow? override;
      for (final row in configurations) {
        final start = BudgetMonth.parse(row.read<String>('month_start'));
        if (row.read<String>('kind') == 'override') {
          if (start == month) override = row;
        } else if (start.compareTo(month) <= 0) {
          standard = row;
        }
      }
      if ((override ?? standard)?.read<int>('matches') == 1) return true;
    }
  }
  return false;
}

/// Called inside the migration/restore transaction. Never changes revisions,
/// financial rows or outbox: this reconstructs only the available legacy base.
Future<void> initializeBudgetMonthlyHistory(
  EquisDatabase database, {
  String? budgetId,
}) async {
  final rows = await database
      .customSelect(
        "SELECT b.*, v.timezone FROM budgets b LEFT JOIN vaults v ON v.id = b.vault_id "
        "WHERE b.period_type = 'monthly' "
        'AND NOT EXISTS (SELECT 1 FROM budget_monthly_configurations c WHERE c.budget_id = b.id) '
        '${budgetId == null ? '' : 'AND b.id = ?'}',
        variables: [if (budgetId != null) Variable(budgetId)],
      )
      .get();
  for (final row in rows) {
    final id = row.read<String>('id');
    final month = budgetCreationMonth(
      row.read<int>('created_at'),
      row.read<String>('timezone'),
    );
    final configurationId = EntityId.generate().value;
    await database.customStatement(
      'INSERT INTO budget_monthly_configurations '
      '(id, budget_id, kind, month_start, limit_method, amount_minor, warning_threshold_bps) '
      "VALUES (?, ?, 'standard', ?, 'fixed', ?, ?)",
      [
        configurationId,
        id,
        month.toString(),
        row.read<int>('limit_minor'),
        row.read<int>('warning_threshold_bps'),
      ],
    );
    for (final link in [
      ('categories', 'category_id'),
      ('accounts', 'account_id'),
      ('tags', 'tag_id'),
    ]) {
      final invalid = await database
          .customSelect(
            'SELECT 1 FROM budget_${link.$1} l LEFT JOIN ${link.$1} r ON r.id = l.${link.$2} '
            'WHERE l.budget_id = ? AND (r.id IS NULL OR r.vault_id <> ?) LIMIT 1',
            variables: [Variable(id), Variable(row.read<String>('vault_id'))],
          )
          .getSingleOrNull();
      if (invalid != null) {
        throw StateError('Invalid legacy budget filter ownership.');
      }
      final extra = link.$1 == 'categories' ? ', include_descendants' : '';
      await database.customStatement(
        'INSERT INTO budget_monthly_${link.$1} (configuration_id, ${link.$2}$extra) '
        'SELECT ?, ${link.$2}$extra FROM budget_${link.$1} WHERE budget_id = ?',
        [configurationId, id],
      );
    }
  }
}
