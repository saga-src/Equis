import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';

abstract interface class EconomicSeriesProvider {
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  });
}

abstract interface class EconomicSeriesCache {
  Future<void> saveAll(List<EconomicSeriesObservation> observations);
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  });
  Future<UtcInstant?> latestFetchedAt(EconomicSeriesCode code);
  Future<LocalDate?> latestReferenceEnd(EconomicSeriesCode code);
  Future<EconomicSeriesRefreshState?> refreshState(EconomicSeriesCode code);
  Future<void> recordRefresh({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
    required UtcInstant attemptedAt,
    String? errorCode,
  });
}

final class EconomicSeriesProviderUnavailable implements Exception {
  const EconomicSeriesProviderUnavailable(this.reason);
  final String reason;
}
