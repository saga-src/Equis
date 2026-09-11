import 'package:decimal/decimal.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/decimal_value.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/shared/zoned_recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UUIDv7 identifiers', () {
    test('generate canonical RFC 9562 UUIDv7 values', () {
      final id = EntityId.generate();
      expect(
        id.value,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(EntityId.parse(id.value.toUpperCase()), id);
    });

    test('reject non-v7 identifiers', () {
      expect(
        () => EntityId.parse('550e8400-e29b-41d4-a716-446655440000'),
        throwsFormatException,
      );
    });
  });

  group('currency and money', () {
    test('normalizes valid ISO code shape and rejects invalid values', () {
      expect(CurrencyCode('brl'), CurrencyCode.brl);
      expect(() => CurrencyCode('REAL'), throwsFormatException);
      expect(
        () => CurrencyDefinition(
          code: CurrencyCode.brl,
          minorUnits: -1,
        ).validate(),
        throwsRangeError,
      );
    });

    test(
      'keeps exact minor units and centralizes half-away-from-zero rounding',
      () {
        final brl = CurrencyDefinition(code: CurrencyCode.brl, minorUnits: 2);
        expect(
          Money.fromMajor(
            currency: brl,
            majorUnits: Decimal.parse('123.455'),
          ).minorUnits,
          12346,
        );
        expect(
          Money.fromMajor(
            currency: brl,
            majorUnits: Decimal.parse('-123.455'),
          ).minorUnits,
          -12346,
        );
        expect(
          Money(currency: CurrencyCode.brl, minorUnits: 100) +
              Money(currency: CurrencyCode.brl, minorUnits: 25),
          Money(currency: CurrencyCode.brl, minorUnits: 125),
        );
        expect(
          () =>
              Money(currency: CurrencyCode.brl, minorUnits: 1) +
              Money(currency: CurrencyCode.usd, minorUnits: 1),
          throwsArgumentError,
        );
      },
    );

    test('rejects signed int64 overflow', () {
      expect(
        () =>
            Money(currency: CurrencyCode.brl, minorUnits: Money.maxInt64) +
            Money(currency: CurrencyCode.brl, minorUnits: 1),
        throwsRangeError,
      );
    });
  });

  test(
    'decimal SQLite representation is canonical and never uses binary float',
    () {
      final value = DecimalValue.parse('005.4300');
      expect(DecimalValue.canonical(value), '5.43');
      expect(
        DecimalValue.round(Decimal.parse('1.005'), scale: 2).toString(),
        '1.01',
      );
    },
  );

  group('date and timezone semantics', () {
    test('LocalDate round-trips and rejects normalized invalid dates', () {
      expect(LocalDate.parse('2024-02-29').toString(), '2024-02-29');
      expect(() => LocalDate.parse('2023-02-29'), throwsArgumentError);
      expect(() => LocalDate.parse('2024-2-09'), throwsFormatException);
    });

    test('UTC instants round-trip epoch microseconds', () {
      const instant = UtcInstant.fromEpochMicroseconds(1723392000123456);
      expect(UtcInstant.fromDateTime(instant.toDateTime()), instant);
      expect(instant.toDateTime().isUtc, isTrue);
    });

    test('IANA recurrence keeps local wall time across DST', () {
      final winter = ZonedRecurrenceClock.resolveUtc(
        date: LocalDate.parse('2024-01-15'),
        hour: 9,
        minute: 0,
        timezone: 'America/New_York',
      );
      final summer = ZonedRecurrenceClock.resolveUtc(
        date: LocalDate.parse('2024-07-15'),
        hour: 9,
        minute: 0,
        timezone: 'America/New_York',
      );
      expect(winter.hour, 14);
      expect(summer.hour, 13);
    });
  });
}
