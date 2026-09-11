import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'local_date.dart';

final class ZonedRecurrenceClock {
  ZonedRecurrenceClock._();

  static bool _initialized = false;

  static void initialize() {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
  }

  static DateTime resolveUtc({
    required LocalDate date,
    required int hour,
    required int minute,
    required String timezone,
  }) {
    initialize();
    if (hour < 0 || hour > 23) {
      throw RangeError.range(hour, 0, 23, 'hour');
    }
    if (minute < 0 || minute > 59) {
      throw RangeError.range(minute, 0, 59, 'minute');
    }
    final location = tz.getLocation(timezone);
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).toUtc();
  }
}
