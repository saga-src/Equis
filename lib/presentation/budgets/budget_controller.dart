import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/budget_service.dart';
import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class BudgetState {
  const BudgetState({this.items = const [], this.loading = false, this.error});

  final List<BudgetProgress> items;
  final bool loading;
  final Object? error;
}

final class BudgetController extends StateNotifier<BudgetState> {
  BudgetController({
    required BudgetService? service,
    required EntityId? vaultId,
  }) : this._(service, vaultId);

  BudgetController._(this._service, this._vaultId) : super(const BudgetState());

  final BudgetService? _service;
  final EntityId? _vaultId;

  Future<void> reload() async {
    final service = _service;
    final vaultId = _vaultId;
    if (service == null || vaultId == null) return;
    state = BudgetState(items: state.items, loading: true);
    try {
      state = BudgetState(
        items: await service.loadProgress(vaultId: vaultId, asOf: _today()),
      );
    } catch (error) {
      state = BudgetState(items: state.items, error: error);
    }
  }

  Future<void> create({
    required String name,
    required CurrencyCode currency,
    required String limitText,
    required BudgetPeriodType periodType,
    required int warningThresholdBps,
    required BudgetScope scope,
    LocalDate? startsOn,
    LocalDate? endsOn,
  }) => _mutate(
    () => _requiredService.create(
      vaultId: _requiredVault,
      name: name,
      currency: currency,
      limitMinor: _minor(limitText, currency),
      periodType: periodType,
      startsOn: startsOn,
      endsOn: endsOn,
      warningThresholdBps: warningThresholdBps,
      scope: scope,
      now: UtcInstant.now(),
    ),
  );

  Future<void> update({
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
      limitMinor: _minor(limitText, existing.currency),
      periodType: periodType,
      startsOn: startsOn,
      endsOn: endsOn,
      warningThresholdBps: warningThresholdBps,
      scope: scope,
      enabled: enabled,
      now: UtcInstant.now(),
    ),
  );

  Future<void> delete(BudgetDefinition budget) =>
      _mutate(() => _requiredService.delete(budget, now: UtcInstant.now()));

  Future<void> _mutate(Future<Object?> Function() action) async {
    if (state.loading) return;
    state = BudgetState(items: state.items, loading: true);
    try {
      await action();
      await reload();
    } catch (error) {
      state = BudgetState(items: state.items, error: error);
    }
  }

  BudgetService get _requiredService =>
      _service ?? (throw StateError('Budget services are unavailable.'));

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
    if (value <= Decimal.zero) throw ArgumentError('Limit must be positive.');
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
