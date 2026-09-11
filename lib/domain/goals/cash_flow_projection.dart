import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/uuid_v7.dart';

enum CashFlowEventType {
  recurringIncome,
  recurringExpense,
  installment,
  cardStatement,
  goalContribution,
}

final class CashFlowSourceRow {
  const CashFlowSourceRow({
    required this.id,
    required this.type,
    required this.date,
    required this.currency,
    required this.amountMinor,
    this.name,
  });

  final EntityId id;
  final CashFlowEventType type;
  final LocalDate date;
  final CurrencyCode currency;
  final int amountMinor;
  final String? name;
}

final class ProjectedCashFlowEvent {
  const ProjectedCashFlowEvent({
    required this.sourceId,
    required this.type,
    required this.date,
    required this.amountMinor,
    required this.balanceAfterMinor,
    this.name,
  });

  final EntityId sourceId;
  final CashFlowEventType type;
  final LocalDate date;
  final int amountMinor;
  final int balanceAfterMinor;
  final String? name;
}

final class CashFlowProjection {
  CashFlowProjection({
    required this.reportingCurrency,
    required this.from,
    required this.through,
    required this.openingAvailableMinor,
    required this.closingProjectedMinor,
    required List<ProjectedCashFlowEvent> events,
    required Set<CurrencyCode> missingRates,
    required this.usesEstimatedRates,
  }) : events = List.unmodifiable(events),
       missingRates = Set.unmodifiable(missingRates);

  final CurrencyCode reportingCurrency;
  final LocalDate from;
  final LocalDate through;
  final int openingAvailableMinor;
  final int closingProjectedMinor;
  final List<ProjectedCashFlowEvent> events;
  final Set<CurrencyCode> missingRates;
  final bool usesEstimatedRates;

  bool get isComplete => missingRates.isEmpty;
  bool get isEstimate => true;
}
