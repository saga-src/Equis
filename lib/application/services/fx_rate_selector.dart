import '../ports/fx_rate_ports.dart';
import '../../domain/fx/fx_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

final class FxRateSelector {
  const FxRateSelector({
    required this.manualRates,
    required this.cache,
    required this.provider,
  });

  final ManualFxRateRepository manualRates;
  final FxRateCacheRepository cache;
  final FxRateProvider provider;

  Future<FxRateQuote?> select({
    required EntityId vaultId,
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
    String? transactionManualRate,
  }) async {
    if (base == quote) {
      return FxRateQuote(
        base: base,
        quote: quote,
        requestedDate: date,
        rateDate: date,
        rate: '1',
        source: FxRateSource.identity,
        provider: 'identity',
      );
    }
    if (transactionManualRate != null) {
      return FxRateQuote(
        base: base,
        quote: quote,
        requestedDate: date,
        rateDate: date,
        rate: transactionManualRate,
        source: FxRateSource.transactionManual,
        provider: 'user',
      );
    }
    final manual = await manualRates.findForDate(
      vaultId: vaultId,
      base: base,
      quote: quote,
      date: date,
    );
    if (manual != null) {
      return FxRateQuote(
        base: base,
        quote: quote,
        requestedDate: date,
        rateDate: manual.date,
        rate: manual.rate,
        source: FxRateSource.datePairManual,
        provider: 'user',
      );
    }
    final exact = await cache.findExact(base: base, quote: quote, date: date);
    if (exact != null) return exact;

    try {
      final remote = await provider.quote(base: base, quote: quote, date: date);
      if (remote != null) {
        await cache.save(remote);
        return remote;
      }
    } on Exception {
      // Offline operation intentionally falls through to durable local cache.
    }

    final previous = await cache.findPrevious(
      base: base,
      quote: quote,
      date: date,
    );
    if (previous != null) return previous;
    return cache.findLatest(base: base, quote: quote, requestedDate: date);
  }
}
