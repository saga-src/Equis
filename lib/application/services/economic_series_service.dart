import 'dart:async';

import '../ports/economic_series_ports.dart';
import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';

final class EconomicSeriesRange {
  const EconomicSeriesRange({required this.from, required this.through});
  final LocalDate from;
  final LocalDate through;
}

final class EconomicSeriesRefreshSummary {
  const EconomicSeriesRefreshSummary({
    this.refreshedPages = 0,
    this.failedCodes = 0,
  });
  final int refreshedPages;
  final int failedCodes;
}

final class _SeriesProgress {
  _SeriesProgress(this.range) : next = range.from;
  EconomicSeriesRange range;
  LocalDate next;
  UtcInstant? retryAfter;
}

final class EconomicSeriesRead {
  const EconomicSeriesRead({
    required this.observations,
    required this.latestFetchedAt,
    required this.latestReferenceEnd,
    required this.refreshState,
    required this.refreshFailed,
  });

  final List<EconomicSeriesObservation> observations;
  final UtcInstant? latestFetchedAt;
  final LocalDate? latestReferenceEnd;
  final EconomicSeriesRefreshState? refreshState;
  final bool refreshFailed;
}

final class EconomicSeriesService {
  EconomicSeriesService({
    required this.cache,
    required this.provider,
    this.remoteReadsEnabled = false,
    this.minimumOpenRefreshInterval = const Duration(hours: 3),
    UtcInstant Function()? clock,
  }) : _clock = clock ?? UtcInstant.now;

  final EconomicSeriesCache cache;
  final EconomicSeriesProvider provider;

  /// Remains disabled until central licensing and endpoint validation pass.
  final bool remoteReadsEnabled;
  final Duration minimumOpenRefreshInterval;
  final UtcInstant Function() _clock;
  final _progress = <EconomicSeriesCode, _SeriesProgress>{};
  final _inFlight = <EconomicSeriesCode>{};
  int _nextCode = 0;
  bool _roundActive = false;
  bool _closed = false;
  final Set<Future<Object?>> _activeOperations = {};
  bool get isActive => !_closed;

  Future<void> close() async {
    _closed = true;
    await Future.wait([
      for (final operation in _activeOperations.toList())
        operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]);
  }

  Future<T> _track<T>(Future<T> operation) {
    _activeOperations.add(operation);
    return operation.whenComplete(() => _activeOperations.remove(operation));
  }

  /// Includes the position scan in shutdown draining, before network work begins.
  Future<EconomicSeriesRefreshSummary> prepareRefresh(
    Future<EconomicSeriesRefreshSummary> Function() prepare,
  ) => _closed
      ? Future.value(const EconomicSeriesRefreshSummary())
      : _track(prepare());

