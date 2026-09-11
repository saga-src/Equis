import 'package:decimal/decimal.dart';

import 'currency.dart';
import 'decimal_value.dart';

final class Money {
  Money({required this.currency, required this.minorUnits}) {
    _checkInt64(minorUnits);
  }

  factory Money.fromMajor({
    required CurrencyDefinition currency,
    required Decimal majorUnits,
  }) {
    currency.validate();
    final scaled = DecimalValue.round(
      majorUnits.shift(currency.minorUnits),
      scale: 0,
    ).toBigInt();
    if (scaled < BigInt.from(minInt64) || scaled > BigInt.from(maxInt64)) {
      throw RangeError('Monetary value does not fit signed int64.');
    }
    return Money(currency: currency.code, minorUnits: scaled.toInt());
  }

  static const int minInt64 = -9223372036854775808;
  static const int maxInt64 = 9223372036854775807;

  final CurrencyCode currency;
  final int minorUnits;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(
      currency: currency,
      minorUnits: _checkedResult(
        BigInt.from(minorUnits) + BigInt.from(other.minorUnits),
      ),
    );
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(
      currency: currency,
      minorUnits: _checkedResult(
        BigInt.from(minorUnits) - BigInt.from(other.minorUnits),
      ),
    );
  }

  Money operator -() {
    if (minorUnits == minInt64) {
      throw RangeError('Negated monetary value does not fit signed int64.');
    }
    return Money(currency: currency, minorUnits: -minorUnits);
  }

  Decimal toMajor(int currencyMinorUnits) {
    if (currencyMinorUnits < 0 || currencyMinorUnits > 9) {
      throw RangeError.range(currencyMinorUnits, 0, 9, 'currencyMinorUnits');
    }
    return Decimal.fromInt(minorUnits).shift(-currencyMinorUnits);
  }

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot combine $currency and ${other.currency}.');
    }
  }

  static void _checkInt64(int value) {
    if (value < minInt64 || value > maxInt64) {
      throw RangeError.range(value, minInt64, maxInt64, 'minorUnits');
    }
  }

  static int _checkedResult(BigInt value) {
    if (value < BigInt.from(minInt64) || value > BigInt.from(maxInt64)) {
      throw RangeError('Monetary result does not fit signed int64.');
    }
    return value.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.currency == currency &&
      other.minorUnits == minorUnits;

  @override
  int get hashCode => Object.hash(currency, minorUnits);

  @override
  String toString() => '$currency $minorUnits';
}
