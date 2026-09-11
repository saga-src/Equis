import '../budgeting/budget_models.dart';
import '../goals/cash_flow_projection.dart';
import '../goals/goal_models.dart';
import '../investments/investment_models.dart';
import '../reporting/dashboard_models.dart';
import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/uuid_v7.dart';
import '../wealth/net_worth_models.dart';

enum FinancialInsightKind {
  spendingTrend,
  expenseAnomaly,
  budgetForecast,
  cashFlowForecast,
  recurringCommitments,
  goalContribution,
  emergencyFund,
  debtOverview,
  netWorthTrend,
  investmentConcentration,
}

enum FinancialInsightSeverity { positive, information, caution, critical }

final class FinancialInsight {
  FinancialInsight({
    required this.kind,
    required this.severity,
    required Map<String, int> metrics,
    this.sourceId,
    this.label,
  }) : metrics = Map.unmodifiable(metrics);

  final FinancialInsightKind kind;
  final FinancialInsightSeverity severity;
  final Map<String, int> metrics;
  final EntityId? sourceId;
  final String? label;
}

final class FinancialIntelligenceReport {
  FinancialIntelligenceReport({
    required this.enabled,
    required this.asOf,
    required this.currency,
    required List<FinancialInsight> insights,
  }) : insights = List.unmodifiable(insights);

  final bool enabled;
  final LocalDate asOf;
  final CurrencyCode currency;
  final List<FinancialInsight> insights;
}

final class FinancialIntelligenceInputs {
  FinancialIntelligenceInputs({
    required this.asOf,
    required this.currentMonth,
    required List<DashboardSnapshot> previousMonths,
    required List<BudgetProgress> budgets,
    required List<GoalProgress> goals,
    required this.cashFlow,
    required this.wealth,
    required this.portfolio,
  }) : previousMonths = List.unmodifiable(previousMonths),
       budgets = List.unmodifiable(budgets),
       goals = List.unmodifiable(goals);

  final LocalDate asOf;
  final DashboardSnapshot currentMonth;
  final List<DashboardSnapshot> previousMonths;
  final List<BudgetProgress> budgets;
  final List<GoalProgress> goals;
  final CashFlowProjection cashFlow;
  final NetWorthReport wealth;
  final PortfolioReport portfolio;
}