  Future<EconomicSeriesRead> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
    bool refresh = false,
    bool Function()? isActive,
  }) {
    if (_closed) {
      return Future.value(
        const EconomicSeriesRead(
          observations: [],
          latestFetchedAt: null,
          latestReferenceEnd: null,
          refreshState: null,
          refreshFailed: false,
        ),
      );
    }
    return _track(
      _read(
        code: code,
        from: from,
        through: through,
        refresh: refresh,
        isActive: () => !_closed && isActive?.call() != false,
      ),
    );
  }

  Future<EconomicSeriesRead> _read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
    bool refresh = false,
    bool Function()? isActive,
  }) async {
    if (from.compareTo(through) > 0) {
      throw ArgumentError('Series range is reversed.');
    }
    var refreshFailed = false;
    if (refresh && remoteReadsEnabled) {
      var start = from;
      while (start.compareTo(through) <= 0) {
        if (isActive?.call() == false) break;
        final limit = start.addDays(365);
        final end = limit.compareTo(through) < 0 ? limit : through;
        final attemptedAt = _clock();
        try {
          final values = await provider.read(
            code: code,
            from: start,
            through: end,
          );
          if (isActive?.call() == false) break;
          await cache.saveAll(values);
          if (isActive?.call() == false) break;
          await cache.recordRefresh(
            code: code,
            from: start,
            through: end,
            attemptedAt: attemptedAt,
          );
        } on EconomicSeriesProviderUnavailable catch (error) {
          if (isActive?.call() == false) break;
          await cache.recordRefresh(
            code: code,
            from: start,
            through: end,
            attemptedAt: attemptedAt,
            errorCode: error.reason,
          );
          refreshFailed = true;
          break;
        } on Exception {
          if (isActive?.call() == false) break;
          await cache.recordRefresh(
            code: code,
            from: start,
            through: end,
            attemptedAt: attemptedAt,
            errorCode: 'refresh_failed',
          );
          refreshFailed = true;
          break;
        }
        start = end.addDays(1);
      }
    }
    if (isActive?.call() == false) {
      return const EconomicSeriesRead(
        observations: [],
        latestFetchedAt: null,
        latestReferenceEnd: null,
        refreshState: null,
        refreshFailed: false,
      );
    }
    return EconomicSeriesRead(
      observations: await cache.read(code: code, from: from, through: through),
      latestFetchedAt: await cache.latestFetchedAt(code),
      latestReferenceEnd: await cache.latestReferenceEnd(code),
      refreshState: await cache.refreshState(code),
      refreshFailed: refreshFailed,
    );
  }

  Future<void> refreshOnOpen(UtcInstant now) async {
    if (!remoteReadsEnabled) return;
    final current = now.toDateTime();
    final today = LocalDate(current.year, current.month, current.day);
    final from = today.addDays(-365);
    await refreshRanges(
      ranges: {
        for (final code in EconomicSeriesCode.values)
          code: EconomicSeriesRange(from: from, through: today),
      },
      now: now,
    );
  }

  /// At most two provider requests run together. A round starts no new page
  /// after 30 seconds; the provider's 15-second deadline can finish afterward.
  /// Cursors survive repeated refreshes in this service, including failures.
  Future<EconomicSeriesRefreshSummary> refreshRanges({
    required Map<EconomicSeriesCode, EconomicSeriesRange> ranges,
    UtcInstant? now,
    bool Function()? isActive,
  }) {
    if (_closed) return Future.value(const EconomicSeriesRefreshSummary());
    return _track(
      _refreshRanges(
        ranges: ranges,
        now: now,
        isActive: () => !_closed && isActive?.call() != false,
      ),
    );
  }

  Future<EconomicSeriesRefreshSummary> _refreshRanges({
    required Map<EconomicSeriesCode, EconomicSeriesRange> ranges,
    UtcInstant? now,
    bool Function()? isActive,
  }) async {
    if (!remoteReadsEnabled ||
        _roundActive ||
        isActive?.call() == false ||
        ranges.isEmpty) {
      return const EconomicSeriesRefreshSummary();
    }
    _roundActive = true;
    try {
      final attemptedAt = now ?? _clock();
      final budget = Stopwatch()..start();
      final codes = EconomicSeriesCode.values;
      final ordered = [
        for (var i = 0; i < codes.length; i++)
          codes[(_nextCode + i) % codes.length],
      ];
      var refreshed = 0;
      var failed = 0;
      var index = 0;
      Future<void> worker() async {
        while (index < ordered.length &&
            budget.elapsed < const Duration(seconds: 30) &&
            isActive?.call() != false) {
          final code = ordered[index++];
          _nextCode = (codes.indexOf(code) + 1) % codes.length;
          final range = ranges[code];
          if (range == null ||
              range.from.compareTo(range.through) > 0 ||
              !_inFlight.add(code)) {
            continue;
          }
          try {
            var progress = _progress[code];
            if (progress == null || progress.range.from != range.from) {
              progress = _SeriesProgress(range);
              _progress[code] = progress;
              final state = await cache.refreshState(code);
              if (state != null &&
                  state.requestedFrom.compareTo(range.from) <= 0 &&
                  state.requestedThrough.compareTo(range.through) >= 0) {
                progress.retryAfter = UtcInstant.fromEpochMicroseconds(
                  state.lastAttemptAt.epochMicroseconds +
                      minimumOpenRefreshInterval.inMicroseconds,
                );
              }
            }
            if (range.through.compareTo(progress.range.through) > 0) {
              progress.retryAfter = null;
            }
            progress.range = range;
            final retry = progress.retryAfter;
            if (retry != null && attemptedAt.compareTo(retry) < 0) continue;
            progress.retryAfter = null;
            if (progress.next.compareTo(range.through) > 0) {
              progress.next = range.from;
            }
            for (var page = 0; page < 4; page++) {
              if (budget.elapsed >= const Duration(seconds: 30) ||
                  isActive?.call() == false) {
                break;
              }
              final start = progress.next;
              final limit = start.addDays(365);
              final end = limit.compareTo(range.through) < 0
                  ? limit
                  : range.through;
              final result = await read(
                code: code,
                from: start,
                through: end,
                refresh: true,
                isActive: isActive,
              );
              if (isActive?.call() == false) break;
              if (result.refreshFailed) {
                failed++;
                progress.retryAfter = UtcInstant.fromEpochMicroseconds(
                  attemptedAt.epochMicroseconds +
                      minimumOpenRefreshInterval.inMicroseconds,
                );
                break;
              }
              refreshed++;
              progress.next = end.addDays(1);
              if (progress.next.compareTo(range.through) > 0) {
                progress.retryAfter = UtcInstant.fromEpochMicroseconds(
                  attemptedAt.epochMicroseconds +
                      minimumOpenRefreshInterval.inMicroseconds,
                );
                break;
              }
            }
          } finally {
            _inFlight.remove(code);
          }
        }
      }

      await Future.wait([worker(), worker()]);
      return EconomicSeriesRefreshSummary(
        refreshedPages: refreshed,
        failedCodes: failed,
      );
    } finally {
      _roundActive = false;
    }
  }
}
