import '../../domain/intelligence/financial_intelligence_engine.dart';
import '../../domain/intelligence/financial_intelligence_models.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import 'budget_service.dart';
import 'cash_flow_projection_service.dart';
import 'dashboard_service.dart';
import 'goal_service.dart';
import 'investment_service.dart';
import 'wealth_service.dart';

final class FinancialIntelligenceService {
  const FinancialIntelligenceService({
    required this.dashboard,
    required this.budgets,
    required this.goals,
    required this.cashFlow,
    required this.wealth,
    required this.investments,
    this.engine = const FinancialIntelligenceEngine(),
    this.enabled = true,
  });

  const FinancialIntelligenceService.disabled()
    : dashboard = null,
      budgets = null,
      goals = null,
      cashFlow = null,
      wealth = null,
      investments = null,
      engine = const FinancialIntelligenceEngine(),
      enabled = false;

  final DashboardService? dashboard;
  final BudgetService? budgets;
  final GoalService? goals;
  final CashFlowProjectionService? cashFlow;
  final WealthService? wealth;
  final InvestmentService? investments;
  final FinancialIntelligenceEngine engine;
  final bool enabled;

  Future<FinancialIntelligenceReport> load({
    required EntityId vaultId,
    required CurrencyCode currency,
    required LocalDate asOf,
  }) async {
    if (!enabled) {
      return FinancialIntelligenceReport(
        enabled: false,
        asOf: asOf,
        currency: currency,
        insights: const [],
      );
    }
    final current = await dashboard!.load(
      vaultId: vaultId,
      reportingCurrency: currency,
      asOf: asOf,
    );
    final previous = <DashboardSnapshot>[];
    for (var offset = 1; offset <= 3; offset++) {
      final date = _monthEnd(asOf, -offset);
      previous.add(
        await dashboard!.load(
          vaultId: vaultId,
          reportingCurrency: currency,
          asOf: date,
        ),
      );
    }
    final input = FinancialIntelligenceInputs(
      asOf: asOf,
      currentMonth: current,
      previousMonths: previous,
      budgets: await budgets!.loadProgress(vaultId: vaultId, asOf: asOf),
      goals: await goals!.loadProgress(vaultId: vaultId, asOf: asOf),
      cashFlow: await cashFlow!.load(
        vaultId: vaultId,
        reportingCurrency: currency,
        asOf: asOf,
        through: asOf.addDays(30),
      ),
      wealth: await wealth!.report(
        vaultId: vaultId,
        currency: currency,
        asOf: asOf,
        historyMonths: 4,
      ),
      portfolio: await investments!.report(
        vaultId: vaultId,
        currency: currency,
        asOf: asOf,
      ),
    );
    return engine.analyze(input);
  }
}

LocalDate _monthEnd(LocalDate value, int offset) {
  final zeroBased = value.year * 12 + value.month - 1 + offset;
  final year = zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  return LocalDate(year, month, DateTime.utc(year, month + 1, 0).day);
}
