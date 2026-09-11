import '../ports/dashboard_repository.dart';
import '../ports/goal_repository.dart';
import 'dashboard_service.dart';
import 'recurring_transaction_service.dart';
import '../../domain/goals/cash_flow_projection.dart';
import '../../domain/goals/goal_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

final class CashFlowProjectionService {
  const CashFlowProjectionService({
    required this.repository,
    required this.reporting,
    required this.dashboard,
    required this.recurring,
  });

  final GoalRepository repository;
  final DashboardRepository reporting;
  final DashboardService dashboard;
  final RecurringTransactionService recurring;

  Future<CashFlowProjection> load({
    required EntityId vaultId,
    required CurrencyCode reportingCurrency,
    required LocalDate asOf,
    required LocalDate through,
  }) async {
    if (through.compareTo(asOf) <= 0) {
      throw ArgumentError('Projection end must be after the as-of date.');
    }
    final current = await dashboard.load(
      vaultId: vaultId,
      reportingCurrency: reportingCurrency,
      asOf: asOf,
    );
    reporting.beginRead();
    final sources = await repository.cashFlowSources(
      vaultId: vaultId,
      after: asOf,
      through: through,
    );
    final recurringRows = await recurring.upcoming(
      vaultId: vaultId,
      from: asOf.addDays(1),
      through: through,
      limit: 200,
    );
    for (final occurrence in recurringRows) {
      final template = occurrence.schedule.template;
      if (template.transactionType != LedgerTransactionType.income &&
          template.transactionType != LedgerTransactionType.expense) {
        continue;
      }
      for (final split in template.splits) {
        sources.add(
          CashFlowSourceRow(
            id: occurrence.schedule.rule.id,
            type: template.transactionType == LedgerTransactionType.income
                ? CashFlowEventType.recurringIncome
                : CashFlowEventType.recurringExpense,
            date: occurrence.scheduledDate,
            currency: split.money.currency,
            amountMinor:
                template.transactionType == LedgerTransactionType.income
                ? split.money.minorUnits.abs()
                : -split.money.minorUnits.abs(),
            name: occurrence.schedule.rule.name,
          ),
        );
      }
    }
    final goals = await repository.listForVault(vaultId);
    for (final goal in goals.where(
      (item) =>
          item.status == GoalStatus.active &&
          item.trackingMode == GoalTrackingMode.manual &&
          (item.plannedMonthlyMinor ?? 0) > 0,
    )) {
      for (final date in _monthEnds(after: asOf, through: through)) {
        sources.add(
          CashFlowSourceRow(
            id: goal.id,
            type: CashFlowEventType.goalContribution,
            date: date,
            currency: goal.currency,
            amountMinor: -goal.plannedMonthlyMinor!,
            name: goal.name,
          ),
        );
      }
    }
    sources.sort((a, b) {
      final date = a.date.compareTo(b.date);
      return date != 0 ? date : a.type.index.compareTo(b.type.index);
    });
    final missing = <CurrencyCode>{...current.missingRates};
    var estimated = current.usesEstimatedRates;
    var balance = current.availableMoneyMinor;
    final events = <ProjectedCashFlowEvent>[];
    for (final source in sources) {
      final converted = await reporting.convertMinor(
        vaultId: vaultId,
        source: source.currency,
        target: reportingCurrency,
        date: source.date,
        amountMinor: source.amountMinor,
      );
      if (converted == null) {
        missing.add(source.currency);
        continue;
      }
      balance += converted.minorUnits;
      estimated |= converted.estimated;
      events.add(
        ProjectedCashFlowEvent(
          sourceId: source.id,
          type: source.type,
          date: source.date,
          amountMinor: converted.minorUnits,
          balanceAfterMinor: balance,
          name: source.name,
        ),
      );
    }
    return CashFlowProjection(
      reportingCurrency: reportingCurrency,
      from: asOf.addDays(1),
      through: through,
      openingAvailableMinor: current.availableMoneyMinor,
      closingProjectedMinor: balance,
      events: events,
      missingRates: missing,
      usesEstimatedRates: estimated,
    );
  }
}

Iterable<LocalDate> _monthEnds({
  required LocalDate after,
  required LocalDate through,
}) sync* {
  var year = after.year;
  var month = after.month;
  while (true) {
    final end = LocalDate(year, month, DateTime.utc(year, month + 1, 0).day);
    if (end.compareTo(through) > 0) return;
    if (end.compareTo(after) > 0) yield end;
    month++;
    if (month == 13) {
      month = 1;
      year++;
    }
  }
}
