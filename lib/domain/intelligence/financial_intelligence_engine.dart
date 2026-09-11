import '../budgeting/budget_models.dart';
import '../goals/cash_flow_projection.dart';
import 'financial_intelligence_models.dart';

final class FinancialIntelligenceEngine {
  const FinancialIntelligenceEngine();

  FinancialIntelligenceReport analyze(FinancialIntelligenceInputs input) {
    final insights = <FinancialInsight>[];
    _spending(input, insights);
    _budgets(input, insights);
    _cashFlow(input, insights);
    _goals(input, insights);
    _emergencyFund(input, insights);
    _debt(input, insights);
    _netWorth(input, insights);
    _allocation(input, insights);
    insights.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return FinancialIntelligenceReport(
      enabled: true,
      asOf: input.asOf,
      currency: input.currentMonth.reportingCurrency,
      insights: insights,
    );
  }

  void _spending(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    if (input.previousMonths.isEmpty) return;
    final current = input.currentMonth;
    final previous = input.previousMonths.first;
    final elapsed = input.asOf.day;
    final days = current.periodEnd.day;
    final projected = _ratio(current.expenseMinor, elapsed, days);
    if (previous.expenseMinor > 0) {
      final delta = _ratio(projected, previous.expenseMinor, 10000) - 10000;
      result.add(
        FinancialInsight(
          kind: FinancialInsightKind.spendingTrend,
          severity: delta >= 2000
              ? FinancialInsightSeverity.caution
              : delta <= -1000
              ? FinancialInsightSeverity.positive
              : FinancialInsightSeverity.information,
          metrics: {
            'current_minor': current.expenseMinor,
            'projected_minor': projected,
            'previous_minor': previous.expenseMinor,
            'delta_bps': delta,
            'elapsed_days': elapsed,
            'period_days': days,
          },
        ),
      );
    }

    final priorByCategory = {
      for (final value in previous.spendingByCategory)
        value.categoryId: value.amountMinor,
    };
    final anomalies = <FinancialInsight>[];
    for (final value in current.spendingByCategory) {
      final prior = priorByCategory[value.categoryId] ?? 0;
      if (prior <= 0) continue;
      final categoryProjected = _ratio(value.amountMinor, elapsed, days);
      final delta = _ratio(categoryProjected, prior, 10000) - 10000;
      if (delta < 5000 || value.amountMinor < 1000) continue;
      anomalies.add(
        FinancialInsight(
          kind: FinancialInsightKind.expenseAnomaly,
          severity: delta >= 10000
              ? FinancialInsightSeverity.critical
              : FinancialInsightSeverity.caution,
          sourceId: value.categoryId,
          metrics: {
            'current_minor': value.amountMinor,
            'projected_minor': categoryProjected,
            'previous_minor': prior,
            'delta_bps': delta,
            'elapsed_days': elapsed,
            'period_days': days,
          },
        ),
      );
    }
    anomalies.sort(
      (a, b) => b.metrics['delta_bps']!.compareTo(a.metrics['delta_bps']!),
    );
    result.addAll(anomalies.take(3));
  }

  void _budgets(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    for (final progress in input.budgets.where(
      (value) =>
          value.likelyToExceed || value.warningState != BudgetWarningState.safe,
    )) {
      result.add(
        FinancialInsight(
          kind: FinancialInsightKind.budgetForecast,
          severity:
              progress.warningState == BudgetWarningState.exceeded ||
                  progress.projectedMinor >
                      progress.budget.limitMinor * 12 ~/ 10
              ? FinancialInsightSeverity.critical
              : FinancialInsightSeverity.caution,
          sourceId: progress.budget.id,
          label: progress.budget.name,
          metrics: {
            'used_minor': progress.usedMinor,
            'projected_minor': progress.projectedMinor,
            'limit_minor': progress.budget.limitMinor,
            'usage_bps': progress.usageBps,
          },
        ),
      );
    }
  }

  void _cashFlow(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    final flow = input.cashFlow;
    result.add(
      FinancialInsight(
        kind: FinancialInsightKind.cashFlowForecast,
        severity: flow.closingProjectedMinor < 0
            ? FinancialInsightSeverity.critical
            : flow.closingProjectedMinor < flow.openingAvailableMinor ~/ 4
            ? FinancialInsightSeverity.caution
            : FinancialInsightSeverity.information,
        metrics: {
          'opening_minor': flow.openingAvailableMinor,
          'closing_minor': flow.closingProjectedMinor,
          'event_count': flow.events.length,
          'days':
              flow.through
                  .toUtcDate()
                  .difference(flow.from.toUtcDate())
                  .inDays +
              1,
        },
      ),
    );
    final recurring = flow.events.where(
      (value) => value.type == CashFlowEventType.recurringExpense,
    );
    final recurringCount = recurring.length;
    if (recurringCount > 0) {
      result.add(
        FinancialInsight(
          kind: FinancialInsightKind.recurringCommitments,
          severity: FinancialInsightSeverity.information,
          metrics: {
            'count': recurringCount,
            'total_minor': recurring.fold(
              0,
              (sum, value) => sum + value.amountMinor.abs(),
            ),
          },
        ),
      );
    }
  }

