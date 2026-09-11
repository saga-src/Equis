import 'package:decimal/decimal.dart';

import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum PhysicalAssetType {
  property,
  vehicle,
  collectible,
  equipment,
  valuablePossession('valuable_possession'),
  other;

  const PhysicalAssetType([String? storageValue])
    : storageValue = storageValue ?? '';
  final String storageValue;
  String get stored => storageValue.isEmpty ? name : storageValue;
  static PhysicalAssetType fromStorage(String value) => values.firstWhere(
    (item) => item.stored == value,
    orElse: () => PhysicalAssetType.other,
  );
}

enum AssetValuationMethod {
  manual,
  straightLine('straight_line'),
  percentageDepreciation('percentage_depreciation'),
  percentageAppreciation('percentage_appreciation'),
  custom;

  const AssetValuationMethod([String? storageValue])
    : storageValue = storageValue ?? '';
  final String storageValue;
  String get stored => storageValue.isEmpty ? name : storageValue;
  static AssetValuationMethod fromStorage(String value) =>
      values.singleWhere((item) => item.stored == value);
}

enum AssetValuationSource { manual, calculated, external }

final class PhysicalAsset {
  PhysicalAsset({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.type,
    required this.currency,
    required this.valuationMethod,
    required this.createdAt,
    required this.updatedAt,
    this.acquiredOn,
    this.acquisitionCostMinor,
    this.annualRate,
    this.usefulLifeMonths,
    this.salvageValueMinor,
    this.includeInNetWorth = true,
    this.notes,
    this.revision = 1,
    this.deletedAt,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (acquisitionCostMinor != null && acquisitionCostMinor! < 0) {
      throw RangeError.value(acquisitionCostMinor!, 'acquisitionCostMinor');
    }
    if (salvageValueMinor != null && salvageValueMinor! < 0) {
      throw RangeError.value(salvageValueMinor!, 'salvageValueMinor');
    }
    if (usefulLifeMonths != null && usefulLifeMonths! <= 0) {
      throw RangeError.value(usefulLifeMonths!, 'usefulLifeMonths');
    }
    if (annualRate != null && annualRate! < Decimal.zero) {
      throw ArgumentError.value(
        annualRate,
        'annualRate',
        'must not be negative',
      );
    }
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final PhysicalAssetType type;
  final CurrencyCode currency;
  final LocalDate? acquiredOn;
  final int? acquisitionCostMinor;
  final AssetValuationMethod valuationMethod;
  final Decimal? annualRate;
  final int? usefulLifeMonths;
  final int? salvageValueMinor;
  final bool includeInNetWorth;
  final String? notes;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  PhysicalAsset revise({
    String? name,
    PhysicalAssetType? type,
    LocalDate? acquiredOn,
    int? acquisitionCostMinor,
    AssetValuationMethod? valuationMethod,
    Decimal? annualRate,
    int? usefulLifeMonths,
    int? salvageValueMinor,
    bool? includeInNetWorth,
    String? notes,
    UtcInstant? deletedAt,
    required UtcInstant at,
  }) => PhysicalAsset(
    id: id,
    vaultId: vaultId,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency,
    acquiredOn: acquiredOn ?? this.acquiredOn,
    acquisitionCostMinor: acquisitionCostMinor ?? this.acquisitionCostMinor,
    valuationMethod: valuationMethod ?? this.valuationMethod,
    annualRate: annualRate ?? this.annualRate,
    usefulLifeMonths: usefulLifeMonths ?? this.usefulLifeMonths,
    salvageValueMinor: salvageValueMinor ?? this.salvageValueMinor,
    includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
    notes: notes ?? this.notes,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

final class AssetValuation {
  AssetValuation({
    required this.id,
    required this.assetId,
    required this.date,
    required this.valueMinor,
    required this.source,
    this.notes,
  }) {
    if (valueMinor < 0) throw RangeError.value(valueMinor, 'valueMinor');
  }
  final EntityId id;
  final EntityId assetId;
  final LocalDate date;
  final int valueMinor;
  final AssetValuationSource source;
  final String? notes;
}

final class AssetValue {
  const AssetValue({
    required this.asset,
    required this.valueMinor,
    required this.asOf,
    required this.source,
    this.reportingMinor,
    this.estimatedFx = false,
  });
  final PhysicalAsset asset;
  final int valueMinor;
  final int? reportingMinor;
  final LocalDate asOf;
  final AssetValuationSource source;
  final bool estimatedFx;
}

int? modelAssetValue(PhysicalAsset asset, LocalDate asOf) {
  final cost = asset.acquisitionCostMinor;
  final acquired = asset.acquiredOn;
  if (cost == null || acquired == null || asOf.compareTo(acquired) < 0) {
    return null;
  }
  final months = completedMonths(acquired, asOf);
  return switch (asset.valuationMethod) {
    AssetValuationMethod.manual || AssetValuationMethod.custom => cost,
    AssetValuationMethod.straightLine => _straightLine(asset, cost, months),
    AssetValuationMethod.percentageDepreciation => _percentage(
      cost,
      asset.annualRate,
      months,
      appreciate: false,
    ),
    AssetValuationMethod.percentageAppreciation => _percentage(
      cost,
      asset.annualRate,
      months,
      appreciate: true,
    ),
  };
}

int completedMonths(LocalDate from, LocalDate through) {
  var months = (through.year - from.year) * 12 + through.month - from.month;
  if (through.day < from.day) months--;
  return months < 0 ? 0 : months;
}

int _straightLine(PhysicalAsset asset, int cost, int elapsed) {
  final life = asset.usefulLifeMonths;
  if (life == null) return cost;
  final salvage = asset.salvageValueMinor ?? 0;
  final base = cost > salvage ? cost - salvage : 0;
  final used = elapsed > life ? life : elapsed;
  final depreciation =
      (BigInt.from(base) * BigInt.from(used)) ~/ BigInt.from(life);
  final value = cost - depreciation.toInt();
  return value < salvage ? salvage : value;
}

int _percentage(
  int cost,
  Decimal? annualRate,
  int months, {
  required bool appreciate,
}) {
  if (annualRate == null || months == 0) return cost;
  final monthly = (annualRate / Decimal.fromInt(12)).toDecimal(
    scaleOnInfinitePrecision: 24,
  );
  var value = Decimal.fromInt(cost);
  final factor = appreciate ? Decimal.one + monthly : Decimal.one - monthly;
  if (factor <= Decimal.zero) return appreciate ? cost : 0;
  for (var index = 0; index < months; index++) {
    value = value * factor;
  }
  final rounded = DecimalValue.round(value, scale: 0).toBigInt();
  return rounded < BigInt.zero ? 0 : rounded.toInt();
}
