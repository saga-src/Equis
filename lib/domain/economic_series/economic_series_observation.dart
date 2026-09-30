import 'package:decimal/decimal.dart';

import '../shared/local_date.dart';
import '../shared/utc_instant.dart';

enum EconomicSeriesCode {
  selicDaily(11, 'percent_per_day'),
  cdiDaily(12, 'percent_per_day'),
  inpcMonthly(188, 'percent_per_month'),
  igpmMonthly(189, 'percent_per_month'),
  trPeriod(226, 'percent_per_validity_period'),
  ipcaMonthly(433, 'percent_per_month');

  const EconomicSeriesCode(this.sgsCode, this.unit);

  final int sgsCode;
  final String unit;
}

final class EconomicSeriesObservation {
  EconomicSeriesObservation({
    required this.code,
    required this.referenceStart,
    required this.referenceEnd,
    required this.value,
    required this.fetchedAt,
    this.source = 'BCB_SGS',
  }) {
    if (referenceEnd.compareTo(referenceStart) < 0) {
      throw ArgumentError('Series validity interval is reversed.');
    }
    if (source != 'BCB_SGS') {
      throw ArgumentError.value(source, 'source', 'Unsupported series source.');
    }
    Decimal.parse(value);
  }

  final EconomicSeriesCode code;
  final LocalDate referenceStart;
  final LocalDate referenceEnd;

  /// The original percent value; conversion to an accrual factor belongs to
  /// the contract evaluator, which knows the series' period and formula.
  final String value;
  final String source;
  final UtcInstant fetchedAt;
  String get unit => code.unit;
}

final class EconomicSeriesRefreshState {
  const EconomicSeriesRefreshState({
    required this.code,
    required this.requestedFrom,
    required this.requestedThrough,
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.lastErrorCode,
  });

  final EconomicSeriesCode code;
  final LocalDate requestedFrom;
  final LocalDate requestedThrough;
  final UtcInstant lastAttemptAt;
  final UtcInstant? lastSuccessAt;
  final String? lastErrorCode;
}
