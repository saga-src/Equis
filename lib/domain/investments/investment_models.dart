import 'package:decimal/decimal.dart';

import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum InvestmentAssetClass {
  stock,
  etf,
  fund,
  reit,
  fii,
  bond,
  fixedIncome('fixed_income'),
  crypto,
  commodity,
  cashEquivalent('cash_equivalent'),
  other;

  const InvestmentAssetClass([String? storageValue])
    : storageValue = storageValue ?? '';
  final String storageValue;
  String get stored => storageValue.isEmpty ? name : storageValue;
  static InvestmentAssetClass fromStorage(String value) =>
      values.singleWhere((item) => item.stored == value);
}

final class InvestmentInstrument {
  InvestmentInstrument({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.assetClass,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
    this.symbol,
    this.exchange,
    this.isin,
    this.providerSymbol,
    this.providerName,
    this.customInstrument = false,
    this.revision = 1,
    this.deletedAt,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }
  final EntityId id;
  final EntityId vaultId;
  final String? symbol;
  final String name;
  final InvestmentAssetClass assetClass;
  final String? exchange;
  final CurrencyCode currency;
  final String? isin;
  final String? providerSymbol;
  final String? providerName;
  final bool customInstrument;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  InvestmentInstrument revise({
    String? symbol,
    String? name,
    InvestmentAssetClass? assetClass,
    String? exchange,
    String? isin,
    String? providerSymbol,
    String? providerName,
    bool? customInstrument,
    UtcInstant? deletedAt,
    required UtcInstant at,
  }) => InvestmentInstrument(
    id: id,
    vaultId: vaultId,
    symbol: symbol ?? this.symbol,
    name: name ?? this.name,
    assetClass: assetClass ?? this.assetClass,
    exchange: exchange ?? this.exchange,
    currency: currency,
    isin: isin ?? this.isin,
    providerSymbol: providerSymbol ?? this.providerSymbol,
    providerName: providerName ?? this.providerName,
    customInstrument: customInstrument ?? this.customInstrument,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

final class InvestmentLot {
  InvestmentLot({
    required this.id,
    required this.acquisitionEventId,
    required this.instrumentId,
    required this.acquiredOn,
    required Decimal originalQuantity,
    required this.costBasisMinor,
    required this.costCurrency,
  }) : originalQuantity = _positive(originalQuantity, 'originalQuantity') {
    if (costBasisMinor < 0) {
      throw RangeError.value(costBasisMinor, 'costBasisMinor');
    }
  }
  final EntityId id;
  final EntityId acquisitionEventId;
  final EntityId instrumentId;
  final LocalDate acquiredOn;
  final Decimal originalQuantity;
  final int costBasisMinor;
  final CurrencyCode costCurrency;
}

final class LotDisposal {
  LotDisposal({
    required this.id,
    required this.disposalEventId,
    required this.lotId,
    required Decimal quantity,
    required this.allocatedCostMinor,
  }) : quantity = _positive(quantity, 'quantity') {
    if (allocatedCostMinor < 0) {
      throw RangeError.value(allocatedCostMinor, 'allocatedCostMinor');
    }
  }
  final EntityId id;
  final EntityId disposalEventId;
  final EntityId lotId;
  final Decimal quantity;
  final int allocatedCostMinor;
}

final class LotPosition {
  LotPosition({
    required this.lot,
    required this.disposedQuantity,
    required this.allocatedCostMinor,
  }) {
    if (disposedQuantity < Decimal.zero ||
        disposedQuantity > lot.originalQuantity) {
      throw StateError(
        'Disposed quantity is inconsistent with the immutable lot.',
      );
    }
    if (allocatedCostMinor < 0 || allocatedCostMinor > lot.costBasisMinor) {
      throw StateError(
        'Allocated cost is inconsistent with the immutable lot.',
      );
    }
  }
  final InvestmentLot lot;
  final Decimal disposedQuantity;
  final int allocatedCostMinor;
  Decimal get remainingQuantity => lot.originalQuantity - disposedQuantity;
  int get remainingCostMinor => lot.costBasisMinor - allocatedCostMinor;
}

final class InvestmentPrice {
  const InvestmentPrice({
    required this.price,
    required this.currency,
    required this.date,
    required this.manual,
  });
  final Decimal price;
  final CurrencyCode currency;
  final LocalDate date;
  final bool manual;
}

final class InvestmentPerformanceSource {
  const InvestmentPerformanceSource({
    required this.realizedMinor,
    required this.incomeMinor,
  });
  final int realizedMinor;
  final int incomeMinor;
}

final class HoldingReport {
  const HoldingReport({
    required this.instrument,
    required this.quantity,
    required this.costBasisMinor,
    required this.averageCost,
    required this.realizedMinor,
    required this.incomeMinor,
    required this.marketValueMinor,
    required this.unrealizedMinor,
    required this.allocationBps,
    required this.price,
    required this.lots,
    this.reportingMarketValueMinor,
    this.missingFx = false,
    this.estimatedFx = false,
  });
  final InvestmentInstrument instrument;
  final Decimal quantity;
  final int costBasisMinor;
  final Decimal averageCost;
  final int? marketValueMinor;
  final int? reportingMarketValueMinor;
  final int? unrealizedMinor;
  final int realizedMinor;
  final int incomeMinor;
  final int allocationBps;
  final InvestmentPrice? price;
  final List<LotPosition> lots;
  final bool missingFx;
  final bool estimatedFx;
}

final class PortfolioReport {
  PortfolioReport({
    required this.currency,
    required List<HoldingReport> holdings,
    required this.marketValueMinor,
    required this.costBasisMinor,
    required this.unrealizedMinor,
    required this.realizedMinor,
    required this.incomeMinor,
  }) : holdings = List.unmodifiable(holdings);
  final CurrencyCode currency;
  final List<HoldingReport> holdings;
  final int marketValueMinor;
  final int costBasisMinor;
  final int unrealizedMinor;
  final int realizedMinor;
  final int incomeMinor;
}

Decimal _positive(Decimal value, String name) {
  if (value <= Decimal.zero) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return DecimalValue.parse(DecimalValue.canonical(value));
}
