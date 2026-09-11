import '../ports/dashboard_repository.dart';
import '../ports/goal_repository.dart';
import '../../domain/goals/goal_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class GoalService {
  const GoalService({required this.repository, required this.reporting});

  final GoalRepository repository;
  final DashboardRepository reporting;

  Future<GoalDefinition> create({
    required EntityId vaultId,
    required String name,
    required GoalType type,
    required CurrencyCode currency,
    required int targetMinor,
    required GoalTrackingMode trackingMode,
    required int priority,
    required Set<EntityId> accountPocketIds,
    required UtcInstant now,
    LocalDate? startsOn,
    LocalDate? targetDate,
    int? plannedMonthlyMinor,
  }) async {
    final goal = GoalDefinition(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: name.trim(),
      type: type,
      currency: currency,
      targetMinor: targetMinor,
      startsOn: startsOn,
      targetDate: targetDate,
      plannedMonthlyMinor: plannedMonthlyMinor,
      trackingMode: trackingMode,
      priority: priority,
      accountPocketIds: accountPocketIds,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(goal);
    return goal;
  }

  Future<GoalDefinition> update({
    required GoalDefinition existing,
    required String name,
    required GoalType type,
    required int targetMinor,
    required GoalTrackingMode trackingMode,
    required int priority,
    required Set<EntityId> accountPocketIds,
    required GoalStatus status,
    required UtcInstant now,
    LocalDate? startsOn,
    LocalDate? targetDate,
    int? plannedMonthlyMinor,
  }) async {
    final goal = existing.revise(
      name: name.trim(),
      type: type,
      targetMinor: targetMinor,
      startsOn: startsOn,
      targetDate: targetDate,
      plannedMonthlyMinor: plannedMonthlyMinor,
      clearTargetDate: targetDate == null,
      clearPlannedMonthly: plannedMonthlyMinor == null,
      trackingMode: trackingMode,
      priority: priority,
      status: status,
      accountPocketIds: accountPocketIds,
      at: now,
    );
    await repository.save(goal);
    return goal;
  }

  Future<void> delete(GoalDefinition goal, {required UtcInstant now}) =>
      repository.save(goal.revise(deletedAt: now, at: now));

  Future<GoalContribution> contribute({
    required GoalDefinition goal,
    required int amountMinor,
    required LocalDate date,
    EntityId? transactionId,
    String? notes,
  }) async {
    if (goal.trackingMode == GoalTrackingMode.linkedAccounts) {
      throw StateError('Linked-account goals derive progress from balances.');
    }
    final contribution = GoalContribution(
      id: EntityId.generate(),
      goalId: goal.id,
      transactionId: transactionId,
      amountMinor: amountMinor,
      date: date,
      notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
    );
    await repository.addContribution(contribution);
    return contribution;
  }

  Future<List<GoalProgress>> loadProgress({
    required EntityId vaultId,
    required LocalDate asOf,
  }) async {
    reporting.beginRead();
    final goals = await repository.listForVault(vaultId);
    final result = <GoalProgress>[];
    for (final goal in goals) {
      final missing = <CurrencyCode>{};
      var estimated = false;
      var current = 0;
      if (goal.trackingMode == GoalTrackingMode.linkedAccounts) {
        for (final balance in await repository.linkedBalances(
          goal,
          asOf: asOf,
        )) {
          final converted = await reporting.convertMinor(
            vaultId: vaultId,
            source: balance.currency,
            target: goal.currency,
            date: asOf,
            amountMinor: balance.balanceMinor,
          );
          if (converted == null) {
            missing.add(balance.currency);
            continue;
          }
          current += converted.minorUnits;
          estimated |= converted.estimated;
        }
      } else {
        current = (await repository.contributions(
          goal.id,
          through: asOf,
        )).fold(0, (sum, item) => sum + item.amountMinor);
      }
      if (current < 0) current = 0;
      final remaining = current >= goal.targetMinor
          ? 0
          : goal.targetMinor - current;
      result.add(
        GoalProgress(
          goal: goal,
          currentMinor: current,
          progressBps: _ratio(current, goal.targetMinor, 10000),
          requiredMonthlyMinor: _requiredMonthly(
            remaining: remaining,
            asOf: asOf,
            targetDate: goal.targetDate,
          ),
          expectedCompletionDate: expectedCompletion(
            asOf: asOf,
            remainingMinor: remaining,
            monthlyMinor: goal.plannedMonthlyMinor,
          ),
          missingRates: missing,
          usesEstimatedRates: estimated,
        ),
      );
    }
    result.sort((a, b) {
      final priority = b.goal.priority.compareTo(a.goal.priority);
      return priority != 0 ? priority : a.goal.name.compareTo(b.goal.name);
    });
    return result;
  }

  LocalDate? expectedCompletionFor({
    required GoalProgress progress,
    required LocalDate asOf,
    required int monthlyMinor,
  }) => expectedCompletion(
    asOf: asOf,
    remainingMinor: progress.remainingMinor,
    monthlyMinor: monthlyMinor,
  );
}

int _ratio(int value, int divisor, int multiplier) {
  if (value <= 0) return 0;
  final result =
      (BigInt.from(value) * BigInt.from(multiplier)) ~/ BigInt.from(divisor);
  return result > BigInt.from(10000) ? 10000 : result.toInt();
}

int? _requiredMonthly({
  required int remaining,
  required LocalDate asOf,
  required LocalDate? targetDate,
}) {
  if (remaining == 0) return 0;
  if (targetDate == null || targetDate.compareTo(asOf) < 0) return null;
  final months =
      (targetDate.year - asOf.year) * 12 + targetDate.month - asOf.month + 1;
  return (remaining + months - 1) ~/ months;
}

LocalDate? expectedCompletion({
  required LocalDate asOf,
  required int remainingMinor,
  required int? monthlyMinor,
}) {
  if (remainingMinor == 0) return asOf;
  if (monthlyMinor == null || monthlyMinor <= 0) return null;
  final months = (remainingMinor + monthlyMinor - 1) ~/ monthlyMinor;
  final zeroBased = asOf.month - 1 + months - 1;
  final year = asOf.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  return LocalDate(year, month, DateTime.utc(year, month + 1, 0).day);
}
