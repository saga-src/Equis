final class LocalDate implements Comparable<LocalDate> {
  factory LocalDate(int year, int month, int day) {
    final candidate = DateTime.utc(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      throw ArgumentError.value(
        '$year-$month-$day',
        'date',
        'Invalid calendar date.',
      );
    }
    return LocalDate._(year, month, day);
  }

  factory LocalDate.parse(String value) {
    if (value.length != 10 ||
        value.codeUnitAt(4) != 45 ||
        value.codeUnitAt(7) != 45) {
      throw FormatException('LocalDate must use YYYY-MM-DD.', value);
    }
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) {
      throw FormatException('LocalDate must use YYYY-MM-DD.', value);
    }
    return LocalDate(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  DateTime toUtcDate() => DateTime.utc(year, month, day);

  LocalDate addDays(int days) {
    final value = toUtcDate().add(Duration(days: days));
    return LocalDate(value.year, value.month, value.day);
  }

  @override
  int compareTo(LocalDate other) => toString().compareTo(other.toString());

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
