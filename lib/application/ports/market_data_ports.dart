import '../../domain/investments/investment_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class MarketDataProvider {
  Future<void> heartbeat(List<MarketQuoteRequest> assets);
  Future<List<MarketInstrumentCandidate>> search({
    required String query,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    int limit = 10,
  });
  Future<MarketQuotePreview?> quoteCandidate(
    MarketInstrumentCandidate candidate,
  );
  Future<MarketQuote?> quote(MarketQuoteRequest request);
  Future<List<MarketQuote>> history(
    MarketQuoteRequest request, {
    required LocalDate from,
    required LocalDate through,
  });
}

abstract interface class MarketPriceRepository {
  Future<void> saveAutomatic(MarketQuote quote);
  Future<void> saveManual(ManualMarketPrice price);
  Future<ManualMarketPrice?> latestManual(
    EntityId vaultId,
    EntityId instrumentId, {
    required LocalDate asOf,
  });
  Future<MarketQuote?> latestAutomatic(
    EntityId instrumentId, {
    LocalDate? asOf,
  });
  Future<UtcInstant?> latestAutomaticFetchedAt(EntityId instrumentId);
}

final class MarketProviderUnavailable implements Exception {
  const MarketProviderUnavailable(this.reason);
  final String reason;
}
