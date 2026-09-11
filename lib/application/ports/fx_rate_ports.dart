import '../../domain/fx/fx_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class FxRateProvider {
  Future<FxRateQuote?> quote({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  });
}

abstract interface class ManualFxRateRepository {
  Future<void> save(ManualFxRate rate);
  Future<ManualFxRate?> findForDate({
    required EntityId vaultId,
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  });
}

abstract interface class FxRateCacheRepository {
  Future<void> save(FxRateQuote quote);
  Future<FxRateQuote?> findExact({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  });
  Future<FxRateQuote?> findPrevious({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  });
  Future<FxRateQuote?> findLatest({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate requestedDate,
  });
}
