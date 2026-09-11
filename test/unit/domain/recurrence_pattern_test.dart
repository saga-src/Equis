import 'package:equis/domain/recurring/recurrence_models.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily, weekly, and custom intervals are deterministic', () {
    expect(
      const RecurrencePattern(
        frequency: RecurrenceFrequency.daily,
        interval: 3,
      ).between(
        anchor: LocalDate(2026, 1, 1),
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 1, 10),
        limit: 10,
      ),
      [
        LocalDate(2026, 1, 1),
        LocalDate(2026, 1, 4),
        LocalDate(2026, 1, 7),
        LocalDate(2026, 1, 10),
      ],
    );
    expect(
      const RecurrencePattern(
        frequency: RecurrenceFrequency.weekly,
        interval: 2,
      ).occurrenceAt(LocalDate(2026, 1, 5), 2),
      LocalDate(2026, 2, 2),
    );
  });

  test('month-end uses the anchor day without cumulative drift', () {
    const pattern = RecurrencePattern(frequency: RecurrenceFrequency.monthly);
    final anchor = LocalDate(2025, 1, 31);
    expect(
      [
        for (var index = 0; index < 4; index++)
          pattern.occurrenceAt(anchor, index),
      ],
      [
        LocalDate(2025, 1, 31),
        LocalDate(2025, 2, 28),
        LocalDate(2025, 3, 31),
        LocalDate(2025, 4, 30),
      ],
    );
  });

  test('yearly leap-day recurrence returns to February 29 in leap years', () {
    const pattern = RecurrencePattern(frequency: RecurrenceFrequency.yearly);
    final anchor = LocalDate(2024, 2, 29);
    expect(pattern.occurrenceAt(anchor, 1), LocalDate(2025, 2, 28));
    expect(pattern.occurrenceAt(anchor, 4), LocalDate(2028, 2, 29));
  });

  test('RRULE subset round-trips frequency and interval', () {
    const pattern = RecurrencePattern(
      frequency: RecurrenceFrequency.monthly,
      interval: 3,
    );
    expect(
      RecurrencePattern.parse(
        pattern.serialize(LocalDate(2026, 8, 31)),
      ).interval,
      3,
    );
    expect(
      RecurrencePattern.parse('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29').frequency,
      RecurrenceFrequency.yearly,
    );
  });
}
