import 'package:drift/drift.dart';

import '../../application/ports/economic_series_ports.dart';
import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../persistence/database/equis_database.dart'
    hide EconomicSeriesCache, EconomicSeriesRefreshState;

final class DriftEconomicSeriesCache implements EconomicSeriesCache {
  const DriftEconomicSeriesCache(this.database);

  final EquisDatabase database;

  @override
  Future<void> saveAll(
    List<EconomicSeriesObservation> observations,
  ) => database.transaction(() async {
    for (final observation in observations) {
      await database.customStatement(
        'INSERT INTO economic_series_cache '
        '(code, reference_start, reference_end, value, unit, source, fetched_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(code, reference_start) DO UPDATE SET '
        'reference_end = excluded.reference_end, '
        'value = excluded.value, unit = excluded.unit, '
        'source = excluded.source, fetched_at = excluded.fetched_at '
        'WHERE excluded.fetched_at >= economic_series_cache.fetched_at',
        [
          observation.code.sgsCode,
          observation.referenceStart.toString(),
          observation.referenceEnd.toString(),
          observation.value,
          observation.unit,
          observation.source,
          observation.fetchedAt.epochMicroseconds,
        ],
      );
    }
  });

  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT reference_start, reference_end, value, unit, source, fetched_at '
          'FROM economic_series_cache '
          'WHERE code = ? AND reference_start <= ? AND reference_end >= ? '
          'ORDER BY reference_start, reference_end',
          variables: [
            Variable<int>(code.sgsCode),
            Variable<String>(through.toString()),
            Variable<String>(from.toString()),
          ],
        )
        .get();
    if (rows.any((row) => row.read<String>('unit') != code.unit)) {
      throw StateError('Cached economic series unit does not match its code.');
    }
    return [
      for (final row in rows)
        EconomicSeriesObservation(
          code: code,
          referenceStart: LocalDate.parse(row.read<String>('reference_start')),
          referenceEnd: LocalDate.parse(row.read<String>('reference_end')),
          value: row.read<String>('value'),
          source: row.read<String>('source'),
          fetchedAt: UtcInstant.fromEpochMicroseconds(
            row.read<int>('fetched_at'),
          ),
        ),
    ];
  }

  @override
  Future<UtcInstant?> latestFetchedAt(EconomicSeriesCode code) async {
    final row = await database
        .customSelect(
          'SELECT MAX(fetched_at) AS latest FROM economic_series_cache WHERE code = ?',
          variables: [Variable<int>(code.sgsCode)],
        )
        .getSingle();
    final micros = row.readNullable<int>('latest');
    return micros == null ? null : UtcInstant.fromEpochMicroseconds(micros);
  }

  @override
  Future<LocalDate?> latestReferenceEnd(EconomicSeriesCode code) async {
    final row = await database
        .customSelect(
          'SELECT MAX(reference_end) AS latest FROM economic_series_cache WHERE code = ?',
          variables: [Variable<int>(code.sgsCode)],
        )
        .getSingle();
    final date = row.readNullable<String>('latest');
    return date == null ? null : LocalDate.parse(date);
  }

  @override
  Future<EconomicSeriesRefreshState?> refreshState(
    EconomicSeriesCode code,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT requested_from, requested_through, last_attempt_at, '
          'last_success_at, last_error_code '
          'FROM economic_series_refresh_state WHERE code = ?',
          variables: [Variable<int>(code.sgsCode)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    final successMicros = row.readNullable<int>('last_success_at');
    return EconomicSeriesRefreshState(
      code: code,
      requestedFrom: LocalDate.parse(row.read<String>('requested_from')),
      requestedThrough: LocalDate.parse(row.read<String>('requested_through')),
      lastAttemptAt: UtcInstant.fromEpochMicroseconds(
        row.read<int>('last_attempt_at'),
      ),
      lastSuccessAt: successMicros == null
          ? null
          : UtcInstant.fromEpochMicroseconds(successMicros),
      lastErrorCode: row.readNullable<String>('last_error_code'),
    );
  }

  @override
  Future<void> recordRefresh({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
    required UtcInstant attemptedAt,
    String? errorCode,
  }) => database.customStatement(
    'INSERT INTO economic_series_refresh_state '
    '(code, requested_from, requested_through, last_attempt_at, '
    'last_success_at, last_error_code) VALUES (?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(code) DO UPDATE SET '
    'requested_from = excluded.requested_from, '
    'requested_through = excluded.requested_through, '
    'last_attempt_at = excluded.last_attempt_at, '
    'last_success_at = CASE WHEN excluded.last_error_code IS NULL '
    'THEN excluded.last_success_at '
    'ELSE economic_series_refresh_state.last_success_at END, '
    'last_error_code = excluded.last_error_code '
    'WHERE excluded.last_attempt_at >= economic_series_refresh_state.last_attempt_at',
    [
      code.sgsCode,
      from.toString(),
      through.toString(),
      attemptedAt.epochMicroseconds,
      if (errorCode == null) attemptedAt.epochMicroseconds else null,
      errorCode,
    ],
  );
}
