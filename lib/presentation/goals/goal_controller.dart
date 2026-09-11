import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/cash_flow_projection_service.dart';
import '../../application/services/goal_service.dart';
import '../../domain/goals/cash_flow_projection.dart';
import '../../domain/goals/goal_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class GoalState {
  const GoalState({
    this.items = const [],
    this.cashFlow,
    this.loading = false,
    this.error,
  });

  final List<GoalProgress> items;
  final CashFlowProjection? cashFlow;
  final bool loading;
  final Object? error;
}

final class GoalController extends StateNotifier<GoalState> {
  GoalController({
    required GoalService? goals,
    required CashFlowProjectionService? cashFlow,
    required EntityId? vaultId,
    required CurrencyCode? reportingCurrency,
  }) : this._(goals, cashFlow, vaultId, reportingCurrency);

  GoalController._(
    this._goals,
    this._cashFlow,
    this._vaultId,
    this._reportingCurrency,
  ) : super(const GoalState());

  final GoalService? _goals;
  final CashFlowProjectionService? _cashFlow;
  final EntityId? _vaultId;
  final CurrencyCode? _reportingCurrency;

  Future<void> reload() async {
    final goals = _goals;
    final cashFlow = _cashFlow;
    final vaultId = _vaultId;
    final currency = _reportingCurrency;
    if (goals == null ||
        cashFlow == null ||
        vaultId == null ||
        currency == null) {
      return;
    }
    state = GoalState(
      items: state.items,
      cashFlow: state.cashFlow,
      loading: true,
    );
    try {
      final today = _today();
      final values = await Future.wait<Object>([
        goals.loadProgress(vaultId: vaultId, asOf: today),
        cashFlow.load(
          vaultId: vaultId,
          reportingCurrency: currency,
          asOf: today,
          through: today.addDays(90),
        ),
      ]);
      state = GoalState(
        items: values[0] as List<GoalProgress>,
        cashFlow: values[1] as CashFlowProjection,
      );
    } catch (error) {
      state = GoalState(
        items: state.items,
        cashFlow: state.cashFlow,
        error: error,
      );
    }
  }

  Future<void> create({
    required String name,
    required GoalType type,
    required CurrencyCode currency,
    required String targetText,
    required String plannedMonthlyText,
    required GoalTrackingMode trackingMode,
    required int priority,
    required Set<EntityId> accountPocketIds,
    LocalDate? targetDate,
  }) => _mutate(
    () => _requiredGoals.create(
      vaultId: _requiredVault,
      name: name,
      type: type,
      currency: currency,
      targetMinor: _minor(targetText, currency),
      startsOn: _today(),
      targetDate: targetDate,
      plannedMonthlyMinor: plannedMonthlyText.trim().isEmpty
          ? null
          : _minor(plannedMonthlyText, currency),
      trackingMode: trackingMode,
      priority: priority,
      accountPocketIds: accountPocketIds,
      now: UtcInstant.now(),
    ),
  );

  Future<void> update({
    required GoalDefinition existing,
    required String name,
    required GoalType type,
    required String targetText,
    required String plannedMonthlyText,
    required GoalTrackingMode trackingMode,
    required int priority,
    required Set<EntityId> accountPocketIds,
    LocalDate? targetDate,
  }) => _mutate(
    () => _requiredGoals.update(
      existing: existing,
      name: name,
      type: type,
      targetMinor: _minor(targetText, existing.currency),
      targetDate: targetDate,
      plannedMonthlyMinor: plannedMonthlyText.trim().isEmpty
          ? null
          : _minor(plannedMonthlyText, existing.currency),
      trackingMode: trackingMode,
      priority: priority,
      accountPocketIds: accountPocketIds,
      status: existing.status,
      now: UtcInstant.now(),
    ),
  );

  Future<void> contribute({
    required GoalDefinition goal,
    required String amountText,
    required LocalDate date,
    EntityId? transactionId,
    String? notes,
  }) => _mutate(
    () => _requiredGoals.contribute(
      goal: goal,
      amountMinor: _minor(amountText, goal.currency),
      date: date,
      transactionId: transactionId,
      notes: notes,
    ),
  );

  Future<void> delete(GoalDefinition goal) =>
      _mutate(() => _requiredGoals.delete(goal, now: UtcInstant.now()));

  Future<void> _mutate(Future<Object?> Function() action) async {
    if (state.loading) return;
    state = GoalState(
      items: state.items,
      cashFlow: state.cashFlow,
      loading: true,
    );
    try {
      await action();
      await reload();
    } catch (error) {
      state = GoalState(
        items: state.items,
        cashFlow: state.cashFlow,
        error: error,
      );
    }
  }

  GoalService get _requiredGoals =>
      _goals ?? (throw StateError('Goal services are unavailable.'));
  EntityId get _requiredVault =>
      _vaultId ?? (throw StateError('A local vault is required.'));

  int _minor(String input, CurrencyCode currency) {
    var normalized = input.trim().replaceAll(RegExp(r'\s'), '');
    final comma = normalized.lastIndexOf(',');
    final dot = normalized.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      normalized = comma > dot
          ? normalized.replaceAll('.', '').replaceAll(',', '.')
          : normalized.replaceAll(',', '');
    } else if (comma >= 0) {
      normalized = normalized.replaceAll(',', '.');
    }
    final value = DecimalValue.parse(normalized);
    if (value <= Decimal.zero) throw ArgumentError('Amount must be positive.');
    return Money.fromMajor(
      currency: CurrencyDefinition(code: currency, minorUnits: 2),
      majorUnits: value,
    ).minorUnits;
  }
}

LocalDate _today() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}
