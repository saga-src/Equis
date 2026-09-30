import 'dart:async';

import 'package:equis/application/ports/economic_series_ports.dart';
import 'package:equis/application/services/economic_series_service.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Cache cache;
  late _Provider provider;
  late UtcInstant now;
  late EconomicSeriesService service;
  final historical = EconomicSeriesRange(
    from: LocalDate(2015, 1, 1),
    through: LocalDate(2026, 9, 30),
  );
  final ranges = {EconomicSeriesCode.cdiDaily: historical};
  setUp(() {
    cache = _Cache();
    provider = _Provider();
    now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 30));
    service = EconomicSeriesService(
      cache: cache,
      provider: provider,
      remoteReadsEnabled: true,
      clock: () => now,
    );
  });

  test(
    'bounded rounds continue historical pages without repeating the prefix',
    () async {
      expect((await service.refreshRanges(ranges: ranges)).refreshedPages, 4);
      final next = provider.calls.last.$3.addDays(1);
      await service.refreshRanges(ranges: ranges);
      expect(provider.calls, hasLength(8));
      expect(provider.calls[4].$2, next);
      await service.refreshRanges(ranges: ranges);
      expect(provider.calls.last.$3, historical.through);
      final completedCalls = provider.calls.length;
      await service.refreshRanges(ranges: ranges);
      expect(provider.calls, hasLength(completedCalls));
      for (final call in provider.calls) {
        expect(
          call.$3.toUtcDate().difference(call.$2.toUtcDate()).inDays,
          lessThanOrEqualTo(365),
        );
      }
    },
  );

  test(
    'failed page retains cache and resumes at failure after cooldown',
    () async {
      provider.failOnCall = 2;
      final first = await service.refreshRanges(ranges: ranges);
      expect(first.refreshedPages, 1);
      expect(first.failedCodes, 1);
      final failedStart = provider.calls.last.$2;
      expect(cache.values, hasLength(1));
      await service.refreshRanges(ranges: ranges);
      expect(provider.calls, hasLength(2));
      now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 30, 4));
      provider.failOnCall = null;
      await service.refreshRanges(ranges: ranges);
      expect(provider.calls[2].$2, failedStart);
      expect(cache.values.first.referenceStart, historical.from);
    },
  );

  test(
    'disabled refresh and cache-only read make no provider requests',
    () async {
      final disabled = EconomicSeriesService(cache: cache, provider: provider);
      await disabled.refreshRanges(ranges: ranges);
      await disabled.read(
        code: EconomicSeriesCode.cdiDaily,
        from: historical.from,
        through: historical.through,
        refresh: true,
      );
      await service.read(
        code: EconomicSeriesCode.cdiDaily,
        from: historical.from,
        through: historical.through,
      );
      expect(provider.calls, isEmpty);
    },
  );

  test(
    'overlapping rounds never exceed two requests and cancel before cache writes',
    () async {
      final pending = Completer<void>();
      provider.wait = pending.future;
      var active = true;
      final all = {
        for (final code in EconomicSeriesCode.values)
          code: EconomicSeriesRange(
            from: LocalDate(2026, 1, 1),
            through: LocalDate(2026, 1, 2),
          ),
      };
      final first = service.refreshRanges(ranges: all, isActive: () => active);
      await provider.started.future;
      await service.refreshRanges(ranges: all);
      expect(provider.calls, hasLength(2));
      active = false;
      pending.complete();
      await first;
      expect(provider.maximumActive, 2);
      expect(cache.values, isEmpty);
      expect(cache.states, isEmpty);
    },
  );

  test(
    'closing waits for in-flight provider work and prevents late cache writes',
    () async {
      final pending = Completer<void>();
      provider.wait = pending.future;
      final closingRanges = {
        ...ranges,
        EconomicSeriesCode.selicDaily: historical,
      };
      final refresh = service.refreshRanges(ranges: closingRanges);
      await provider.started.future;
      var finished = false;
      final closing = service.close().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(service.isActive, isFalse);
      await service.refreshRanges(ranges: ranges);
      expect(provider.calls, hasLength(2));
      pending.complete();
      await refresh;
      await closing;
      expect(finished, isTrue);
      expect(cache.values, isEmpty);
      expect(cache.states, isEmpty);
    },
  );

  test(
    'closing also drains position preparation before provider work',
    () async {
      final entered = Completer<void>();
      final finishScan = Completer<void>();
      final preparation = service.prepareRefresh(() async {
        entered.complete();
        await finishScan.future;
        return service.refreshRanges(ranges: ranges);
      });
      await entered.future;
      var closed = false;
      final closing = service.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      finishScan.complete();
      await preparation;
      await closing;
      expect(provider.calls, isEmpty);
      expect(closed, isTrue);
    },
  );
}

final class _Provider implements EconomicSeriesProvider {
  final calls = <(EconomicSeriesCode, LocalDate, LocalDate)>[];
  final started = Completer<void>();
  Future<void>? wait;
  int? failOnCall;
  int active = 0;
  int maximumActive = 0;
  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async {
    calls.add((code, from, through));
    final number = calls.length;
    active++;
    if (active > maximumActive) maximumActive = active;
    if (active == 2 && !started.isCompleted) started.complete();
    try {
      await wait;
      if (number == failOnCall) {
        throw const EconomicSeriesProviderUnavailable('offline');
      }
      return [
        EconomicSeriesObservation(
          code: code,
          referenceStart: from,
          referenceEnd: from,
          value: '0.1',
          fetchedAt: UtcInstant.fromDateTime(DateTime.utc(2026, 9, 30)),
        ),
      ];
    } finally {
      active--;
    }
  }
}

final class _Cache implements EconomicSeriesCache {
  final values = <EconomicSeriesObservation>[];
  final states = <EconomicSeriesCode, EconomicSeriesRefreshState>{};
  @override
  Future<void> saveAll(List<EconomicSeriesObservation> observations) async =>
      values.addAll(observations);
  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async => values
      .where(
        (value) =>
            value.code == code &&
            value.referenceStart.compareTo(through) <= 0 &&
            value.referenceEnd.compareTo(from) >= 0,
      )
      .toList();
  @override
  Future<UtcInstant?> latestFetchedAt(EconomicSeriesCode code) async =>
      values.where((value) => value.code == code).firstOrNull?.fetchedAt;
  @override
  Future<LocalDate?> latestReferenceEnd(EconomicSeriesCode code) async =>
      values.where((value) => value.code == code).lastOrNull?.referenceEnd;
  @override
  Future<EconomicSeriesRefreshState?> refreshState(
    EconomicSeriesCode code,
  ) async => states[code];
  @override
  Future<void> recordRefresh({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
    required UtcInstant attemptedAt,
    String? errorCode,
  }) async {
    states[code] = EconomicSeriesRefreshState(
      code: code,
      requestedFrom: from,
      requestedThrough: through,
      lastAttemptAt: attemptedAt,
      lastSuccessAt: errorCode == null
          ? attemptedAt
          : states[code]?.lastSuccessAt,
      lastErrorCode: errorCode,
    );
  }
}
