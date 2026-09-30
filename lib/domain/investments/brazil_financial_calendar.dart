import '../shared/local_date.dart';
import 'fixed_income_valuation.dart';

/// Financial-operation calendar derived from CMN 4.880/2020, national
/// holidays, and the annual public holiday ordinances. Its bounded version
/// was checked against the published SGS 11/12 dates from 2021 through
/// 2026-09-23. Future dates are expected business days under those rules;
/// an unpublished rate still makes valuation incomplete.
final class BrazilFinancialCalendar implements BusinessCalendar {
  const BrazilFinancialCalendar();

  static const currentVersion = 'BR-CMN4880-SGS11-12-2021-2026-v1';

  @override
  String get version => currentVersion;

  @override
  bool? isBusinessDay(LocalDate date) {
    if (date.year < 2021 || date.year > 2026) return null;
    if (date.toUtcDate().weekday >= DateTime.saturday) return false;
    if (_nationalHolidays.contains(date.month * 100 + date.day)) return false;
    if (date.year >= 2024 && date.month == 11 && date.day == 20) return false;
    final easter = LocalDate.parse(_easterDates[date.year]!);
    return date != easter.addDays(-48) &&
        date != easter.addDays(-47) &&
        date != easter.addDays(-2) &&
        date != easter.addDays(60);
  }

  // 20 November became a national holiday in 2024. Neither 24 nor 31
  // December is excluded: both daily SGS series have published on those
  // weekdays, including 2025-12-31.
  static const _nationalHolidays = <int>{
    101,
    421,
    501,
    907,
    1012,
    1102,
    1115,
    1225,
  };

  // Easter anchors from the corresponding public annual holiday ordinances;
  // Good Friday, Carnival and Corpus Christi are derived from these dates.
  static const _easterDates = <int, String>{
    2021: '2021-04-04',
    2022: '2022-04-17',
    2023: '2023-04-09',
    2024: '2024-03-31',
    2025: '2025-04-20',
    2026: '2026-04-05',
  };
}
