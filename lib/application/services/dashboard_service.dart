import '../ports/dashboard_repository.dart';
import 'recurring_transaction_service.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

final class DashboardService {
  const DashboardService({required this.repository, required this.recurring});

  final DashboardRepository repository;
  final RecurringTransactionService recurring;

  Future<DashboardSnapshot> load({
    required EntityId vaultId,
    required CurrencyCode reportingCurrency,
    required LocalDate asOf,
  }) async {
    repository.beginRead();
    final periodStart = LocalDate(asOf.year, asOf.month, 1);
    final periodEnd = LocalDate(
      asOf.year,
      asOf.month,
      DateTime.utc(asOf.year, asOf.month + 1, 0).day,
    );
    final splits = await repository.loadSplits(
      vaultId: vaultId,
      from: periodStart,
      through: periodEnd,
      asOf: asOf,
    );
    final accounts = await repository.loadAccountBalances(
      vaultId: vaultId,
      asOf: asOf,
    );
    final missing = <CurrencyCode>{};
    var estimated = false;
    var income = 0;
    var expense = 0;
    final categories = <EntityId, int>{};
    final tags = <EntityId?, int>{};
    final dailyIncome = <LocalDate, int>{};
    final dailyExpense = <LocalDate, int>{};
    for (final row in splits) {
      final converted = row.currency == reportingCurrency
          ? ReportingConversion(minorUnits: row.amountMinor)
          : await repository.convertMinor(
              vaultId: vaultId,
              source: row.currency,
              target: reportingCurrency,
              date: row.date,
              amountMinor: row.amountMinor,
            );
      if (converted == null) {
        missing.add(row.currency);
        continue;
      }
      estimated |= converted.estimated;
      switch (row.classification) {
        case ReportClassification.income:
          income += converted.minorUnits;
          dailyIncome.update(
            row.date,
            (value) => value + converted.minorUnits,
            ifAbsent: () => converted.minorUnits,
          );
        case ReportClassification.expense:
          expense += converted.minorUnits;
          for (final tag
              in row.tagIds.isEmpty
                  ? <EntityId?>[null]
                  : row.tagIds.toSet().toList()) {
            tags.update(
              tag,
              (value) => value + converted.minorUnits,
              ifAbsent: () => converted.minorUnits,
            );
          }
          categories.update(
            row.categoryId,
            (value) => value + converted.minorUnits,
            ifAbsent: () => converted.minorUnits,
          );
          dailyExpense.update(
            row.date,
            (value) => value + converted.minorUnits,
            ifAbsent: () => converted.minorUnits,
          );
      }
    }

    var available = 0;
    final balances = <AccountReportBalance>[];
    for (final row in accounts) {
      final converted = row.currency == reportingCurrency
          ? ReportingConversion(minorUnits: row.balanceMinor)
          : await repository.convertMinor(
              vaultId: vaultId,
              source: row.currency,
              target: reportingCurrency,
              date: asOf,
              amountMinor: row.balanceMinor,
            );
      if (converted == null) {
        missing.add(row.currency);
      } else {
        estimated |= converted.estimated;
        if (row.nature == AccountNature.asset && isLiquidAccount(row.type)) {
          available += converted.minorUnits;
        }
      }
      balances.add(
        AccountReportBalance(
          accountId: row.accountId,
          pocketId: row.pocketId,
          accountName: row.accountName,
          type: row.type,
          nature: row.nature,
          currency: row.currency,
          originalMinor: row.balanceMinor,
          reportingMinor: converted?.minorUnits,
        ),
      );
    }

    final recurringUpcoming = await recurring.upcoming(
      vaultId: vaultId,
      from: asOf.addDays(1),
      through: asOf.addDays(30),
      limit: 200,
    );
    final installmentCount = await repository.countUpcomingInstallments(
      vaultId: vaultId,
      after: asOf,
      through: asOf.addDays(30),
    );
    final trend = <CashFlowPoint>[];
    for (
      var date = periodStart;
      date.compareTo(asOf) <= 0;
      date = date.addDays(1)
    ) {
      trend.add(
        CashFlowPoint(
          date: date,
          incomeMinor: dailyIncome[date] ?? 0,
          expenseMinor: dailyExpense[date] ?? 0,
        ),
      );
    }
    final categoryValues = [
      for (final entry in categories.entries)
        if (entry.value > 0)
          CategorySpending(categoryId: entry.key, amountMinor: entry.value),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    return DashboardSnapshot(
      reportingCurrency: reportingCurrency,
      periodStart: periodStart,
      periodEnd: periodEnd,
      availableMoneyMinor: available,
      incomeMinor: income,
      expenseMinor: expense,
      spendingByTag:
          [
            for (final entry in tags.entries)
              TagSpending(tagId: entry.key, amountMinor: entry.value),
          ]..sort((a, b) {
            final amount = b.amountMinor.compareTo(a.amountMinor);
            return amount != 0
                ? amount
                : (a.tagId?.value ?? '').compareTo(b.tagId?.value ?? '');
          }),
      spendingByCategory: categoryValues,
      cashFlow: trend,
      accountBalances: balances,
      missingRates: missing,
      usesEstimatedRates: estimated,
      upcomingCount: recurringUpcoming.length + installmentCount,
    );
  }
}
