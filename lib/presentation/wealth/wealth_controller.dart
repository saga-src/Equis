import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/wealth_service.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/wealth/asset_models.dart';
import '../../domain/wealth/net_worth_models.dart';

final class WealthState {
  const WealthState({this.report, this.loading = false, this.error});
  final NetWorthReport? report;
  final bool loading;
  final Object? error;
}

final class WealthController extends StateNotifier<WealthState> {
  WealthController({
    required WealthService? service,
    required EntityId? vaultId,
    required CurrencyCode? reportingCurrency,
  }) : this._(service, vaultId, reportingCurrency);

  WealthController._(this._service, this._vaultId, this._reportingCurrency)
    : super(const WealthState());

  final WealthService? _service;
  final EntityId? _vaultId;
  final CurrencyCode? _reportingCurrency;

  Future<void> reload() async {
    if (_service == null || _vaultId == null || _reportingCurrency == null) {
      return;
    }
    state = WealthState(report: state.report, loading: true);
    try {
      state = WealthState(
        report: await _service.report(
          vaultId: _vaultId,
          currency: _reportingCurrency,
          asOf: _today(),
        ),
      );
    } catch (error) {
      state = WealthState(report: state.report, error: error);
    }
  }

  Future<void> create({
    required String name,
    required PhysicalAssetType type,
    required CurrencyCode currency,
    required String costText,
    required AssetValuationMethod method,
    required LocalDate acquiredOn,
    required String annualRateText,
    required String usefulLifeText,
    required String salvageText,
    required bool included,
    String? notes,
  }) => _mutate(() async {
    await _requiredService.createAsset(
      vaultId: _requiredVault,
      name: name,
      type: type,
      currency: currency,
      valuationMethod: method,
      acquiredOn: acquiredOn,
      acquisitionCostMinor: _minor(costText, currency),
      annualRate: annualRateText.trim().isEmpty
          ? null
          : (DecimalValue.parse(annualRateText.trim().replaceAll(',', '.')) /
                    Decimal.fromInt(100))
                .toDecimal(scaleOnInfinitePrecision: 12),
      usefulLifeMonths: usefulLifeText.trim().isEmpty
          ? null
          : int.parse(usefulLifeText),
      salvageValueMinor: salvageText.trim().isEmpty
          ? null
          : _minor(salvageText, currency),
      includeInNetWorth: included,
      notes: notes,
      now: UtcInstant.now(),
    );
  });

  Future<void> overrideValue(
    PhysicalAsset asset,
    String valueText,
    LocalDate date, {
    String? notes,
  }) => _mutate(
    () async => _requiredService.overrideValue(
      asset: asset,
      date: date,
      valueMinor: _minor(valueText, asset.currency),
      notes: notes,
    ),
  );

  Future<void> delete(PhysicalAsset asset) => _mutate(
    () async => _requiredService.deleteAsset(asset, UtcInstant.now()),
  );

  Future<void> _mutate(Future<void> Function() action) async {
    if (state.loading) return;
    state = WealthState(report: state.report, loading: true);
    try {
      await action();
      await reload();
    } catch (error) {
      state = WealthState(report: state.report, error: error);
    }
  }

  WealthService get _requiredService =>
      _service ?? (throw StateError('Wealth services are unavailable.'));
  EntityId get _requiredVault =>
      _vaultId ?? (throw StateError('A local vault is required.'));

  int _minor(String input, CurrencyCode currency) {
    var value = input.trim().replaceAll(RegExp(r'\s'), '');
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      value = comma > dot
          ? value.replaceAll('.', '').replaceAll(',', '.')
          : value.replaceAll(',', '');
    } else if (comma >= 0) {
      value = value.replaceAll(',', '.');
    }
    final decimal = DecimalValue.parse(value);
    if (decimal < Decimal.zero) {
      throw ArgumentError('Value must not be negative.');
    }
    return Money.fromMajor(
      currency: CurrencyDefinition(code: currency, minorUnits: 2),
      majorUnits: decimal,
    ).minorUnits;
  }
}

LocalDate _today() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}