  void _goals(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    for (final progress in input.goals.where(
      (value) => !value.targetIsReached,
    )) {
      final required = progress.requiredMonthlyMinor;
      if (required == null) continue;
      final planned = progress.goal.plannedMonthlyMinor ?? 0;
      if (planned >= required) continue;
      result.add(
        FinancialInsight(
          kind: FinancialInsightKind.goalContribution,
          severity: FinancialInsightSeverity.caution,
          sourceId: progress.goal.id,
          label: progress.goal.name,
          metrics: {
            'current_minor': progress.currentMinor,
            'remaining_minor': progress.remainingMinor,
            'planned_minor': planned,
            'required_minor': required,
            'gap_minor': required - planned,
          },
        ),
      );
    }
  }

  void _emergencyFund(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    final complete = input.previousMonths.where((value) => value.isComplete);
    if (complete.isEmpty) return;
    final average =
        complete.fold(0, (sum, value) => sum + value.expenseMinor) ~/
        complete.length;
    if (average <= 0) return;
    final coverageMilli = _ratio(
      input.currentMonth.availableMoneyMinor,
      average,
      1000,
    );
    result.add(
      FinancialInsight(
        kind: FinancialInsightKind.emergencyFund,
        severity: coverageMilli < 3000
            ? FinancialInsightSeverity.caution
            : coverageMilli >= 6000
            ? FinancialInsightSeverity.positive
            : FinancialInsightSeverity.information,
        metrics: {
          'liquid_minor': input.currentMonth.availableMoneyMinor,
          'average_expense_minor': average,
          'coverage_milli_months': coverageMilli,
          'sample_months': complete.length,
        },
      ),
    );
  }

  void _debt(FinancialIntelligenceInputs input, List<FinancialInsight> result) {
    final debt = input.wealth.current.liabilitiesMinor;
    if (debt <= 0) return;
    final asset = input.wealth.current.assetsMinor;
    result.add(
      FinancialInsight(
        kind: FinancialInsightKind.debtOverview,
        severity: debt > asset
            ? FinancialInsightSeverity.critical
            : debt * 2 > asset
            ? FinancialInsightSeverity.caution
            : FinancialInsightSeverity.information,
        metrics: {
          'debt_minor': debt,
          'asset_minor': asset,
          'debt_to_asset_bps': asset <= 0 ? 10000 : _ratio(debt, asset, 10000),
        },
      ),
    );
  }

  void _netWorth(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    if (input.wealth.history.length < 2) return;
    final first = input.wealth.history.first.netWorthMinor;
    final current = input.wealth.current.netWorthMinor;
    final delta = current - first;
    final deltaBps = first == 0 ? 0 : _ratio(delta, first.abs(), 10000);
    result.add(
      FinancialInsight(
        kind: FinancialInsightKind.netWorthTrend,
        severity: delta < 0
            ? FinancialInsightSeverity.caution
            : delta > 0
            ? FinancialInsightSeverity.positive
            : FinancialInsightSeverity.information,
        metrics: {
          'starting_minor': first,
          'current_minor': current,
          'delta_minor': delta,
          'delta_bps': deltaBps,
          'sample_months': input.wealth.history.length,
        },
      ),
    );
  }

  void _allocation(
    FinancialIntelligenceInputs input,
    List<FinancialInsight> result,
  ) {
    if (input.portfolio.holdings.isEmpty) return;
    final holding = input.portfolio.holdings.reduce(
      (a, b) => a.allocationBps >= b.allocationBps ? a : b,
    );
    result.add(
      FinancialInsight(
        kind: FinancialInsightKind.investmentConcentration,
        severity: holding.allocationBps >= 5000
            ? FinancialInsightSeverity.caution
            : FinancialInsightSeverity.information,
        sourceId: holding.instrument.id,
        label: holding.instrument.symbol ?? holding.instrument.name,
        metrics: {
          'allocation_bps': holding.allocationBps,
          'holding_count': input.portfolio.holdings.length,
          'portfolio_minor': input.portfolio.marketValueMinor,
        },
      ),
    );
  }
}

int _ratio(int value, int divisor, int multiplier) {
  if (divisor == 0) return 0;
  final negative = value.isNegative != divisor.isNegative;
  var numerator = BigInt.from(value.abs()) * BigInt.from(multiplier.abs());
  final denominator = BigInt.from(divisor.abs());
  numerator += denominator ~/ BigInt.two;
  final result = (numerator ~/ denominator).toInt();
  return negative ? -result : result;
}
