import 'package:decimal/decimal.dart';

import '../economic_series/economic_series_observation.dart';
import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/money.dart';
import '../shared/utc_instant.dart';
import 'fixed_income_contract.dart';
import 'investment_models.dart';

/// A versioned, verified answer for each day. Null means the date is outside
/// the calendar's verified coverage, rather than a non-business day.
abstract interface class BusinessCalendar {
  String get version;
  bool? isBusinessDay(LocalDate date);
}

enum ValuationOrigin { contractual, manual, market }

enum ValuationState {
  current,
  incomplete,
  maturedActionRequired,
  manualRequired,
  closed,
  notStarted,
}

enum MissingPeriodReason { calendar, observation }

final class ValuationMissingPeriod {
  const ValuationMissingPeriod({
    required this.start,
    required this.end,
    required this.reason,
    this.code,
  });

  final LocalDate start;
  final LocalDate end;
  final MissingPeriodReason reason;
  final EconomicSeriesCode? code;
}

final class PositionValuation {
  PositionValuation({
    required this.amountMinor,
    required this.currency,
    required this.valueDate,
    required this.calculatedAt,
    required this.origin,
    required this.state,
    required this.source,
    required List<ValuationMissingPeriod> missingPeriods,
  }) : missingPeriods = List.unmodifiable(missingPeriods);

  final int? amountMinor;
  final CurrencyCode currency;
  final LocalDate valueDate;
  final UtcInstant calculatedAt;
  final ValuationOrigin origin;
  final ValuationState state;
  final String source;
  final List<ValuationMissingPeriod> missingPeriods;
}

/// Pure contractual balance calculation. Rates are proportions in contract
/// terms and percentages in public observations. No redemption price, tax, or
/// guarantee is inferred from a product name.
final class FixedIncomeValuator {
  const FixedIncomeValuator();

  PositionValuation evaluate({
    required LotPosition position,
    required FixedIncomeTerms terms,
    required LocalDate asOf,
    required UtcInstant calculatedAt,
    required Iterable<EconomicSeriesObservation> observations,
    Iterable<FixedIncomeManualValue> manualValues = const [],
    BusinessCalendar? calendar,
    bool manualValidAfterDisposal = false,
    int currencyMinorUnits = 2,
  }) {
    if (currencyMinorUnits < 0 || currencyMinorUnits > 9) {
      throw RangeError.range(currencyMinorUnits, 0, 9, 'currencyMinorUnits');
    }
    if (terms.currency != position.lot.costCurrency) {
      throw ArgumentError('Contract and lot currencies differ.');
    }
    if (position.remainingQuantity == Decimal.zero) {
      return _result(terms, asOf, calculatedAt, null, ValuationState.closed);
    }
    if (asOf.compareTo(terms.accrualStart) < 0) {
      return _result(
        terms,
        asOf,
        calculatedAt,
        null,
        ValuationState.notStarted,
      );
    }

    final eligibleManual =
        manualValues
            .where(
              (value) =>
                  value.lotId == position.lot.id &&
                  value.currency == terms.currency &&
                  value.removedAt == null &&
                  value.valueDate.compareTo(asOf) <= 0,
            )
            .toList()
          ..sort((a, b) {
            final byDate = b.valueDate.compareTo(a.valueDate);
            if (byDate != 0) return byDate;
            final byRecording = b.recordedAt.compareTo(a.recordedAt);
            return byRecording != 0
                ? byRecording
                : b.id.value.compareTo(a.id.value);
          });
    if (eligibleManual.isNotEmpty) {
      if (!manualValidAfterDisposal &&
          (position.disposedQuantity > Decimal.zero ||
              eligibleManual.first.disposalFingerprint != null)) {
        return _result(
          terms,
          asOf,
          calculatedAt,
          null,
          ValuationState.manualRequired,
          origin: ValuationOrigin.manual,
          source: 'manual_disposal_unverified',
        );
      }
      final manual = eligibleManual.first;
      if (manual.amountMinor < 0) {
        throw ArgumentError.value(manual.amountMinor, 'amountMinor');
      }
      return PositionValuation(
        amountMinor: manual.amountMinor,
        currency: terms.currency,
        valueDate: manual.valueDate,
        calculatedAt: calculatedAt,
        origin: ValuationOrigin.manual,
        state: _stateAt(terms, asOf),
        source: 'user_manual',
        missingPeriods: const [],
      );
    }
    if (terms.mode == FixedIncomeRemunerationMode.manualOnly) {
      return _result(
        terms,
        asOf,
        calculatedAt,
        null,
        ValuationState.manualRequired,
      );
    }

    final valueDate =
        terms.maturityOn != null && asOf.compareTo(terms.maturityOn!) > 0
        ? terms.maturityOn!
        : asOf;
    final missing = <ValuationMissingPeriod>[];
    final factor = switch (terms.mode) {
      FixedIncomeRemunerationMode.fixedAnnual => _fixedFactor(
        terms,
        valueDate,
        calendar,
        missing,
      ),
      FixedIncomeRemunerationMode.dailyIndexPercent ||
      FixedIncomeRemunerationMode.dailyIndexSpread => _dailyFactor(
        terms,
        valueDate,
        observations,
        calendar,
        missing,
      ),
      FixedIncomeRemunerationMode.monthlyIndex => _monthlyFactor(
        terms,
        valueDate,
        observations,
        missing,
      ),
      FixedIncomeRemunerationMode.trValidity => _trFactor(
        terms,
        valueDate,
        observations,
        missing,
      ),
      FixedIncomeRemunerationMode.manualOnly => null,
    };
    if (factor == null || missing.isNotEmpty) {
      return _result(
        terms,
        valueDate,
        calculatedAt,
        null,
        ValuationState.incomplete,
        missing: missing,
        source: _contractSource(terms),
      );
    }
    final remainingFraction =
        (position.remainingQuantity / position.lot.originalQuantity).toDecimal(
          scaleOnInfinitePrecision: _scale,
        );
    final amount = terms.principal * remainingFraction * factor;
    final rounded = Money.fromMajor(
      currency: CurrencyDefinition(
        code: terms.currency,
        minorUnits: currencyMinorUnits,
      ),
      majorUnits: amount,
    );
    return _result(
      terms,
      valueDate,
      calculatedAt,
      rounded.minorUnits,
      _stateAt(terms, asOf),
      source: _contractSource(terms),
    );
  }

