import 'package:decimal/decimal.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/goals/cash_flow_projection.dart';
import 'package:equis/domain/goals/goal_models.dart';
import 'package:equis/domain/intelligence/financial_intelligence_engine.dart';
import 'package:equis/domain/intelligence/financial_intelligence_models.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/wealth/net_worth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all local modules produce deterministic and traceable insights', () {
    final inputs = _fixture();
    const engine = FinancialIntelligenceEngine();

    final first = engine.analyze(inputs);
    final second = engine.analyze(inputs);

    expect(first.asOf, LocalDate(2026, 8, 15));
    expect(first.currency, CurrencyCode.brl);
    expect(first.insights.map((value) => value.kind).toSet(), {
      FinancialInsightKind.spendingTrend,
      FinancialInsightKind.expenseAnomaly,
      FinancialInsightKind.budgetForecast,
      FinancialInsightKind.cashFlowForecast,
      FinancialInsightKind.recurringCommitments,
      FinancialInsightKind.goalContribution,
      FinancialInsightKind.emergencyFund,
      FinancialInsightKind.debtOverview,
      FinancialInsightKind.netWorthTrend,
      FinancialInsightKind.investmentConcentration,
    });
    expect(
      first.insights.map((value) => value.metrics).toList(),
      second.insights.map((value) => value.metrics).toList(),
    );
    final emergency = first.insights.singleWhere(
      (value) => value.kind == FinancialInsightKind.emergencyFund,
    );
    expect(emergency.metrics['average_expense_minor'], 100000);
    expect(emergency.metrics['coverage_milli_months'], 2500);
    final anomaly = first.insights.singleWhere(
      (value) => value.kind == FinancialInsightKind.expenseAnomaly,
    );
    expect(anomaly.sourceId, isNotNull);
    expect(
      anomaly.metrics.keys,
      containsAll(['current_minor', 'previous_minor']),
    );
  });

  test(
    'empty history produces only calculations supported by local inputs',
    () {
      final fixture = _fixture();
      final report = const FinancialIntelligenceEngine().analyze(
        FinancialIntelligenceInputs(
          asOf: fixture.asOf,
          currentMonth: fixture.currentMonth,
          previousMonths: const [],
          budgets: const [],
          goals: const [],
          cashFlow: CashFlowProjection(
            reportingCurrency: CurrencyCode.brl,
            from: LocalDate(2026, 8, 16),
            through: LocalDate(2026, 9, 14),
            openingAvailableMinor: 0,
            closingProjectedMinor: 0,
            events: const [],
            missingRates: const {},
            usesEstimatedRates: false,
          ),
          wealth: NetWorthReport(
            currency: CurrencyCode.brl,
            current: _worth(LocalDate(2026, 8, 15), 0, 0),
            history: [_worth(LocalDate(2026, 8, 15), 0, 0)],
            physicalAssets: const [],
          ),
          portfolio: PortfolioReport(
            currency: CurrencyCode.brl,
            holdings: const [],
            marketValueMinor: 0,
            costBasisMinor: 0,
            unrealizedMinor: 0,
            realizedMinor: 0,
            incomeMinor: 0,
          ),
        ),
      );
      expect(report.insights.map((value) => value.kind), [
        FinancialInsightKind.cashFlowForecast,
      ]);
    },
  );
}

