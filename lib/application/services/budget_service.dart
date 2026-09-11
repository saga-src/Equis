import '../ports/budget_repository.dart';
import '../ports/dashboard_repository.dart';
import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class BudgetService {
  const BudgetService({required this.repository, required this.reporting});

  final BudgetRepository repository;
  final DashboardRepository reporting;

  Future<BudgetDefinition> create({
    required EntityId vaultId,
    required String name,
    required CurrencyCode currency,
    required int limitMinor,
    required BudgetPeriodType periodType,
    required int warningThresholdBps,
    required BudgetScope scope,
    required UtcInstant now,
    LocalDate? startsOn,
    LocalDate? endsOn,
  }) async {
    final budget = BudgetDefinition(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: name.trim(),
      currency: currency,
      limitMinor: limitMinor,
      periodType: periodType,
      startsOn: startsOn,
      endsOn: endsOn,
      warningThresholdBps: warningThresholdBps,
      scope: scope,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(budget);
    return budget;
  }

  Future<BudgetDefinition> update({
    required BudgetDefinition existing,
    required String name,
    required int limitMinor,
    required BudgetPeriodType periodType,
    required int warningThresholdBps,
    required BudgetScope scope,
    required bool enabled,
    required UtcInstant now,
    LocalDate? startsOn,
    LocalDate? endsOn,
  }) async {
    final budget = existing.revise(
      name: name.trim(),
      limitMinor: limitMinor,
      periodType: periodType,
      startsOn: startsOn,
      endsOn: endsOn,
      warningThresholdBps: warningThresholdBps,
      scope: scope,
      enabled: enabled,
      at: now,
    );
    await repository.save(budget);
    return budget;
  }

  Future<void> delete(BudgetDefinition existing, {required UtcInstant now}) =>
      repository.save(existing.revise(deletedAt: now, at: now));

  Future<List<BudgetProgress>> loadProgress({
    required EntityId vaultId,
    required LocalDate asOf,
  }) async {
    final budgets = (await repository.listForVault(
      vaultId,
    )).where((budget) => budget.enabled).toList(growable: false);
    if (budgets.isEmpty) return const [];
    reporting.beginRead();
    final parents = await repository.loadCategoryParents(vaultId);
    final periods = {
      for (final budget in budgets)
        budget.id: BudgetPeriod.forDate(budget, asOf),
    };
    var from = periods.values.first.start;
    var through = _through(periods.values.first, asOf);
    for (final period in periods.values.skip(1)) {
      if (period.start.compareTo(from) < 0) from = period.start;
      final candidate = _through(period, asOf);
      if (candidate.compareTo(through) > 0) through = candidate;
    }
    final rows = through.compareTo(from) < 0
        ? const <BudgetUsageRow>[]
        : await repository.loadUsageRows(
            vaultId: vaultId,
            from: from,
            through: through,
          );
    final result = <BudgetProgress>[];
    for (final budget in budgets) {
      final period = periods[budget.id]!;
      var used = 0;
      var estimated = false;
      final missing = <CurrencyCode>{};
      for (final row in rows) {
        if (!period.contains(row.date) ||
            row.date.compareTo(asOf) > 0 ||
            !_matches(budget.scope, row, parents)) {
          continue;
        }
        final converted = await reporting.convertMinor(
          vaultId: vaultId,
          source: row.currency,
          target: budget.currency,
          date: row.date,
          amountMinor: row.amountMinor,
        );
        if (converted == null) {
          missing.add(row.currency);
          continue;
        }
        used += converted.minorUnits;
        estimated |= converted.estimated;
      }
      if (used < 0) used = 0;
      final usageBps = _roundRatio(used, budget.limitMinor, 10000);
      final elapsed = _elapsedDays(period, asOf);
      final projected = elapsed == 0
          ? 0
          : _roundRatio(used, elapsed, period.totalDays);
      result.add(
        BudgetProgress(
          budget: budget,
          period: period,
          usedMinor: used,
          projectedMinor: projected,
          warningState: _warningState(
            used: used,
            limit: budget.limitMinor,
            thresholdBps: budget.warningThresholdBps,
          ),
          usageBps: usageBps,
          missingRates: missing,
          usesEstimatedRates: estimated,
        ),
      );
    }
    result.sort((a, b) {
      final warning = b.warningState.index.compareTo(a.warningState.index);
      return warning != 0 ? warning : b.usageBps.compareTo(a.usageBps);
    });
    return result;
  }
}

LocalDate _through(BudgetPeriod period, LocalDate asOf) =>
    asOf.compareTo(period.end) < 0 ? asOf : period.end;

int _elapsedDays(BudgetPeriod period, LocalDate asOf) {
  if (asOf.compareTo(period.start) < 0) return 0;
  final through = _through(period, asOf);
  return through.toUtcDate().difference(period.start.toUtcDate()).inDays + 1;
}

int _roundRatio(int value, int divisor, int multiplier) {
  if (value == 0) return 0;
  final numerator = BigInt.from(value) * BigInt.from(multiplier);
  final denominator = BigInt.from(divisor);
  final rounded = (numerator + (denominator ~/ BigInt.two)) ~/ denominator;
  return rounded.toInt();
}

BudgetWarningState _warningState({
  required int used,
  required int limit,
  required int thresholdBps,
}) {
  if (used > limit) return BudgetWarningState.exceeded;
  if (used == limit) return BudgetWarningState.limitReached;
  return _roundRatio(used, limit, 10000) >= thresholdBps
      ? BudgetWarningState.approachingLimit
      : BudgetWarningState.safe;
}

bool _matches(
  BudgetScope scope,
  BudgetUsageRow row,
  Map<EntityId, EntityId?> parents,
) {
  final categoryMatches =
      scope.categories.isEmpty ||
      scope.categories.any(
        (candidate) =>
            row.categoryId == candidate.categoryId ||
            (candidate.includeDescendants &&
                _isDescendantOf(row.categoryId, candidate.categoryId, parents)),
      );
  final accountMatches =
      scope.accountIds.isEmpty || row.accountIds.any(scope.accountIds.contains);
  final tagMatches =
      scope.tagIds.isEmpty || row.tagIds.any(scope.tagIds.contains);
  return categoryMatches && accountMatches && tagMatches;
}

bool _isDescendantOf(
  EntityId category,
  EntityId ancestor,
  Map<EntityId, EntityId?> parents,
) {
  final visited = <EntityId>{};
  var current = parents[category];
  while (current != null && visited.add(current)) {
    if (current == ancestor) return true;
    current = parents[current];
  }
  return false;
}