  static const _scale = 42;

  String _contractSource(FixedIncomeTerms terms) => terms.indexCode == null
      ? 'contract'
      : 'contract+BCB_SGS:${terms.indexCode!.sgsCode}';

  PositionValuation _result(
    FixedIncomeTerms terms,
    LocalDate date,
    UtcInstant calculatedAt,
    int? amountMinor,
    ValuationState state, {
    ValuationOrigin origin = ValuationOrigin.contractual,
    String source = 'contract',
    List<ValuationMissingPeriod> missing = const [],
  }) => PositionValuation(
    amountMinor: amountMinor,
    currency: terms.currency,
    valueDate: date,
    calculatedAt: calculatedAt,
    origin: origin,
    state: state,
    source: source,
    missingPeriods: missing,
  );

  ValuationState _stateAt(FixedIncomeTerms terms, LocalDate asOf) =>
      terms.maturityOn != null && asOf.compareTo(terms.maturityOn!) >= 0
      ? ValuationState.maturedActionRequired
      : ValuationState.current;

  Decimal? _fixedFactor(
    FixedIncomeTerms terms,
    LocalDate through,
    BusinessCalendar? calendar,
    List<ValuationMissingPeriod> missing,
  ) {
    final basis = terms.dayCountBasis!;
    if (through == terms.accrualStart) return Decimal.one;
    var elapsed = 0;
    if (basis == 252) {
      if (!_hasCalendar(
        terms,
        calendar,
        terms.accrualStart,
        through.addDays(-1),
        missing,
      )) {
        return null;
      }
      for (
        var day = terms.accrualStart;
        day.compareTo(through) < 0;
        day = day.addDays(1)
      ) {
        final business = calendar!.isBusinessDay(day);
        if (business == null) {
          missing.add(
            ValuationMissingPeriod(
              start: day,
              end: day,
              reason: MissingPeriodReason.calendar,
            ),
          );
        } else if (business) {
          elapsed++;
        }
      }
      if (missing.isNotEmpty) return null;
    } else {
      elapsed = through
          .toUtcDate()
          .difference(terms.accrualStart.toUtcDate())
          .inDays;
    }
    return _rationalPower(Decimal.one + terms.annualRate!, elapsed, basis);
  }

