import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the implemented local reports with FL Chart', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = EntityId.generate();
    final category = CategoryNode(
      id: EntityId.generate(),
      vaultId: vault,
      type: CategoryType.expense,
      customName: 'Food',
      createdAt: const UtcInstant.fromEpochMicroseconds(1),
      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
    );
    final account = EntityId.generate();
    final pocket = EntityId.generate();
    final report = DashboardSnapshot(
      reportingCurrency: CurrencyCode.brl,
      periodStart: LocalDate(2026, 8, 1),
      periodEnd: LocalDate(2026, 8, 31),
      availableMoneyMinor: 125000,
      incomeMinor: 50000,
      expenseMinor: 20000,
      spendingByTag: const [TagSpending(tagId: null, amountMinor: 20000)],
      spendingByCategory: [
        CategorySpending(categoryId: category.id, amountMinor: 20000),
      ],
      cashFlow: [
        CashFlowPoint(
          date: LocalDate(2026, 8, 1),
          incomeMinor: 50000,
          expenseMinor: 0,
        ),
        CashFlowPoint(
          date: LocalDate(2026, 8, 2),
          incomeMinor: 0,
          expenseMinor: 20000,
        ),
      ],
      accountBalances: [
        AccountReportBalance(
          accountId: account,
          pocketId: pocket,
          accountName: 'Checking',
          type: AccountType.checking,
          nature: AccountNature.asset,
          currency: CurrencyCode.brl,
          originalMinor: 125000,
          reportingMinor: 125000,
        ),
      ],
      missingRates: const {},
      usesEstimatedRates: false,
      upcomingCount: 3,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardOverview(
                finance: LocalFinanceSnapshot(
                  vault: null,
                  categories: [category],
                ),
                reportOverride: report,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available money'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Cash flow over time'), findsOneWidget);
    expect(find.text('Account balances'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Income:.*Expenses:', dotAll: true)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Spending by category'), findsOneWidget);
    expect(find.bySemanticsLabel('Cash flow over time'), findsAtLeast(1));
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Spending by tag'), findsOneWidget);
    expect(find.text('Without tags'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
    semantics.dispose();
  });
}
