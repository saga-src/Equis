import 'package:decimal/decimal.dart';

import '../investments/investment_models.dart';
import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum MarketProvider { brapi, twelveData, coinGecko }

enum MarketPriceSource { manual, automatic }

final class MarketQuoteRequest {
  const MarketQuoteRequest({
    required this.instrumentId,
    required this.symbol,
    required this.assetClass,
    required this.currency,
    required this.provider,
    this.providerSymbol,
    this.exchange,
  });
  final EntityId instrumentId;
  final String symbol;
  final String? providerSymbol;
  final InvestmentAssetClass assetClass;
  final CurrencyCode currency;
  final String? exchange;
  final MarketProvider provider;
}

final class MarketQuote {
  MarketQuote({
    required this.instrumentId,
    required Decimal price,
    required this.currency,
    required this.timestamp,
    required this.provider,
  }) : price = DecimalValue.parse(DecimalValue.canonical(price)) {
    if (this.price <= Decimal.zero) throw ArgumentError.value(price, 'price');
  }
  final EntityId instrumentId;
  final Decimal price;
  final CurrencyCode currency;
  final UtcInstant timestamp;
  final String provider;
  bool isStaleAt(
    UtcInstant now, {
    Duration maximumAge = const Duration(hours: 24),
  }) =>
      now.epochMicroseconds - timestamp.epochMicroseconds >
      maximumAge.inMicroseconds;
}

final class ManualMarketPrice {
  ManualMarketPrice({
    required this.id,
    required this.vaultId,
    required this.instrumentId,
    required this.date,
    required Decimal price,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.revision = 1,
    this.deletedAt,
  }) : price = DecimalValue.parse(DecimalValue.canonical(price)) {
    if (this.price <= Decimal.zero) throw ArgumentError.value(price, 'price');
  }
  final EntityId id, vaultId, instrumentId;
  final LocalDate date;
  final Decimal price;
  final CurrencyCode currency;
  final String? notes;
  final int revision;
  final UtcInstant createdAt, updatedAt;
  final UtcInstant? deletedAt;
}

final class MarketPriceState {
  const MarketPriceState({
    required this.instrument,
    required this.quote,
    required this.source,
    required this.stale,
    required this.refreshFailed,
  });
  final InvestmentInstrument instrument;
  final MarketQuote? quote;
  final MarketPriceSource source;
  final bool stale, refreshFailed;
}