  Decimal? _dailyFactor(
    FixedIncomeTerms terms,
    LocalDate through,
    Iterable<EconomicSeriesObservation> observations,
    BusinessCalendar? calendar,
    List<ValuationMissingPeriod> missing,
  ) {
    if (through == terms.accrualStart) return Decimal.one;
    if (!_hasCalendar(
      terms,
      calendar,
      terms.accrualStart,
      through.addDays(-1),
      missing,
    )) {
      return null;
    }
    final byDate = <LocalDate, EconomicSeriesObservation>{};
    for (final item in observations) {
      if (item.code == terms.indexCode &&
          item.referenceStart == item.referenceEnd) {
        final previous = byDate[item.referenceStart];
        if (previous != null && previous.value != item.value) {
          throw StateError('Conflicting daily observations.');
        }
        byDate[item.referenceStart] = item;
      }
    }
    final spreadFactor =
        terms.mode == FixedIncomeRemunerationMode.dailyIndexSpread
        ? _rationalPower(Decimal.one + terms.annualSpread!, 1, 252)
        : null;
    var factor = Decimal.one;
    // A published rate for business day n accrues until the next business
    // day. The value date itself is excluded from the DI accumulation window.
    for (
      var day = terms.accrualStart;
      day.compareTo(through) < 0;
      day = day.addDays(1)
    ) {
      final business = calendar!.isBusinessDay(day);
      if (business == null) {
        missing.add(
          ValuationMissingPeriod(
            start: day,
            end: day,
            reason: MissingPeriodReason.calendar,
          ),
        );
        continue;
      }
      if (!business) continue;
      final item = byDate[day];
      if (item == null) {
        missing.add(
          ValuationMissingPeriod(
            start: day,
            end: day,
            reason: MissingPeriodReason.observation,
            code: terms.indexCode,
          ),
        );
        continue;
      }
      final rate = Decimal.parse(item.value).shift(-2);
      final daily = terms.mode == FixedIncomeRemunerationMode.dailyIndexPercent
          ? Decimal.one + terms.indexMultiplier! * rate
          : (Decimal.one + rate) * spreadFactor!;
      if (daily <= Decimal.zero) {
        throw StateError('Daily observation produces a non-positive factor.');
      }
      factor = (factor * daily).round(scale: _scale);
    }
    return missing.isEmpty ? factor : null;
  }

  Decimal? _monthlyFactor(
    FixedIncomeTerms terms,
    LocalDate through,
    Iterable<EconomicSeriesObservation> observations,
    List<ValuationMissingPeriod> missing,
  ) {
    final byMonth = <String, EconomicSeriesObservation>{};
    for (final item in observations) {
      if (item.code != terms.indexCode) continue;
      final key = '${item.referenceStart.year}-${item.referenceStart.month}';
      final previous = byMonth[key];
      if (previous != null && previous.value != item.value) {
        throw StateError('Conflicting monthly observations.');
      }
      byMonth[key] = item;
    }
    final spreadFactor = terms.annualSpread == null
        ? Decimal.one
        : _rationalPower(Decimal.one + terms.annualSpread!, 1, 12);
    var factor = Decimal.one;
    for (var count = 1; ; count++) {
      final anniversary = _anniversary(terms, count);
      if (anniversary.compareTo(through) > 0) break;
      // A completed anniversary uses the last fully ended reference month;
      // publicationLagMonths adds whole months to that declared deferral.
      final reference = _addMonths(
        anniversary,
        -1 - terms.publicationLagMonths,
      );
      final key = '${reference.year}-${reference.month}';
      final item = byMonth[key];
      if (item == null || item.referenceEnd.compareTo(anniversary) >= 0) {
        missing.add(
          ValuationMissingPeriod(
            start: LocalDate(reference.year, reference.month, 1),
            end: LocalDate(
              reference.year,
              reference.month,
              DateTime.utc(reference.year, reference.month + 1, 0).day,
            ),
            reason: MissingPeriodReason.observation,
            code: terms.indexCode,
          ),
        );
        continue;
      }
      final monthly = Decimal.one + Decimal.parse(item.value).shift(-2);
      if (monthly <= Decimal.zero) {
        throw StateError('Monthly observation produces a non-positive factor.');
      }
      factor = (factor * monthly * spreadFactor).round(scale: _scale);
    }
    return missing.isEmpty ? factor : null;
  }

