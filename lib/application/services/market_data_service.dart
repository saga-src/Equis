import 'package:decimal/decimal.dart';

import '../../domain/investments/investment_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../ports/investment_repository.dart';
import '../ports/market_data_ports.dart';

final class MarketDataService {
  const MarketDataService({
    required this.instruments,
    required this.prices,
    required this.provider,
    this.staleAfter = const Duration(hours: 24),
  });
  final InvestmentRepository instruments;
  final MarketPriceRepository prices;
  final MarketDataProvider provider;
  final Duration staleAfter;

  Future<List<MarketPriceState>> load({
    required EntityId vaultId,
    required LocalDate asOf,
    required UtcInstant now,
    bool refresh = false,
  }) async {
    final result = <MarketPriceState>[];
    for (final instrument in await instruments.listInstruments(vaultId)) {
      final manual = await prices.latestManual(
        vaultId,
        instrument.id,
        asOf: asOf,
      );
      if (manual != null) {
        result.add(
          MarketPriceState(
            instrument: instrument,
            quote: MarketQuote(
              instrumentId: instrument.id,
              price: manual.price,
              currency: manual.currency,
              timestamp: _endOfDay(manual.date),
              provider: 'user',
            ),
            source: MarketPriceSource.manual,
            stale: false,
            refreshFailed: false,
          ),
        );
        continue;
      }
      var quote = await prices.latestAutomatic(instrument.id, asOf: asOf);
      var failed = false;
      if (refresh) {
        try {
          final remote = await provider.quote(_request(instrument));
          if (remote != null) {
            await prices.saveAutomatic(remote);
            quote = remote;
          }
        } on Exception {
          failed = true;
        }
      }
      result.add(
        MarketPriceState(
          instrument: instrument,
          quote: quote,
          source: MarketPriceSource.automatic,
          stale: quote?.isStaleAt(now, maximumAge: staleAfter) ?? false,
          refreshFailed: failed,
        ),
      );
    }
    return result;
  }

  Future<ManualMarketPrice> override({
    required EntityId vaultId,
    required InvestmentInstrument instrument,
    required LocalDate date,
    required Decimal price,
    required UtcInstant now,
    String? notes,
  }) async {
    final value = ManualMarketPrice(
      id: EntityId.generate(),
      vaultId: vaultId,
      instrumentId: instrument.id,
      date: date,
      price: price,
      currency: instrument.currency,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await prices.saveManual(value);
    return value;
  }

  MarketQuoteRequest _request(InvestmentInstrument value) => MarketQuoteRequest(
    instrumentId: value.id,
    symbol: value.symbol ?? value.name,
    providerSymbol: value.providerSymbol,
    assetClass: value.assetClass,
    currency: value.currency,
    exchange: value.exchange,
    provider: _providerFor(value),
  );
  MarketProvider _providerFor(InvestmentInstrument value) {
    if (value.assetClass == InvestmentAssetClass.crypto) {
      return MarketProvider.coinGecko;
    }
    if (value.exchange?.toUpperCase() == 'B3' ||
        value.assetClass == InvestmentAssetClass.fii) {
      return MarketProvider.brapi;
    }
    return MarketProvider.twelveData;
  }
}

UtcInstant _endOfDay(LocalDate value) => UtcInstant.fromEpochMicroseconds(
  DateTime.utc(
    value.year,
    value.month,
    value.day,
    23,
    59,
    59,
    999,
    999,
  ).microsecondsSinceEpoch,
);
