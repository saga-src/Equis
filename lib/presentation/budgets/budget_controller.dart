import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../application/services/budget_service.dart';
import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/shared/zoned_recurrence.dart';

final class BudgetState {
  const BudgetState({
    this.items = const [],
    this.currentItems = const [],
    this.selectedMonth,
    this.includeDeleted = false,
    this.loading = false,
    this.saving = false,
    this.error,
  });
  final List<BudgetProgress> items;
  final List<BudgetProgress> currentItems;
  final BudgetMonth? selectedMonth;
  final bool includeDeleted;
  final bool loading;
  final bool saving;
  final Object? error;
  BudgetState copyWith({
    List<BudgetProgress>? items,
    List<BudgetProgress>? currentItems,
    BudgetMonth? selectedMonth,
    bool? includeDeleted,
    bool? loading,
    bool? saving,
    Object? error,
  }) => BudgetState(
    items: items ?? this.items,
    currentItems: currentItems ?? this.currentItems,
    selectedMonth: selectedMonth ?? this.selectedMonth,
    includeDeleted: includeDeleted ?? this.includeDeleted,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: error,
  );
}

final class BudgetController extends StateNotifier<BudgetState> {
  BudgetController({
    required BudgetService? service,
    required EntityId? vaultId,
    String timezone = 'UTC',
    DateTime Function()? clock,
  }) : this._(service, vaultId, timezone, clock ?? DateTime.now);
  BudgetController._(this._service, this._vaultId, this._timezone, this._clock)
    : super(const BudgetState());
  final BudgetService? _service;
  final EntityId? _vaultId;
  final String _timezone;
  final DateTime Function() _clock;
  int _generation = 0;
  LocalDate get today {
    ZonedRecurrenceClock.initialize();
    final date = tz.TZDateTime.from(
      _clock().toUtc(),
      _timezone == 'UTC' ? tz.UTC : tz.getLocation(_timezone),
    );
    return LocalDate(date.year, date.month, date.day);
  }

  Future<void> selectMonth(BudgetMonth month) async {
    if (state.saving) return;
    state = state.copyWith(selectedMonth: month, items: const []);
    await reload();
  }

  Future<void> showDeleted(bool value) async {
    if (state.saving) return;
    state = state.copyWith(includeDeleted: value, items: const []);
    await reload();
  }

  Future<void> reload() async {
    final service = _service;
    final vaultId = _vaultId;
    if (service == null || vaultId == null || !mounted) return;
    final generation = ++_generation;
    state = state.copyWith(loading: true);
    try {
      final asOf = today;
      final month = state.selectedMonth ?? BudgetMonth.fromDate(asOf);
      final includeDeleted = state.includeDeleted;
      final items = await service.loadProgress(
        vaultId: vaultId,
        asOf: asOf,
        month: month,
        includeDeleted: includeDeleted,
      );
      final current = month == BudgetMonth.fromDate(asOf) && !includeDeleted
          ? items
          : await service.loadProgress(vaultId: vaultId, asOf: asOf);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        items: items,
        currentItems: current,
        selectedMonth: month,
        loading: false,
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        state = state.copyWith(loading: false, error: error);
      }
    }
  }

  Future<bool> create({
    required String name,
    required CurrencyCode currency,
    required String limitText,
    required BudgetPeriodType periodType,
    required int warningThresholdBps,
    required BudgetScope scope,
    BudgetLimitMethod limitMethod = BudgetLimitMethod.fixed,
    LocalDate? startsOn,
    LocalDate? endsOn,
  }) => _mutate(() {
    final instant = _clock();
    final amount = parseBudgetAmount(limitText, currency);
    final configuration = periodType == BudgetPeriodType.monthly
        ? BudgetMonthlyConfiguration(
            limitMethod: limitMethod,
            amountMinor: amount,
            warningThresholdBps: warningThresholdBps,
            scope: scope,
          )
        : null;
    ZonedRecurrenceClock.initialize();
    final date = tz.TZDateTime.from(
      instant.toUtc(),
      _timezone == 'UTC' ? tz.UTC : tz.getLocation(_timezone),
    );
    final month = BudgetMonth(date.year, date.month);
    return _requiredService.create(
      vaultId: _requiredVault,
      name: name,
      currency: currency,
      limitMinor: configuration?.limitFor(month) ?? amount,
      periodType: periodType,
      startsOn: startsOn,
      endsOn: endsOn,
      warningThresholdBps: warningThresholdBps,
      scope: scope,
      monthlyConfiguration: configuration,
      now: UtcInstant.fromDateTime(instant),
    );
  });
  Future<bool> updateMonthly({
    required BudgetDefinition existing,
    required BudgetMonth month,
    required String name,
    required String limitText,
    required BudgetLimitMethod limitMethod,
    required int warningThresholdBps,
    required BudgetScope scope,
    required BudgetMonthlyEditScope editScope,
  }) => _mutate(
    () => _requiredService.editMonthly(
      existing: existing,
      month: month,
      name: name,
      configuration: BudgetMonthlyConfiguration(
        limitMethod: limitMethod,
        amountMinor: parseBudgetAmount(limitText, existing.currency),
        warningThresholdBps: warningThresholdBps,
        scope: scope,
      ),
      scope: editScope,
      now: UtcInstant.fromDateTime(_clock()),
    ),
  );
  Future<bool> update({
    required BudgetDefinition existing,
    required String name,
    required String limitText,
    required BudgetPeriodType periodType,
    required int warningThresholdBps,
    required BudgetScope scope,
    required bool enabled,
    LocalDate? startsOn,
    LocalDate? endsOn,
  }) => _mutate(
    () => _requiredService.update(
      existing: existing,
      name: name,
      limitMinor: parseBudgetAmount(limitText, existing.currency),
      periodType: periodType,
      startsOn: startsOn,
      endsOn: endsOn,
      warningThresholdBps: warningThresholdBps,
      scope: scope,
      enabled: enabled,
      now: UtcInstant.fromDateTime(_clock()),
    ),
  );
  Future<bool> delete(BudgetDefinition budget) => _mutate(
    () =>
        _requiredService.delete(budget, now: UtcInstant.fromDateTime(_clock())),
  );

  Future<bool> rename(BudgetDefinition budget, String name) => _mutate(
    () => _requiredService.rename(
      budget,
      name: name,
      now: UtcInstant.fromDateTime(_clock()),
    ),
  );
  Future<bool> _mutate(Future<Object?> Function() action) async {
    if (state.saving || !mounted) return false;
    ++_generation;
    state = state.copyWith(saving: true, loading: false);
    try {
      await action();
      if (!mounted) return true;
      state = state.copyWith(saving: false);
      await reload();
      return true;
    } catch (error) {
      if (mounted) state = state.copyWith(saving: false, error: error);
      return false;
    }
  }

  BudgetService get _requiredService =>
      _service ?? (throw StateError('Budget services are unavailable.'));
  EntityId get _requiredVault =>
      _vaultId ?? (throw StateError('A local vault is required.'));
}

int parseBudgetAmount(String input, CurrencyCode currency) {
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
  if (value <= Decimal.zero) throw ArgumentError('Limit must be positive.');
  final minor = Money.fromMajor(
    currency: CurrencyDefinition(code: currency, minorUnits: 2),
    majorUnits: value,
  ).minorUnits;
  if (minor <= 0) throw ArgumentError('Limit must be at least one minor unit.');
  return minor;
}