  Decimal? _trFactor(
    FixedIncomeTerms terms,
    LocalDate through,
    Iterable<EconomicSeriesObservation> observations,
    List<ValuationMissingPeriod> missing,
  ) {
    final byStart = <LocalDate, EconomicSeriesObservation>{};
    for (final item in observations) {
      if (item.code != EconomicSeriesCode.trPeriod) continue;
      final previous = byStart[item.referenceStart];
      if (previous != null &&
          (previous.referenceEnd != item.referenceEnd ||
              previous.value != item.value)) {
        throw StateError('Conflicting TR validity observations.');
      }
      byStart[item.referenceStart] = item;
    }
    var factor = Decimal.one;
    var start = terms.accrualStart;
    while (true) {
      final item = byStart[start];
      if (item == null) {
        if (start.compareTo(through) < 0) {
          missing.add(
            ValuationMissingPeriod(
              start: start,
              end: through,
              reason: MissingPeriodReason.observation,
              code: EconomicSeriesCode.trPeriod,
            ),
          );
        }
        break;
      }
      if (item.referenceEnd.compareTo(start) <= 0) {
        throw StateError('TR validity interval does not advance.');
      }
      if (item.referenceEnd.compareTo(through) > 0) break;
      final period = Decimal.one + Decimal.parse(item.value).shift(-2);
      if (period <= Decimal.zero) {
        throw StateError('TR observation produces a non-positive factor.');
      }
      factor = (factor * period).round(scale: _scale);
      start = item.referenceEnd;
    }
    return missing.isEmpty ? factor : null;
  }

  bool _hasCalendar(
    FixedIncomeTerms terms,
    BusinessCalendar? calendar,
    LocalDate first,
    LocalDate last,
    List<ValuationMissingPeriod> missing,
  ) {
    if (calendar != null &&
        terms.calendarVersion != null &&
        terms.calendarVersion == calendar.version) {
      return true;
    }
    if (first.compareTo(last) <= 0) {
      missing.add(
        ValuationMissingPeriod(
          start: first,
          end: last,
          reason: MissingPeriodReason.calendar,
        ),
      );
    }
    return false;
  }

  LocalDate _anniversary(FixedIncomeTerms terms, int count) {
    final month = _addMonths(terms.accrualStart, count);
    final last = DateTime.utc(month.year, month.month + 1, 0).day;
    final day = terms.anniversaryDay! < last ? terms.anniversaryDay! : last;
    return LocalDate(month.year, month.month, day);
  }

  LocalDate _addMonths(LocalDate date, int months) {
    final monthIndex = date.year * 12 + date.month - 1 + months;
    final year = monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final last = DateTime.utc(year, month + 1, 0).day;
    return LocalDate(year, month, date.day < last ? date.day : last);
  }

  /// Fixed-scale integer root of an exact rational power. Binary search makes
  /// the result deterministic across Dart targets without floating-point math.
  Decimal _rationalPower(Decimal base, int numerator, int denominator) {
    if (numerator == 0) return Decimal.one;
    if (base <= Decimal.zero || denominator <= 0 || numerator < 0) {
      throw ArgumentError('Invalid rational power.');
    }
    final full = numerator ~/ denominator;
    final remainder = numerator % denominator;
    final whole = base.pow(full).toDecimal();
    if (remainder == 0) return whole;
    final exact = base.pow(remainder);
    final scaledNumerator =
        exact.numerator * BigInt.from(10).pow(_scale * denominator);
    final scaledDenominator = exact.denominator;
    final target = scaledNumerator ~/ scaledDenominator;
    var low = BigInt.zero;
    var high =
        BigInt.one << ((target.bitLength + denominator - 1) ~/ denominator);
    while (low + BigInt.one < high) {
      final mid = (low + high) >> 1;
      if (mid.pow(denominator) <= target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    if (high.pow(denominator) <= target) low = high;
    return (whole * Decimal.fromBigInt(low).shift(-_scale)).round(
      scale: _scale,
    );
  }
}
