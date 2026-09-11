import 'package:decimal/decimal.dart';

/// The sole conversion boundary for persisted high-precision numbers.
final class DecimalValue {
  DecimalValue._();

  static Decimal parse(String source) {
    final value = Decimal.tryParse(source);
    if (value == null) {
      throw FormatException('Invalid decimal value.', source);
    }
    return value;
  }

  /// Returns a non-exponential, normalized representation suitable for SQLite.
  static String canonical(Decimal value) => value.toString();

  /// Rounds to the nearest value, with exact halves away from zero.
  static Decimal round(Decimal value, {required int scale}) {
    if (scale < 0) {
      throw RangeError.value(scale, 'scale', 'must not be negative');
    }
    return value.round(scale: scale);
  }
}
