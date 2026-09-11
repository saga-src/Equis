import '../../domain/market/market_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class MarketDataProvider {
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
}
