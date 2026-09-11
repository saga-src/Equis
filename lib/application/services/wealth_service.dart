import 'package:decimal/decimal.dart';

import '../../domain/entities/account_profile.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/wealth/asset_models.dart';
import '../../domain/wealth/net_worth_models.dart';
import '../ports/dashboard_repository.dart';
import '../ports/wealth_repository.dart';
import 'investment_service.dart';

final class WealthService {
  const WealthService({
    required this.repository,
    required this.reporting,
    this.investments,
  });
  final WealthRepository repository;
  final DashboardRepository reporting;
  final InvestmentService? investments;

  Future<PhysicalAsset> createAsset({
    required EntityId vaultId,
    required String name,
    required PhysicalAssetType type,
    required CurrencyCode currency,
    required AssetValuationMethod valuationMethod,
    required UtcInstant now,
    LocalDate? acquiredOn,
    int? acquisitionCostMinor,
    Decimal? annualRate,
    int? usefulLifeMonths,
    int? salvageValueMinor,
    bool includeInNetWorth = true,
    String? notes,
  }) async {
    final asset = PhysicalAsset(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: name.trim(),
      type: type,
      currency: currency,
      acquiredOn: acquiredOn,
      acquisitionCostMinor: acquisitionCostMinor,
      valuationMethod: valuationMethod,
      annualRate: annualRate,
      usefulLifeMonths: usefulLifeMonths,
      salvageValueMinor: salvageValueMinor,
      includeInNetWorth: includeInNetWorth,
      notes: _optional(notes),
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveAsset(asset);
    return asset;
  }

  Future<void> deleteAsset(PhysicalAsset asset, UtcInstant now) =>
      repository.saveAsset(asset.revise(deletedAt: now, at: now));

  Future<AssetValuation> overrideValue({
    required PhysicalAsset asset,
    required LocalDate date,
    required int valueMinor,
    String? notes,
  }) async {
    final valuation = AssetValuation(
      id: EntityId.generate(),
      assetId: asset.id,
      date: date,
      valueMinor: valueMinor,
      source: AssetValuationSource.manual,
      notes: _optional(notes),
    );
    await repository.addValuation(valuation);
    return valuation;
  }

  Future<AssetValue?> valueAt(PhysicalAsset asset, LocalDate asOf) async {
    final history = await repository.valuations(asset.id, through: asOf);
    if (history.isNotEmpty) {
      final valuation = history.last;
      return AssetValue(
        asset: asset,
        valueMinor: valuation.valueMinor,
        asOf: asOf,
        source: valuation.source,
      );
    }
    final value = modelAssetValue(asset, asOf);
    return value == null
        ? null
        : AssetValue(
            asset: asset,
            valueMinor: value,
            asOf: asOf,
            source: asset.valuationMethod == AssetValuationMethod.manual
                ? AssetValuationSource.manual
                : AssetValuationSource.calculated,
          );
  }

  Future<NetWorthReport> report({
    required EntityId vaultId,
    required CurrencyCode currency,
    required LocalDate asOf,
    int historyMonths = 12,
  }) async {
    final assets = await repository.listAssets(vaultId);
    final dates = <LocalDate>[];
    for (var offset = historyMonths - 1; offset >= 1; offset--) {
      final monthIndex = asOf.year * 12 + asOf.month - 1 - offset;
      final year = monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;
      dates.add(LocalDate(year, month, DateTime.utc(year, month + 1, 0).day));
    }
    dates.add(asOf);
    final points = <NetWorthPoint>[];
    List<AssetValue> currentAssets = const [];
    for (final date in dates) {
      reporting.beginRead();
      final result = await _point(vaultId, currency, date, assets);
      points.add(result.$1);
      if (date == asOf) currentAssets = result.$2;
    }
    return NetWorthReport(
      currency: currency,
      current: points.last,
      history: points,
      physicalAssets: currentAssets,
    );
  }

  Future<(NetWorthPoint, List<AssetValue>)> _point(
    EntityId vaultId,
    CurrencyCode currency,
    LocalDate date,
    List<PhysicalAsset> assets,
  ) async {
    var assetTotal = 0;
    var liabilityTotal = 0;
    var estimated = false;
    final missing = <CurrencyCode>{};
    for (final row in await repository.accountBalances(vaultId, date)) {
      final converted = await reporting.convertMinor(
        vaultId: vaultId,
        source: row.currency,
        target: currency,
        date: date,
        amountMinor: row.balanceMinor,
      );
      if (converted == null) {
        missing.add(row.currency);
        continue;
      }
      estimated |= converted.estimated;
      if (row.nature == AccountNature.asset) {
        assetTotal += converted.minorUnits;
      } else {
        liabilityTotal += converted.minorUnits;
      }
    }
    final investmentReport = await investments?.report(
      vaultId: vaultId,
      currency: currency,
      asOf: date,
    );
    if (investmentReport != null) {
      assetTotal += investmentReport.marketValueMinor;
    }
    final values = <AssetValue>[];
    for (final asset in assets.where((item) => _activeAssetAt(item, date))) {
      final value = await valueAt(asset, date);
      if (value == null) continue;
      if (!asset.includeInNetWorth) {
        values.add(value);
        continue;
      }
      final converted = await reporting.convertMinor(
        vaultId: vaultId,
        source: asset.currency,
        target: currency,
        date: date,
        amountMinor: value.valueMinor,
      );
      if (converted == null) {
        missing.add(asset.currency);
        values.add(value);
        continue;
      }
      estimated |= converted.estimated;
      assetTotal += converted.minorUnits;
      values.add(
        AssetValue(
          asset: asset,
          valueMinor: value.valueMinor,
          reportingMinor: converted.minorUnits,
          asOf: date,
          source: value.source,
          estimatedFx: converted.estimated,
        ),
      );
    }
    return (
      NetWorthPoint(
        date: date,
        assetsMinor: assetTotal,
        liabilitiesMinor: liabilityTotal,
        missingRates: missing,
        usesEstimatedRates: estimated,
      ),
      values,
    );
  }
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

bool _activeAssetAt(PhysicalAsset asset, LocalDate date) {
  final deleted = asset.deletedAt;
  if (deleted == null) return true;
  final instant = DateTime.fromMicrosecondsSinceEpoch(
    deleted.epochMicroseconds,
    isUtc: true,
  );
  return date.compareTo(LocalDate(instant.year, instant.month, instant.day)) <
      0;
}
