import 'package:drift/drift.dart';

import '../../application/ports/fx_rate_ports.dart';
import '../../domain/fx/fx_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart' hide ManualFxRate;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftManualFxRateRepository implements ManualFxRateRepository {
  const DriftManualFxRateRepository(this.database, {this.syncRecorder});
  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(ManualFxRate rate) =>
      syncRecorder?.run(
        vaultId: rate.vaultId.value,
        entityType: SyncEntityType.manualFxRate,
        recordId: rate.id.value,
        newRevision: rate.revision,
        operation: rate.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(rate),
      ) ??
      _save(rate);

  Future<void> _save(ManualFxRate rate) => database
      .into(database.manualFxRates)
      .insertOnConflictUpdate(
        ManualFxRatesCompanion.insert(
          id: Value(rate.id.value),
          vaultId: rate.vaultId.value,
          baseCurrency: rate.base.value,
          quoteCurrency: rate.quote.value,
          rateDate: rate.date.toString(),
          rate: rate.rate,
          notes: Value(rate.notes),
          revision: Value(rate.revision),
          createdAt: rate.createdAt.epochMicroseconds,
          updatedAt: rate.updatedAt.epochMicroseconds,
          deletedAt: Value(rate.deletedAt?.epochMicroseconds),
        ),
      );

  @override
  Future<ManualFxRate?> findForDate({
    required EntityId vaultId,
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) async {
    final query = database.select(database.manualFxRates)
      ..where(
        (row) =>
            row.vaultId.equals(vaultId.value) &
            row.baseCurrency.equals(base.value) &
            row.quoteCurrency.equals(quote.value) &
            row.rateDate.equals(date.toString()) &
            row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : ManualFxRate(
            id: EntityId.parse(row.id!),
            vaultId: EntityId.parse(row.vaultId),
            base: CurrencyCode(row.baseCurrency),
            quote: CurrencyCode(row.quoteCurrency),
            date: LocalDate.parse(row.rateDate),
            rate: row.rate,
            notes: row.notes,
            revision: row.revision,
            createdAt: UtcInstant.fromEpochMicroseconds(row.createdAt),
            updatedAt: UtcInstant.fromEpochMicroseconds(row.updatedAt),
            deletedAt: row.deletedAt == null
                ? null
                : UtcInstant.fromEpochMicroseconds(row.deletedAt!),
          );
  }
}

final class DriftFxRateCacheRepository implements FxRateCacheRepository {
  DriftFxRateCacheRepository(this.database, {UtcInstant Function()? clock})
    : _clock = clock ?? UtcInstant.now;

  final EquisDatabase database;
  final UtcInstant Function() _clock;

  @override
  Future<void> save(FxRateQuote quote) => database
      .into(database.fxRateCache)
      .insertOnConflictUpdate(
        FxRateCacheCompanion.insert(
          baseCurrency: quote.base.value,
          quoteCurrency: quote.quote.value,
          rateDate: quote.rateDate.toString(),
          rate: quote.rate,
          provider: quote.provider,
          fetchedAt: _clock().epochMicroseconds,
        ),
      );

  @override
  Future<FxRateQuote?> findExact({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) => _find(
    base: base,
    quote: quote,
    requestedDate: date,
    where: 'rate_date = ?',
    whereValues: [date.toString()],
    source: FxRateSource.automaticExact,
  );

  @override
  Future<FxRateQuote?> findPrevious({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) => _find(
    base: base,
    quote: quote,
    requestedDate: date,
    where: 'rate_date < ?',
    whereValues: [date.toString()],
    source: FxRateSource.previousMarketDay,
  );

  @override
  Future<FxRateQuote?> findLatest({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate requestedDate,
  }) => _find(
    base: base,
    quote: quote,
    requestedDate: requestedDate,
    where: '1 = 1',
    whereValues: const [],
    source: FxRateSource.latestCached,
  );

  Future<FxRateQuote?> _find({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate requestedDate,
    required String where,
    required List<String> whereValues,
    required FxRateSource source,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT base_currency, quote_currency, rate_date, rate, provider '
          'FROM fx_rate_cache WHERE base_currency = ? AND quote_currency = ? '
          'AND $where ORDER BY rate_date DESC, fetched_at DESC LIMIT 1',
          variables: [
            Variable<String>(base.value),
            Variable<String>(quote.value),
            ...whereValues.map(Variable<String>.new),
          ],
          readsFrom: {database.fxRateCache},
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return FxRateQuote(
      base: CurrencyCode(row.read<String>('base_currency')),
      quote: CurrencyCode(row.read<String>('quote_currency')),
      requestedDate: requestedDate,
      rateDate: LocalDate.parse(row.read<String>('rate_date')),
      rate: row.read<String>('rate'),
      source: source,
      provider: row.read<String>('provider'),
    );
  }
}
