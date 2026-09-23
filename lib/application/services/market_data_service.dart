import 'package:decimal/decimal.dart';

import '../../domain/investments/investment_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
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
    MarketQuotePurpose purpose = MarketQuotePurpose.manualRefresh,
  }) async {
    final result = <MarketPriceState>[];
    final available = await instruments.listInstruments(vaultId);
    if (refresh) {
      try {
        await provider.heartbeat([
          for (final instrument in available)
            if (instrument.providerSymbol != null)
              _request(instrument, purpose: MarketQuotePurpose.portfolio),
        ]);
      } on Exception {
        // Heartbeat is best effort and never blocks local portfolio refresh.
      }
    }
    for (final instrument in available) {
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
      var refreshed = false;
      MarketRefreshFailureKind? failure;
      if (refresh) {
        try {
          final remote = await provider.quote(
            _request(instrument, purpose: purpose),
          );
          if (remote != null) {
            if (!remote.refreshFailed) await prices.saveAutomatic(remote);
            quote = remote;
            refreshed = !remote.refreshFailed;
            failed = remote.refreshFailed;
            failure = remote.refreshFailure;
          }
        } on Exception catch (error) {
          failed = true;
          failure = _failureKind(error);
        }
      }
      result.add(
        MarketPriceState(
          instrument: instrument,
          quote: quote,
          source: MarketPriceSource.automatic,
          stale:
              (quote?.stale ?? false) ||
              (quote?.isStaleAt(now, maximumAge: staleAfter) ?? false),
          refreshFailed: failed,
          refreshFailure: failure,
          refreshed: refreshed,
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

  Future<List<MarketInstrumentCandidate>> search({
    required String query,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    int limit = 10,
  }) => provider.search(
    query: query,
    assetClass: assetClass,
    currency: currency,
    limit: limit,
  );

  Future<MarketQuotePreview?> quoteCandidate(
    MarketInstrumentCandidate candidate,
  ) => provider.quoteCandidate(candidate);

  Future<void> savePreview(
    InvestmentInstrument instrument,
    MarketQuotePreview preview,
  ) {
    // A stale server fallback is useful to show a reference price, but saving it
    // as a fresh automatic quote would incorrectly advance the local cache.
    if (preview.stale || preview.refreshFailed) return Future.value();
    return prices.saveAutomatic(
      MarketQuote(
        instrumentId: instrument.id,
        price: preview.price,
        currency: preview.currency,
        timestamp: preview.timestamp,
        provider: preview.provider,
      ),
    );
  }

  MarketQuoteRequest _request(
    InvestmentInstrument value, {
    MarketQuotePurpose purpose = MarketQuotePurpose.manualRefresh,
  }) => MarketQuoteRequest(
    instrumentId: value.id,
    symbol: value.symbol ?? value.name,
    providerSymbol: value.providerSymbol,
    assetClass: value.assetClass,
    currency: value.currency,
    exchange: value.exchange,
    provider: _providerFor(value),
    purpose: purpose,
  );
  MarketProvider _providerFor(InvestmentInstrument value) {
    final persisted = value.providerName;
    if (persisted != null) {
      for (final provider in MarketProvider.values) {
        if (provider.name == persisted) return provider;
      }
    }
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

MarketRefreshFailureKind _failureKind(Object error) {
  if (error is MarketProviderUnavailable) {
    return switch (error.reason) {
      'unauthorized' => MarketRefreshFailureKind.unauthorized,
      'rate_limited' => MarketRefreshFailureKind.rateLimited,
      'invalid_response' => MarketRefreshFailureKind.invalidResponse,
      'network' => MarketRefreshFailureKind.network,
      _ => MarketRefreshFailureKind.providerUnavailable,
    };
  }
  if (error is FormatException) return MarketRefreshFailureKind.invalidResponse;
  return MarketRefreshFailureKind.network;
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