FinancialIntelligenceInputs _fixture() {
  final vault = EntityId.generate();
  final category = EntityId.generate();
  final budget = BudgetDefinition(
    id: EntityId.generate(),
    vaultId: vault,
    name: 'Food',
    currency: CurrencyCode.brl,
    limitMinor: 100000,
    periodType: BudgetPeriodType.monthly,
    warningThresholdBps: 8000,
    scope: BudgetScope(),
    createdAt: const UtcInstant.fromEpochMicroseconds(1),
    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
  );
  final goal = GoalDefinition(
    id: EntityId.generate(),
    vaultId: vault,
    name: 'Reserve',
    type: GoalType.emergencyFund,
    currency: CurrencyCode.brl,
    targetMinor: 500000,
    targetDate: LocalDate(2027, 5, 31),
    plannedMonthlyMinor: 20000,
    trackingMode: GoalTrackingMode.manual,
    priority: 1,
    accountPocketIds: const {},
    createdAt: const UtcInstant.fromEpochMicroseconds(1),
    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
  );
  final instrument = InvestmentInstrument(
    id: EntityId.generate(),
    vaultId: vault,
    name: 'Acme',
    symbol: 'ACME3',
    assetClass: InvestmentAssetClass.stock,
    currency: CurrencyCode.brl,
    createdAt: const UtcInstant.fromEpochMicroseconds(1),
    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
  );
  return FinancialIntelligenceInputs(
    asOf: LocalDate(2026, 8, 15),
    currentMonth: _dashboard(
      asOf: LocalDate(2026, 8, 15),
      expense: 120000,
      available: 250000,
      category: category,
      categoryExpense: 70000,
    ),
    previousMonths: [
      _dashboard(
        asOf: LocalDate(2026, 7, 31),
        expense: 100000,
        available: 0,
        category: category,
        categoryExpense: 50000,
      ),
      _dashboard(
        asOf: LocalDate(2026, 6, 30),
        expense: 90000,
        available: 0,
        category: category,
        categoryExpense: 40000,
      ),
      _dashboard(
        asOf: LocalDate(2026, 5, 31),
        expense: 110000,
        available: 0,
        category: category,
        categoryExpense: 45000,
      ),
    ],
    budgets: [
      BudgetProgress(
        budget: budget,
        period: BudgetPeriod.forDate(budget, LocalDate(2026, 8, 15)),
        usedMinor: 80000,
        projectedMinor: 160000,
        warningState: BudgetWarningState.approachingLimit,
        usageBps: 8000,
        missingRates: const {},
        usesEstimatedRates: false,
      ),
    ],
    goals: [
      GoalProgress(
        goal: goal,
        currentMinor: 100000,
        progressBps: 2000,
        requiredMonthlyMinor: 50000,
        expectedCompletionDate: null,
        missingRates: const {},
        usesEstimatedRates: false,
      ),
    ],
    cashFlow: CashFlowProjection(
      reportingCurrency: CurrencyCode.brl,
      from: LocalDate(2026, 8, 16),
      through: LocalDate(2026, 9, 14),
      openingAvailableMinor: 250000,
      closingProjectedMinor: -10000,
      events: [
        ProjectedCashFlowEvent(
          sourceId: EntityId.generate(),
          type: CashFlowEventType.recurringExpense,
          date: LocalDate(2026, 8, 20),
          amountMinor: -20000,
          balanceAfterMinor: 230000,
        ),
        ProjectedCashFlowEvent(
          sourceId: EntityId.generate(),
          type: CashFlowEventType.recurringExpense,
          date: LocalDate(2026, 9, 1),
          amountMinor: -20000,
          balanceAfterMinor: 210000,
        ),
      ],
      missingRates: const {},
      usesEstimatedRates: false,
    ),
    wealth: NetWorthReport(
      currency: CurrencyCode.brl,
      current: _worth(LocalDate(2026, 8, 15), 300000, 200000),
      history: [
        _worth(LocalDate(2026, 5, 31), 200000, 150000),
        _worth(LocalDate(2026, 6, 30), 240000, 160000),
        _worth(LocalDate(2026, 7, 31), 280000, 180000),
        _worth(LocalDate(2026, 8, 15), 300000, 200000),
      ],
      physicalAssets: const [],
    ),
    portfolio: PortfolioReport(
      currency: CurrencyCode.brl,
      marketValueMinor: 100000,
      costBasisMinor: 80000,
      unrealizedMinor: 20000,
      realizedMinor: 0,
      incomeMinor: 0,
      holdings: [
        HoldingReport(
          instrument: instrument,
          quantity: Decimal.fromInt(10),
          costBasisMinor: 60000,
          averageCost: Decimal.fromInt(60),
          realizedMinor: 0,
          incomeMinor: 0,
          marketValueMinor: 60000,
          reportingMarketValueMinor: 60000,
          unrealizedMinor: 0,
          allocationBps: 6000,
          price: InvestmentPrice(
            price: Decimal.fromInt(60),
            currency: CurrencyCode.brl,
            date: LocalDate(2026, 8, 15),
            manual: true,
          ),
          lots: const [],
        ),
      ],
    ),
  );
}

DashboardSnapshot _dashboard({
  required LocalDate asOf,
  required int expense,
  required int available,
  required EntityId category,
  required int categoryExpense,
}) => DashboardSnapshot(
  reportingCurrency: CurrencyCode.brl,
  periodStart: LocalDate(asOf.year, asOf.month, 1),
  periodEnd: LocalDate(
    asOf.year,
    asOf.month,
    DateTime.utc(asOf.year, asOf.month + 1, 0).day,
  ),
  availableMoneyMinor: available,
  incomeMinor: 0,
  expenseMinor: expense,
  spendingByCategory: [
    CategorySpending(categoryId: category, amountMinor: categoryExpense),
  ],
  cashFlow: const [],
  accountBalances: const [],
  missingRates: const {},
  usesEstimatedRates: false,
  upcomingCount: 0,
);

NetWorthPoint _worth(LocalDate date, int assets, int liabilities) =>
    NetWorthPoint(
      date: date,
      assetsMinor: assets,
      liabilitiesMinor: liabilities,
      missingRates: const {},
      usesEstimatedRates: false,
    );
