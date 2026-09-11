import 'package:equis/app/equis_app.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/goals/cash_flow_projection.dart';
import 'package:equis/domain/goals/goal_models.dart';
import 'package:equis/domain/wealth/asset_models.dart';
import 'package:equis/domain/wealth/net_worth_models.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/intelligence/financial_intelligence_models.dart';
import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:decimal/decimal.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:equis/presentation/budgets/budget_controller.dart';
import 'package:equis/presentation/budgets/budget_screen.dart';
import 'package:equis/presentation/goals/goal_controller.dart';
import 'package:equis/presentation/goals/goal_screen.dart';
import 'package:equis/presentation/wealth/wealth_controller.dart';
import 'package:equis/presentation/wealth/wealth_screen.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:equis/presentation/investments/investment_screen.dart';
import 'package:equis/presentation/intelligence/financial_intelligence_controller.dart';
import 'package:equis/presentation/intelligence/financial_intelligence_screen.dart';
import 'package:equis/presentation/cloud/cloud_account_controller.dart';
import 'package:equis/presentation/cloud/cloud_account_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('protects a small secret in native secure storage', (
    tester,
  ) async {
    const store = FlutterSecureStringStore();
    const key = 'equis.phase17.secure_storage.probe';
    addTearDown(() => store.delete(key));

    await store.delete(key);
    await store.write(key, 'phase17-native-probe');
    expect(await store.read(key), 'phase17-native-probe');
    await store.delete(key);
    expect(await store.read(key), isNull);
  });

  testWidgets('launches the local-first application shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EquisApp()));
    await tester.pumpAndSettle();

    expect(find.text('Equis'), findsOneWidget);
    expect(find.text('Offline ready'), findsOneWidget);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Credit cards'), findsOneWidget);
    expect(
      find.text('Create a credit-card account on Home to get started.'),
      findsOneWidget,
    );
  });

  testWidgets('renders local dashboard reports and charts natively', (
    tester,
  ) async {
    final vaultId = EntityId.generate();
    final category = CategoryNode(
      id: EntityId.generate(),
      vaultId: vaultId,
      type: CategoryType.expense,
      customName: 'Food',
      createdAt: const UtcInstant.fromEpochMicroseconds(1),
      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
    );
    final report = DashboardSnapshot(
      reportingCurrency: CurrencyCode.brl,
      periodStart: LocalDate(2026, 8, 1),
      periodEnd: LocalDate(2026, 8, 31),
      availableMoneyMinor: 125000,
      incomeMinor: 50000,
      expenseMinor: 20000,
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
          accountId: EntityId.generate(),
          pocketId: EntityId.generate(),
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
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('renders budget progress and warning natively', (tester) async {
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final budget = BudgetDefinition(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Food plan',
      currency: CurrencyCode.brl,
      limitMinor: 10000,
      periodType: BudgetPeriodType.monthly,
      warningThresholdBps: 8000,
      scope: BudgetScope(),
      createdAt: instant,
      updatedAt: instant,
    );
    final progress = BudgetProgress(
      budget: budget,
      period: BudgetPeriod(
        start: LocalDate(2026, 8, 1),
        end: LocalDate(2026, 8, 31),
      ),
      usedMinor: 10000,
      projectedMinor: 15000,
      warningState: BudgetWarningState.limitReached,
      usageBps: 10000,
      missingRates: const {},
      usesEstimatedRates: false,
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
          home: BudgetScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vaultId,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: BudgetState(items: [progress]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Food plan'), findsOneWidget);
    expect(find.text('Limit reached'), findsOneWidget);
    expect(find.text('Projected'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders goal and estimated cash-flow projection natively', (
    tester,
  ) async {
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final goal = GoalDefinition(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Emergency fund',
      type: GoalType.emergencyFund,
      currency: CurrencyCode.brl,
      targetMinor: 3000000,
      plannedMonthlyMinor: 120000,
      trackingMode: GoalTrackingMode.manual,
      priority: 10,
      accountPocketIds: const {},
      createdAt: instant,
      updatedAt: instant,
    );
    final progress = GoalProgress(
      goal: goal,
      currentMinor: 850000,
      progressBps: 2833,
      requiredMonthlyMinor: 100000,
      expectedCompletionDate: LocalDate(2028, 6, 30),
      missingRates: const {},
      usesEstimatedRates: false,
    );
    final projection = CashFlowProjection(
      reportingCurrency: CurrencyCode.brl,
      from: LocalDate(2026, 8, 19),
      through: LocalDate(2026, 11, 17),
      openingAvailableMinor: 100000,
      closingProjectedMinor: 95000,
      events: [
        ProjectedCashFlowEvent(
          sourceId: EntityId.generate(),
          type: CashFlowEventType.installment,
          date: LocalDate(2026, 9, 3),
          amountMinor: -5000,
          balanceAfterMinor: 95000,
          name: 'Course',
        ),
      ],
      missingRates: const {},
      usesEstimatedRates: false,
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
          home: GoalScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vaultId,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: GoalState(items: [progress], cashFlow: projection),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Emergency fund'), findsOneWidget);
    expect(find.text('Required monthly contribution'), findsOneWidget);

    await tester.tap(find.text('Future cash flow'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not a guaranteed future balance'),
      findsOneWidget,
    );
    expect(find.text('Course'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('renders net worth and physical assets natively', (tester) async {
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final date = LocalDate(2026, 8, 18);
    final asset = PhysicalAsset(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Vehicle',
      type: PhysicalAssetType.vehicle,
      currency: CurrencyCode.brl,
      acquiredOn: LocalDate(2025, 1, 1),
      acquisitionCostMinor: 5000000,
      valuationMethod: AssetValuationMethod.straightLine,
      usefulLifeMonths: 60,
      createdAt: instant,
      updatedAt: instant,
    );
    final current = NetWorthPoint(
      date: date,
      assetsMinor: 6500000,
      liabilitiesMinor: 800000,
      missingRates: const {},
      usesEstimatedRates: false,
    );
    final report = NetWorthReport(
      currency: CurrencyCode.brl,
      current: current,
      history: [
        NetWorthPoint(
          date: LocalDate(2026, 7, 31),
          assetsMinor: 6200000,
          liabilitiesMinor: 900000,
          missingRates: const {},
          usesEstimatedRates: false,
        ),
        current,
      ],
      physicalAssets: [
        AssetValue(
          asset: asset,
          valueMinor: 4500000,
          reportingMinor: 4500000,
          asOf: date,
          source: AssetValuationSource.calculated,
        ),
      ],
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
          home: WealthScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vaultId,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: WealthState(report: report),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('net-worth-total')), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('renders investment holdings and performance natively', (
    tester,
  ) async {
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final instrument = InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vaultId,
      symbol: 'ACME3',
      name: 'Acme',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      exchange: 'B3',
      createdAt: instant,
      updatedAt: instant,
    );
    final report = PortfolioReport(
      currency: CurrencyCode.brl,
      marketValueMinor: 6000,
      costBasisMinor: 3630,
      unrealizedMinor: 2370,
      realizedMinor: 5180,
      incomeMinor: 500,
      holdings: [
        HoldingReport(
          instrument: instrument,
          quantity: Decimal.fromInt(3),
          costBasisMinor: 3630,
          averageCost: Decimal.parse('12.1'),
          marketValueMinor: 6000,
          reportingMarketValueMinor: 6000,
          unrealizedMinor: 2370,
          realizedMinor: 5180,
          incomeMinor: 500,
          allocationBps: 10000,
          price: InvestmentPrice(
            price: Decimal.fromInt(20),
            currency: CurrencyCode.brl,
            date: LocalDate(2026, 8, 18),
            manual: true,
          ),
          lots: const [],
        ),
      ],
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
          home: InvestmentScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vaultId,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: InvestmentState(
              report: report,
              prices: [
                MarketPriceState(
                  instrument: instrument,
                  quote: MarketQuote(
                    instrumentId: instrument.id,
                    price: Decimal.fromInt(20),
                    currency: CurrencyCode.brl,
                    timestamp: instant,
                    provider: 'brapi',
                  ),
                  source: MarketPriceSource.automatic,
                  stale: true,
                  refreshFailed: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portfolio-value')), findsOneWidget);
    expect(find.textContaining('ACME3'), findsOneWidget);
    expect(find.text('Unrealized gain/loss'), findsOneWidget);
    expect(
      find.text('The cached market price is out of date.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Refresh market prices'), findsOneWidget);
  });

  testWidgets('renders private local financial insights natively', (
    tester,
  ) async {
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final report = FinancialIntelligenceReport(
      enabled: true,
      asOf: LocalDate(2026, 8, 18),
      currency: CurrencyCode.brl,
      insights: [
        FinancialInsight(
          kind: FinancialInsightKind.emergencyFund,
          severity: FinancialInsightSeverity.caution,
          metrics: const {
            'liquid_minor': 270000,
            'average_expense_minor': 100000,
            'coverage_milli_months': 2700,
            'sample_months': 3,
          },
        ),
      ],
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
          home: FinancialIntelligenceScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vaultId,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: FinancialIntelligenceState(report: report),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-intelligence-privacy')), findsOneWidget);
    expect(find.byKey(const Key('insight-emergencyFund')), findsOneWidget);
    expect(find.textContaining('2.7 months'), findsOneWidget);
  });

  testWidgets('keeps local vault access without cloud configuration natively', (
    tester,
  ) async {
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final finance = LocalFinanceSnapshot(
      vault: VaultProfile(
        id: vaultId,
        name: 'Local',
        baseCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        createdAt: instant,
        updatedAt: instant,
      ),
    );
    final device = LocalDeviceIdentity(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Native device',
      platform: 'windows',
      createdAt: instant,
      lastSeenAt: instant,
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
          home: CloudAccountScreen(
            financeOverride: finance,
            stateOverride: CloudAccountState(
              snapshot: CloudAccountSnapshot(
                status: CloudAccountStatus.localOnly,
                device: device,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloud-status-localOnly')), findsOneWidget);
    expect(find.textContaining('every local feature offline'), findsOneWidget);
    expect(find.byKey(const Key('cloud-email')), findsNothing);
  });
}
