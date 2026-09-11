import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum GoalType {
  emergencyFund('emergency_fund'),
  vacation('vacation'),
  vehicle('vehicle'),
  home('home'),
  debtPayoff('debt_payoff'),
  investment('investment'),
  retirement('retirement'),
  education('education'),
  custom('custom');

  const GoalType(this.stored);
  final String stored;

  static GoalType fromStorage(String value) =>
      values.singleWhere((item) => item.stored == value);
}

enum GoalTrackingMode {
  manual('manual'),
  linkedAccounts('linked_accounts'),
  transactions('transactions');

  const GoalTrackingMode(this.stored);
  final String stored;

  static GoalTrackingMode fromStorage(String value) =>
      values.singleWhere((item) => item.stored == value);
}

enum GoalStatus { active, completed, paused, cancelled }

final class GoalDefinition {
  GoalDefinition({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.type,
    required this.currency,
    required this.targetMinor,
    required this.trackingMode,
    required this.priority,
    required Set<EntityId> accountPocketIds,
    required this.createdAt,
    required this.updatedAt,
    this.startsOn,
    this.targetDate,
    this.plannedMonthlyMinor,
    this.status = GoalStatus.active,
    this.revision = 1,
    this.deletedAt,
  }) : accountPocketIds = Set.unmodifiable(accountPocketIds) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (targetMinor <= 0) throw RangeError.value(targetMinor, 'targetMinor');
    if (plannedMonthlyMinor != null && plannedMonthlyMinor! < 0) {
      throw RangeError.value(plannedMonthlyMinor!, 'plannedMonthlyMinor');
    }
    if (priority < 0) throw RangeError.value(priority, 'priority');
    if (startsOn != null &&
        targetDate != null &&
        startsOn!.compareTo(targetDate!) > 0) {
      throw ArgumentError('Goal start must not be after its target date.');
    }
    if (trackingMode == GoalTrackingMode.linkedAccounts &&
        accountPocketIds.isEmpty) {
      throw ArgumentError('Linked-account goals require at least one pocket.');
    }
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final GoalType type;
  final CurrencyCode currency;
  final int targetMinor;
  final LocalDate? startsOn;
  final LocalDate? targetDate;
  final int? plannedMonthlyMinor;
  final GoalTrackingMode trackingMode;
  final int priority;
  final GoalStatus status;
  final Set<EntityId> accountPocketIds;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  GoalDefinition revise({
    String? name,
    GoalType? type,
    int? targetMinor,
    LocalDate? startsOn,
    LocalDate? targetDate,
    int? plannedMonthlyMinor,
    bool clearStartsOn = false,
    bool clearTargetDate = false,
    bool clearPlannedMonthly = false,
    GoalTrackingMode? trackingMode,
    int? priority,
    GoalStatus? status,
    Set<EntityId>? accountPocketIds,
    UtcInstant? deletedAt,
    required UtcInstant at,
  }) => GoalDefinition(
    id: id,
    vaultId: vaultId,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency,
    targetMinor: targetMinor ?? this.targetMinor,
    startsOn: clearStartsOn ? null : startsOn ?? this.startsOn,
    targetDate: clearTargetDate ? null : targetDate ?? this.targetDate,
    plannedMonthlyMinor: clearPlannedMonthly
        ? null
        : plannedMonthlyMinor ?? this.plannedMonthlyMinor,
    trackingMode: trackingMode ?? this.trackingMode,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    accountPocketIds: accountPocketIds ?? this.accountPocketIds,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

final class GoalContribution {
  GoalContribution({
    required this.id,
    required this.goalId,
    required this.amountMinor,
    required this.date,
    this.transactionId,
    this.notes,
  }) {
    if (amountMinor <= 0) throw RangeError.value(amountMinor, 'amountMinor');
  }

  final EntityId id;
  final EntityId goalId;
  final EntityId? transactionId;
  final int amountMinor;
  final LocalDate date;
  final String? notes;
}

final class GoalAccountBalance {
  const GoalAccountBalance({
    required this.pocketId,
    required this.currency,
    required this.balanceMinor,
  });

  final EntityId pocketId;
  final CurrencyCode currency;
  final int balanceMinor;
}

final class GoalProgress {
  GoalProgress({
    required this.goal,
    required this.currentMinor,
    required this.progressBps,
    required this.requiredMonthlyMinor,
    required this.expectedCompletionDate,
    required Set<CurrencyCode> missingRates,
    required this.usesEstimatedRates,
  }) : missingRates = Set.unmodifiable(missingRates);

  final GoalDefinition goal;
  final int currentMinor;
  final int progressBps;
  final int? requiredMonthlyMinor;
  final LocalDate? expectedCompletionDate;
  final Set<CurrencyCode> missingRates;
  final bool usesEstimatedRates;

  int get remainingMinor =>
      currentMinor >= goal.targetMinor ? 0 : goal.targetMinor - currentMinor;
  bool get isComplete => missingRates.isEmpty;
  bool get targetIsReached => currentMinor >= goal.targetMinor;
}
