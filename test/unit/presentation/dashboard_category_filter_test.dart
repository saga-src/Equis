import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vaultId = EntityId.generate();
  final categoryId = EntityId.generate();
  final report = DashboardSnapshot(
    reportingCurrency: CurrencyCode.brl,
    periodStart: LocalDate(2026, 8, 1),
    periodEnd: LocalDate(2026, 8, 31),
    availableMoneyMinor: 0,
    incomeMinor: 0,
    expenseMinor: 0,
    spendingByCategory: const [],
    cashFlow: [
      CashFlowPoint(
        date: LocalDate(2026, 8, 17),
        incomeMinor: 0,
        expenseMinor: 0,
      ),
    ],
    accountBalances: const [],
    missingRates: const {},
    usesEstimatedRates: false,
    upcomingCount: 0,
  );

  test('expense category uses reconciled reporting semantics', () {
    final filter = dashboardCategoryHistoryFilter(
      vaultId: vaultId,
      categoryId: categoryId,
      report: report,
      classification: ReportClassification.expense,
    );
    expect(filter.categoryId, categoryId);
    expect(filter.reportingExpensesOnly, isTrue);
    expect(filter.types, isEmpty);
    expect(filter.fromDate, LocalDate(2026, 8, 1));
    expect(filter.toDate, LocalDate(2026, 8, 17));
  });

  test('income category limits history to income-producing types', () {
    final filter = dashboardCategoryHistoryFilter(
      vaultId: vaultId,
      categoryId: categoryId,
      report: report,
      classification: ReportClassification.income,
    );
    expect(filter.reportingExpensesOnly, isFalse);
    expect(filter.types, {
      LedgerTransactionType.income,
      LedgerTransactionType.dividend,
      LedgerTransactionType.interest,
    });
  });
}
