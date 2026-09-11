final class CurrencyCode {
  factory CurrencyCode(String value) {
    final canonical = value.toUpperCase();
    if (canonical.length != 3 ||
        canonical.codeUnits.any((unit) => unit < 65 || unit > 90)) {
      throw FormatException(
        'Currency must be a three-letter ISO-4217 code.',
        value,
      );
    }
    return CurrencyCode._(canonical);
  }

  const CurrencyCode._(this.value);

  static final brl = CurrencyCode('BRL');
  static final usd = CurrencyCode('USD');

  final String value;

  @override
  bool operator ==(Object other) =>
      other is CurrencyCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class CurrencyDefinition {
  const CurrencyDefinition({required this.code, required this.minorUnits});

  final CurrencyCode code;
  final int minorUnits;

  void validate() {
    if (minorUnits < 0 || minorUnits > 9) {
      throw RangeError.range(minorUnits, 0, 9, 'minorUnits');
    }
  }
}
