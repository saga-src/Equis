import 'package:drift/native.dart';
import 'package:equis/application/ports/economic_series_ports.dart';
import 'package:equis/application/services/economic_series_service.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:equis/infrastructure/repositories/drift_economic_series_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TR validity overlap is retained and repeated cache writes are idempotent',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final cache = DriftEconomicSeriesCache(database);
      final tr = EconomicSeriesObservation(
        code: EconomicSeriesCode.trPeriod,
        referenceStart: LocalDate(2026, 9, 15),
        referenceEnd: LocalDate(2026, 10, 15),
        value: '0.1432',
        fetchedAt: UtcInstant.fromDateTime(DateTime.utc(2026, 9, 20)),
      );
      await cache.saveAll([tr]);
      await cache.saveAll([tr]);
      final corrected = EconomicSeriesObservation(
        code: EconomicSeriesCode.trPeriod,
        referenceStart: tr.referenceStart,
        referenceEnd: LocalDate(2026, 10, 20),
        value: '0.1433',
        fetchedAt: UtcInstant.fromDateTime(DateTime.utc(2026, 9, 21)),
      );
      await cache.saveAll([corrected]);
      await cache.saveAll([corrected]);
      await cache.saveAll([
        tr,
      ]); // An older response must not undo the correction.

      final values = await cache.read(
        code: EconomicSeriesCode.trPeriod,
        from: LocalDate(2026, 10, 1),
        through: LocalDate(2026, 10, 2),
      );
      expect(values, hasLength(1));
      expect(values.single.referenceStart, LocalDate(2026, 9, 15));
      expect(values.single.referenceEnd, LocalDate(2026, 10, 20));
      expect(values.single.value, '0.1433');
      final count = await database
          .customSelect('SELECT COUNT(*) AS count FROM economic_series_cache')
          .getSingle();
      expect(count.read<int>('count'), 1);
      expect(
        await cache.latestFetchedAt(EconomicSeriesCode.trPeriod),
        corrected.fetchedAt,
      );
      expect(
        await cache.latestReferenceEnd(EconomicSeriesCode.trPeriod),
        corrected.referenceEnd,
      );

      await database.customStatement(
        "INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) "
        "VALUES ('local-vault','Local','BRL','UTC',1,1)",
      );
      final snapshot = await VaultLogicalSnapshotStore(
        database,
      ).capture('local-vault');
      expect(snapshot.tables, isNot(contains('economic_series_cache')));
      expect(snapshot.tables, isNot(contains('economic_series_refresh_state')));
    },
  );

  test('disabled or failed remote read retains offline observations', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftEconomicSeriesCache(database);
    final stored = EconomicSeriesObservation(
      code: EconomicSeriesCode.cdiDaily,
      referenceStart: LocalDate(2026, 9, 21),
      referenceEnd: LocalDate(2026, 9, 21),
      value: '0.0551',
      fetchedAt: UtcInstant.fromDateTime(DateTime.utc(2026, 9, 22)),
    );
    await cache.saveAll([stored]);
    final provider = _FailingProvider();
    final from = LocalDate(2026, 9, 1);
    final through = LocalDate(2026, 9, 24);

    final disabled =
        await EconomicSeriesService(cache: cache, provider: provider).read(
          code: EconomicSeriesCode.cdiDaily,
          from: from,
          through: through,
          refresh: true,
        );
    expect(provider.calls, 0);
    expect(disabled.observations.single.value, '0.0551');
    expect(disabled.refreshFailed, isFalse);

    final failed =
        await EconomicSeriesService(
          cache: cache,
          provider: provider,
          remoteReadsEnabled: true,
        ).read(
          code: EconomicSeriesCode.cdiDaily,
          from: from,
          through: through,
          refresh: true,
        );
    expect(provider.calls, 1);
    expect(failed.observations.single.value, '0.0551');
    expect(failed.latestFetchedAt, stored.fetchedAt);
    expect(failed.latestReferenceEnd, stored.referenceEnd);
    expect(failed.refreshFailed, isTrue);
    expect(failed.refreshState?.lastErrorCode, 'offline');
    expect(failed.refreshState?.lastSuccessAt, isNull);
  });

  test('backfill splits requests into at most 366 inclusive days', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final provider = _WindowProvider();
    final service = EconomicSeriesService(
      cache: DriftEconomicSeriesCache(database),
      provider: provider,
      remoteReadsEnabled: true,
    );
    final result = await service.read(
      code: EconomicSeriesCode.ipcaMonthly,
      from: LocalDate(2024, 1, 1),
      through: LocalDate(2026, 1, 1),
      refresh: true,
    );
    expect(provider.windows, hasLength(2));
    for (final window in provider.windows) {
      expect(
        window.$2.toUtcDate().difference(window.$1.toUtcDate()).inDays,
        lessThanOrEqualTo(365),
      );
    }
    expect(provider.windows.first.$1, LocalDate(2024, 1, 1));
    expect(provider.windows.last.$2, LocalDate(2026, 1, 1));
    expect(result.observations, isEmpty);
    expect(result.refreshFailed, isFalse);
    expect(result.latestFetchedAt, isNull);
    expect(result.refreshState?.lastSuccessAt, isNotNull);
    expect(result.refreshState?.lastErrorCode, isNull);
  });

  test(
    'empty success is recorded and rapid reopening is throttled per code',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final provider = _WindowProvider();
      var now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 24, 9));
      final cache = DriftEconomicSeriesCache(database);
      final service = EconomicSeriesService(
        cache: cache,
        provider: provider,
        remoteReadsEnabled: true,
        clock: () => now,
      );

      expect(await cache.refreshState(EconomicSeriesCode.cdiDaily), isNull);
      await service.refreshOnOpen(now);
      expect(provider.windows, hasLength(6));
      final first = await cache.refreshState(EconomicSeriesCode.cdiDaily);
      expect(first?.lastAttemptAt, now);
      expect(first?.lastSuccessAt, now);
      expect(first?.lastErrorCode, isNull);
      expect(first?.requestedThrough, LocalDate(2026, 9, 24));
      expect(await cache.latestFetchedAt(EconomicSeriesCode.cdiDaily), isNull);

      now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 24, 10));
      await service.refreshOnOpen(now);
      expect(provider.windows, hasLength(6));

      // Explicit historical requests are never suppressed by the open gate.
      await service.read(
        code: EconomicSeriesCode.cdiDaily,
        from: LocalDate(2026, 9, 20),
        through: LocalDate(2026, 9, 24),
        refresh: true,
      );
      expect(provider.windows, hasLength(7));

      now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 24, 10, 5));
      provider.fail = true;
      final failed = await service.read(
        code: EconomicSeriesCode.cdiDaily,
        from: LocalDate(2026, 9, 20),
        through: LocalDate(2026, 9, 24),
        refresh: true,
      );
      expect(failed.refreshFailed, isTrue);
      expect(failed.refreshState?.lastAttemptAt, now);
      expect(
        failed.refreshState?.lastSuccessAt,
        UtcInstant.fromDateTime(DateTime.utc(2026, 9, 24, 10)),
      );
      expect(failed.refreshState?.lastErrorCode, 'offline');
      expect(provider.windows, hasLength(8));
      provider.fail = false;

      now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 24, 13, 6));
      await service.refreshOnOpen(now);
      expect(provider.windows, hasLength(14));
    },
  );
}

final class _FailingProvider implements EconomicSeriesProvider {
  int calls = 0;

  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async {
    calls++;
    throw const EconomicSeriesProviderUnavailable('offline');
  }
}

final class _WindowProvider implements EconomicSeriesProvider {
  final windows = <(LocalDate, LocalDate)>[];
  bool fail = false;

  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async {
    windows.add((from, through));
    if (fail) throw const EconomicSeriesProviderUnavailable('offline');
    return const [];
  }
}
