import 'package:decimal/decimal.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/investments/fixed_income_contract.dart';
import 'package:equis/domain/investments/fixed_income_valuation.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:flutter_test/flutter_test.dart';

final _lotId = EntityId.generate();
final _computedAt = UtcInstant.fromDateTime(DateTime.utc(2026, 6, 1));
final _start = LocalDate(2026, 1, 1);
const _valuator = FixedIncomeValuator();

LotPosition _position({
  String quantity = '1',
  String disposed = '0',
  LocalDate? acquiredOn,
}) => LotPosition(
  lot: InvestmentLot(
    id: _lotId,
    acquisitionEventId: EntityId.generate(),
    instrumentId: EntityId.generate(),
    acquiredOn: acquiredOn ?? _start,
    originalQuantity: Decimal.parse(quantity),
    costBasisMinor: 100000,
    costCurrency: CurrencyCode.brl,
  ),
  disposedQuantity: Decimal.parse(disposed),
  allocatedCostMinor: 0,
);

FixedIncomeTerms _fixed({
  String principal = '1000',
  String rate = '0.1208',
  int basis = 365,
  LocalDate? maturity,
  LocalDate? start,
}) => FixedIncomeTerms(
  principal: Decimal.parse(principal),
  currency: CurrencyCode.brl,
  productName: 'Declared fixed rule',
  accrualStart: start ?? _start,
  maturityOn: maturity,
  mode: FixedIncomeRemunerationMode.fixedAnnual,
  updateRule: FixedIncomeUpdateRule.annualCompound,
  annualRate: Decimal.parse(rate),
  dayCountBasis: basis,
  calendarVersion: basis == 252 ? 'business-2026-v1' : null,
);

FixedIncomeTerms _daily({
  String? multiplier,
  String? spread,
  LocalDate? start,
  EconomicSeriesCode code = EconomicSeriesCode.cdiDaily,
}) => FixedIncomeTerms(
  principal: Decimal.parse('1000000'),
  currency: CurrencyCode.brl,
  productName: 'Declared CDI rule',
  accrualStart: start ?? _start,
  mode: multiplier != null
      ? FixedIncomeRemunerationMode.dailyIndexPercent
      : FixedIncomeRemunerationMode.dailyIndexSpread,
  updateRule: FixedIncomeUpdateRule.dailyObservation,
  indexCode: code,
  indexMultiplier: multiplier == null ? null : Decimal.parse(multiplier),
  annualSpread: spread == null ? null : Decimal.parse(spread),
  dayCountBasis: spread == null ? null : 252,
  calendarVersion: 'business-2026-v1',
);

FixedIncomeTerms _monthly({
  String? spread,
  int lag = 0,
  EconomicSeriesCode code = EconomicSeriesCode.ipcaMonthly,
}) => FixedIncomeTerms(
  principal: Decimal.parse('1000'),
  currency: CurrencyCode.brl,
  productName: 'Declared monthly rule',
  accrualStart: LocalDate(2026, 1, 15),
  mode: FixedIncomeRemunerationMode.monthlyIndex,
  updateRule: FixedIncomeUpdateRule.monthlyAnniversary,
  indexCode: code,
  annualSpread: spread == null ? null : Decimal.parse(spread),
  publicationLagMonths: lag,
  anniversaryDay: 15,
);

EconomicSeriesObservation _observation(
  EconomicSeriesCode code,
  LocalDate from,
  LocalDate through,
  String percent,
) => EconomicSeriesObservation(
  code: code,
  referenceStart: from,
  referenceEnd: through,
  value: percent,
  fetchedAt: _computedAt,
);

final class _Calendar implements BusinessCalendar {
  _Calendar({
    this.version = 'business-2026-v1',
    this.unknown = const {},
    this.holidays = const {},
  });
  @override
  final String version;
  final Set<LocalDate> unknown;
  final Set<LocalDate> holidays;

  @override
  bool? isBusinessDay(LocalDate date) {
    if (unknown.contains(date)) return null;
    if (holidays.contains(date)) return false;
    return date.toUtcDate().weekday <= DateTime.friday;
  }
}

PositionValuation _evaluate(
  FixedIncomeTerms terms,
  LocalDate asOf, {
  LotPosition? position,
  Iterable<EconomicSeriesObservation> observations = const [],
  Iterable<FixedIncomeManualValue> manualValues = const [],
  BusinessCalendar? calendar,
  bool manualValidAfterDisposal = false,
}) => _valuator.evaluate(
  position: position ?? _position(),
  terms: terms,
  asOf: asOf,
  calculatedAt: _computedAt,
  observations: observations,
  manualValues: manualValues,
  calendar: calendar,
  manualValidAfterDisposal: manualValidAfterDisposal,
);

