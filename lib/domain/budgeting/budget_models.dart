import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum BudgetPeriodType { weekly, monthly, yearly, custom }

enum BudgetWarningState { safe, approachingLimit, limitReached, exceeded }

final class BudgetCategoryScope {
  const BudgetCategoryScope({
    required this.categoryId,
    this.includeDescendants = true,
  });

  final EntityId categoryId;
  final bool includeDescendants;
}

final class BudgetScope {
  BudgetScope({
    List<BudgetCategoryScope> categories = const [],
    Set<EntityId> accountIds = const {},
    Set<EntityId> tagIds = const {},
  }) : categories = List.unmodifiable(categories),
       accountIds = Set.unmodifiable(accountIds),
       tagIds = Set.unmodifiable(tagIds);

  final List<BudgetCategoryScope> categories;
  final Set<EntityId> accountIds;
  final Set<EntityId> tagIds;

  bool get isOverall =>
      categories.isEmpty && accountIds.isEmpty && tagIds.isEmpty;
}

final class BudgetDefinition {
  BudgetDefinition({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.currency,
    required this.limitMinor,
    required this.periodType,
    required this.warningThresholdBps,
    required this.scope,
    required this.createdAt,
    required this.updatedAt,
    this.startsOn,
    this.endsOn,
    this.rolloverPolicy = 'none',
    this.enabled = true,
    this.revision = 1,
    this.deletedAt,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (limitMinor <= 0) throw RangeError.value(limitMinor, 'limitMinor');
    if (warningThresholdBps < 1 || warningThresholdBps > 10000) {
      throw RangeError.range(
        warningThresholdBps,
        1,
        10000,
        'warningThresholdBps',
      );
    }
    if (periodType == BudgetPeriodType.custom &&
        (startsOn == null || endsOn == null)) {
      throw ArgumentError('Custom budgets require both boundary dates.');
    }
    if (startsOn != null &&
        endsOn != null &&
        startsOn!.compareTo(endsOn!) > 0) {
      throw ArgumentError('Budget start must not be after its end.');
    }
    if (rolloverPolicy != 'none') {
      throw ArgumentError.value(
        rolloverPolicy,
        'rolloverPolicy',
        'Phase 10 supports only the explicit no-rollover policy.',
      );
    }
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final CurrencyCode currency;
  final int limitMinor;
  final BudgetPeriodType periodType;
  final LocalDate? startsOn;
  final LocalDate? endsOn;
  final int warningThresholdBps;
  final String rolloverPolicy;
  final bool enabled;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;
  final BudgetScope scope;

  BudgetDefinition revise({
    String? name,
    int? limitMinor,
    BudgetPeriodType? periodType,
    LocalDate? startsOn,
    LocalDate? endsOn,
    int? warningThresholdBps,
    BudgetScope? scope,
    bool? enabled,
    UtcInstant? deletedAt,
    required UtcInstant at,
  }) => BudgetDefinition(
    id: id,
    vaultId: vaultId,
    name: name ?? this.name,
    currency: currency,
    limitMinor: limitMinor ?? this.limitMinor,
    periodType: periodType ?? this.periodType,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn ?? this.endsOn,
    warningThresholdBps: warningThresholdBps ?? this.warningThresholdBps,
    rolloverPolicy: rolloverPolicy,
    enabled: enabled ?? this.enabled,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt ?? this.deletedAt,
    scope: scope ?? this.scope,
  );
}

final class BudgetPeriod {
  const BudgetPeriod({required this.start, required this.end});

  factory BudgetPeriod.forDate(BudgetDefinition budget, LocalDate date) {
    switch (budget.periodType) {
      case BudgetPeriodType.weekly:
        final start = date.addDays(1 - date.toUtcDate().weekday);
        return BudgetPeriod(start: start, end: start.addDays(6));
      case BudgetPeriodType.monthly:
        return BudgetPeriod(
          start: LocalDate(date.year, date.month, 1),
          end: LocalDate(
            date.year,
            date.month,
            DateTime.utc(date.year, date.month + 1, 0).day,
          ),
        );
      case BudgetPeriodType.yearly:
        return BudgetPeriod(
          start: LocalDate(date.year, 1, 1),
          end: LocalDate(date.year, 12, 31),
        );
      case BudgetPeriodType.custom:
        return BudgetPeriod(start: budget.startsOn!, end: budget.endsOn!);
    }
  }

  final LocalDate start;
  final LocalDate end;

  int get totalDays => end.toUtcDate().difference(start.toUtcDate()).inDays + 1;

  bool contains(LocalDate date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
}

final class BudgetUsageRow {
  BudgetUsageRow({
    required this.transactionId,
    required this.categoryId,
    required this.currency,
    required this.amountMinor,
    required this.date,
    required Set<EntityId> accountIds,
    required Set<EntityId> tagIds,
  }) : accountIds = Set.unmodifiable(accountIds),
       tagIds = Set.unmodifiable(tagIds);

  final EntityId transactionId;
  final EntityId categoryId;
  final CurrencyCode currency;
  final int amountMinor;
  final LocalDate date;
  final Set<EntityId> accountIds;
  final Set<EntityId> tagIds;
}

final class BudgetProgress {
  BudgetProgress({
    required this.budget,
    required this.period,
    required this.usedMinor,
    required this.projectedMinor,
    required this.warningState,
    required this.usageBps,
    required Set<CurrencyCode> missingRates,
    required this.usesEstimatedRates,
  }) : missingRates = Set.unmodifiable(missingRates);

  final BudgetDefinition budget;
  final BudgetPeriod period;
  final int usedMinor;
  final int projectedMinor;
  final BudgetWarningState warningState;
  final int usageBps;
  final Set<CurrencyCode> missingRates;
  final bool usesEstimatedRates;

  int get remainingMinor => budget.limitMinor - usedMinor;
  bool get isComplete => missingRates.isEmpty;
  bool get likelyToExceed => projectedMinor > budget.limitMinor;
}
