import 'package:equis/domain/investments/brazil_financial_calendar.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calendar = BrazilFinancialCalendar();

  test('bounded version matches the annual SGS 11/12 observation counts', () {
    const expected = <int, int>{
      2021: 251,
      2022: 251,
      2023: 249,
      2024: 253,
      2025: 252,
    };
    for (final entry in expected.entries) {
      var count = 0;
      for (
        var day = LocalDate(entry.key, 1, 1);
        day.year == entry.key;
        day = day.addDays(1)
      ) {
        if (calendar.isBusinessDay(day) == true) count++;
      }
      expect(count, entry.value, reason: '${entry.key} daily SGS dates');
    }
    var count2026 = 0;
    for (
      var day = LocalDate(2026, 1, 1);
      day.compareTo(LocalDate(2026, 9, 23)) <= 0;
      day = day.addDays(1)
    ) {
      if (calendar.isBusinessDay(day) == true) count2026++;
    }
    expect(count2026, 182);
  });

  test('holiday exceptions and future publication remain explicit', () {
    expect(calendar.isBusinessDay(LocalDate(2026, 2, 16)), isFalse);
    expect(calendar.isBusinessDay(LocalDate(2026, 2, 17)), isFalse);
    expect(calendar.isBusinessDay(LocalDate(2026, 4, 3)), isFalse);
    expect(calendar.isBusinessDay(LocalDate(2026, 6, 4)), isFalse);
    expect(calendar.isBusinessDay(LocalDate(2026, 7, 9)), isTrue);
    expect(calendar.isBusinessDay(LocalDate(2025, 12, 31)), isTrue);
    expect(calendar.isBusinessDay(LocalDate(2024, 11, 20)), isFalse);
    expect(calendar.isBusinessDay(LocalDate(2023, 11, 20)), isTrue);
    expect(calendar.isBusinessDay(LocalDate(2027, 1, 4)), isNull);
  });
}