void main() {
  test('fixed 12.08% accrues for elapsed actual days and rounds once', () {
    final value = _evaluate(_fixed(), LocalDate(2027, 1, 1));
    expect(value.amountMinor, 112080);
    expect(value.state, ValuationState.current);
    expect(value.origin, ValuationOrigin.contractual);
    expect(value.valueDate, LocalDate(2027, 1, 1));
  });

  test('252-day fixed basis needs matching verified calendar', () {
    final terms = _fixed(basis: 252);
    final day = LocalDate(2026, 1, 3);
    expect(_evaluate(terms, day).state, ValuationState.incomplete);
    expect(
      _evaluate(terms, day, calendar: _Calendar(version: 'other')).amountMinor,
      isNull,
    );
    final verified = _evaluate(terms, day, calendar: _Calendar());
    expect(verified.amountMinor, greaterThan(100000));
    final unknown = _evaluate(
      terms,
      day,
      calendar: _Calendar(unknown: {LocalDate(2026, 1, 2)}),
    );
    expect(unknown.amountMinor, isNull);
    expect(unknown.missingPeriods.single.reason, MissingPeriodReason.calendar);
  });

  test('252-day fixed basis counts Friday through Saturday and Monday', () {
    final terms = _fixed(basis: 252, start: LocalDate(2026, 1, 2));
    final saturday = _evaluate(
      terms,
      LocalDate(2026, 1, 3),
      calendar: _Calendar(),
    );
    final monday = _evaluate(
      terms,
      LocalDate(2026, 1, 5),
      calendar: _Calendar(),
    );
    expect(saturday.amountMinor, greaterThan(100000));
    expect(monday.amountMinor, saturday.amountMinor);
  });

  test('20%, 118%, and 119% CDI produce distinct daily balances', () {
    final day = LocalDate(2026, 1, 2);
    final rate = _observation(
      EconomicSeriesCode.cdiDaily,
      _start,
      _start,
      '0.1',
    );
    int? value(String multiplier) => _evaluate(
      _daily(multiplier: multiplier),
      day,
      observations: [rate],
      calendar: _Calendar(),
    ).amountMinor;
    expect(value('0.2'), 100020000);
    expect(value('1.18'), 100118000);
    expect(value('1.19'), 100119000);
  });

  test('CDI plus 1.2 percentage points compounds annual spread per day', () {
    final day = LocalDate(2026, 1, 2);
    final result = _evaluate(
      _daily(spread: '0.012'),
      day,
      observations: [
        _observation(EconomicSeriesCode.cdiDaily, _start, _start, '0.1'),
      ],
      calendar: _Calendar(),
    );
    expect(result.amountMinor, 100104738);
    expect(result.source, 'contract+BCB_SGS:12');
  });

  test('daily weekend and declared holiday need no invented observations', () {
    final friday = LocalDate(2026, 1, 2);
    final monday = LocalDate(2026, 1, 5);
    final result = _evaluate(
      _daily(multiplier: '1'),
      monday,
      observations: [
        _observation(EconomicSeriesCode.cdiDaily, friday, friday, '0.1'),
      ],
      calendar: _Calendar(holidays: {_start}),
    );
    expect(result.amountMinor, 100100000);
    expect(result.missingPeriods, isEmpty);
  });

  test('Friday acquisition accrues Friday rate through Monday', () {
    final friday = LocalDate(2026, 1, 2);
    final monday = LocalDate(2026, 1, 5);
    final result = _evaluate(
      _daily(multiplier: '1', start: friday),
      monday,
      position: _position(acquiredOn: friday),
      observations: [
        _observation(EconomicSeriesCode.cdiDaily, friday, friday, '0.1'),
      ],
      calendar: _Calendar(),
    );
    expect(result.amountMinor, 100100000);
  });

  test('Selic daily uses the acquisition day rate', () {
    final result = _evaluate(
      _daily(multiplier: '1', code: EconomicSeriesCode.selicDaily),
      LocalDate(2026, 1, 2),
      observations: [
        _observation(EconomicSeriesCode.selicDaily, _start, _start, '0.1'),
      ],
      calendar: _Calendar(),
    );
    expect(result.amountMinor, 100100000);
  });

  test('a missing expected daily observation leaves no amount', () {
    final result = _evaluate(
      _daily(multiplier: '1'),
      LocalDate(2026, 1, 2),
      calendar: _Calendar(),
    );
    expect(result.amountMinor, isNull);
    expect(result.state, ValuationState.incomplete);
    expect(result.missingPeriods.single.code, EconomicSeriesCode.cdiDaily);
  });

  test(
    'monthly index waits for a completed anniversary and retains deflation',
    () {
      final terms = _monthly(spread: '0.012');
      final jan = _observation(
        EconomicSeriesCode.ipcaMonthly,
        LocalDate(2026, 1, 1),
        LocalDate(2026, 1, 31),
        '-0.5',
      );
      expect(
        _evaluate(
          terms,
          LocalDate(2026, 2, 14),
          observations: [jan],
        ).amountMinor,
        100000,
      );
      expect(
        _evaluate(
          terms,
          LocalDate(2026, 2, 15),
          observations: [jan],
        ).amountMinor,
        99599,
      );
    },
  );

  test(
    'publication lag selects an older month; missing month is incomplete',
    () {
      final terms = _monthly(lag: 1, code: EconomicSeriesCode.inpcMonthly);
      final missing = _evaluate(terms, LocalDate(2026, 2, 15));
      expect(missing.amountMinor, isNull);
      expect(missing.missingPeriods.single.start, LocalDate(2025, 12, 1));
      final december = _observation(
        EconomicSeriesCode.inpcMonthly,
        LocalDate(2025, 12, 1),
        LocalDate(2025, 12, 31),
        '1',
      );
      expect(
        _evaluate(
          terms,
          LocalDate(2026, 2, 15),
          observations: [december],
        ).amountMinor,
        101000,
      );
    },
  );

  test('TR applies once only when the validity interval is completed', () {
    final terms = FixedIncomeTerms(
      principal: Decimal.parse('1000'),
      currency: CurrencyCode.brl,
      productName: 'Declared TR rule',
      accrualStart: _start,
      mode: FixedIncomeRemunerationMode.trValidity,
      updateRule: FixedIncomeUpdateRule.validityInterval,
      indexCode: EconomicSeriesCode.trPeriod,
    );
    final observation = _observation(
      EconomicSeriesCode.trPeriod,
      _start,
      LocalDate(2026, 2, 1),
      '0.5',
    );
    expect(
      _evaluate(
        terms,
        LocalDate(2026, 1, 31),
        observations: [observation],
      ).amountMinor,
      100000,
    );
    final laterEnd = _observation(
      EconomicSeriesCode.trPeriod,
      _start,
      LocalDate(2026, 2, 2),
      '0.5',
    );
    expect(
      _evaluate(
        terms,
        LocalDate(2026, 2, 1),
        observations: [laterEnd],
      ).amountMinor,
      100000,
    );
    expect(
      _evaluate(
        terms,
        LocalDate(2026, 2, 1),
        observations: [observation],
      ).amountMinor,
      100500,
    );
    final next = _observation(
      EconomicSeriesCode.trPeriod,
      LocalDate(2026, 2, 1),
      LocalDate(2026, 3, 1),
      '0.3',
    );
    expect(
      _evaluate(
        terms,
        LocalDate(2026, 3, 1),
        observations: [observation, next],
      ).amountMinor,
      100802,
    );
    final missing = _evaluate(terms, LocalDate(2026, 2, 1));
    expect(missing.amountMinor, isNull);
    expect(missing.missingPeriods.single.code, EconomicSeriesCode.trPeriod);
  });

  test(
    'TR completion follows the published end, even before a calendar month',
    () {
      final start = LocalDate(2026, 1, 30);
      final end = LocalDate(2026, 2, 27);
      final terms = FixedIncomeTerms(
        principal: Decimal.fromInt(1000),
        currency: CurrencyCode.brl,
        productName: 'TR with a short validity interval',
        accrualStart: start,
        mode: FixedIncomeRemunerationMode.trValidity,
        updateRule: FixedIncomeUpdateRule.validityInterval,
        indexCode: EconomicSeriesCode.trPeriod,
      );
      final rate = _observation(EconomicSeriesCode.trPeriod, start, end, '0.5');
      expect(_evaluate(terms, end, observations: [rate]).amountMinor, 100500);
      final missing = _evaluate(terms, end);
      expect(missing.amountMinor, isNull);
      expect(missing.state, ValuationState.incomplete);
    },
  );

  test('maturity stops accrual and flags a still-held position', () {
    final maturity = LocalDate(2027, 1, 1);
    final result = _evaluate(_fixed(maturity: maturity), LocalDate(2027, 2, 1));
    expect(result.amountMinor, 112080);
    expect(result.valueDate, maturity);
    expect(result.state, ValuationState.maturedActionRequired);
  });

  test('remaining homogeneous principal scales after partial disposal', () {
    final result = _evaluate(
      _fixed(),
      LocalDate(2027, 1, 1),
      position: _position(quantity: '2', disposed: '0.5'),
    );
    expect(result.amountMinor, 84060);
  });

  test('dated manual value wins; removal uses the latest active value', () {
    final id = EntityId.generate();
    final manual = FixedIncomeManualValue(
      id: id,
      lotId: _lotId,
      valueDate: LocalDate(2026, 1, 3),
      amountMinor: 123456,
      currency: CurrencyCode.brl,
      recordedAt: _computedAt,
    );
    final asOf = LocalDate(2026, 1, 4);
    final used = _evaluate(_fixed(), asOf, manualValues: [manual]);
    expect(used.amountMinor, 123456);
    expect(used.valueDate, manual.valueDate);
    expect(used.origin, ValuationOrigin.manual);
    final removed = FixedIncomeManualValue(
      id: id,
      lotId: _lotId,
      valueDate: manual.valueDate,
      amountMinor: manual.amountMinor,
      currency: manual.currency,
      recordedAt: manual.recordedAt,
      removedAt: UtcInstant.fromDateTime(DateTime.utc(2026, 6, 2)),
    );
    final fallback = _evaluate(_fixed(), asOf, manualValues: [removed]);
    expect(fallback.origin, ValuationOrigin.contractual);
    expect(fallback.amountMinor, isNot(123456));
    final older = FixedIncomeManualValue(
      id: EntityId.generate(),
      lotId: _lotId,
      valueDate: LocalDate(2026, 1, 2),
      amountMinor: 120000,
      currency: CurrencyCode.brl,
      recordedAt: _computedAt,
    );
    final fallbackWithHistory = _evaluate(
      _fixed(),
      asOf,
      manualValues: [older, removed],
    );
    expect(fallbackWithHistory.origin, ValuationOrigin.manual);
    expect(fallbackWithHistory.amountMinor, 120000);
  });

  test('manual balance after disposal requires durable causal proof', () {
    final manual = FixedIncomeManualValue(
      id: EntityId.generate(),
      lotId: _lotId,
      valueDate: LocalDate(2026, 1, 3),
      amountMinor: 123456,
      currency: CurrencyCode.brl,
      recordedAt: _computedAt,
    );
    final position = _position(quantity: '2', disposed: '1');
    final unverified = _evaluate(
      _fixed(),
      LocalDate(2026, 1, 4),
      position: position,
      manualValues: [manual],
    );
    expect(unverified.amountMinor, isNull);
    expect(unverified.state, ValuationState.manualRequired);
    final verified = _evaluate(
      _fixed(),
      LocalDate(2026, 1, 4),
      position: position,
      manualValues: [manual],
      manualValidAfterDisposal: true,
    );
    expect(verified.amountMinor, 123456);
  });

  test(
    'persisted manual proof must still be checked after disposition becomes zero',
    () {
      final manual = FixedIncomeManualValue(
        id: EntityId.generate(),
        lotId: _lotId,
        valueDate: LocalDate(2026, 1, 3),
        amountMinor: 123456,
        currency: CurrencyCode.brl,
        recordedAt: _computedAt,
        disposalFingerprint: 'previous-sale-proof',
      );
      final unverified = _evaluate(
        _fixed(),
        LocalDate(2026, 1, 4),
        manualValues: [manual],
        position: _position(),
      );
      expect(unverified.amountMinor, isNull);
      expect(unverified.state, ValuationState.manualRequired);
    },
  );

  test('manual-only requires balance and fully disposed lot is closed', () {
    final terms = FixedIncomeTerms(
      principal: Decimal.parse('1000'),
      currency: CurrencyCode.brl,
      productName: 'Coupon schedule',
      accrualStart: _start,
      mode: FixedIncomeRemunerationMode.manualOnly,
      updateRule: FixedIncomeUpdateRule.manualValue,
    );
    expect(
      _evaluate(terms, LocalDate(2026, 1, 2)).state,
      ValuationState.manualRequired,
    );
    final closed = _evaluate(
      terms,
      LocalDate(2026, 1, 2),
      position: _position(disposed: '1'),
    );
    expect(closed.state, ValuationState.closed);
    expect(closed.amountMinor, isNull);
  });
}
