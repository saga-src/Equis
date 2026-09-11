import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';

abstract final class EquisFormatters {
  static String moneyMinor(
    BuildContext context, {
    required CurrencyCode currency,
    required int minor,
    int decimalDigits = 2,
  }) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final scale = _powerOfTen(decimalDigits);
    final absolute = minor.abs();
    final whole = absolute ~/ scale;
    final fraction = (absolute % scale).toString().padLeft(decimalDigits, '0');
    final numberFormat = NumberFormat.decimalPattern(locale);
    final localizedNumber = decimalDigits == 0
        ? numberFormat.format(whole)
        : '${numberFormat.format(whole)}'
              '${numberFormat.symbols.DECIMAL_SEP}$fraction';
    final currencyFormat = NumberFormat.simpleCurrency(
      locale: locale,
      name: currency.value,
      decimalDigits: 0,
    );
    final template = currencyFormat.format(minor < 0 ? -1 : 1);
    final needle = numberFormat.format(1);
    return template.replaceFirst(needle, localizedNumber);
  }

  static String date(BuildContext context, LocalDate value) => DateFormat.yMd(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(value.toUtcDate());

  static String dateRange(
    BuildContext context,
    LocalDate start,
    LocalDate end,
  ) => '${date(context, start)} – ${date(context, end)}';

  static String integer(BuildContext context, int value) =>
      NumberFormat.decimalPattern(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(value);

  static String percentFromBasisPoints(BuildContext context, int basisPoints) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return NumberFormat.decimalPercentPattern(
      locale: locale,
      decimalDigits: basisPoints % 100 == 0 ? 0 : 1,
    ).format(basisPoints / 10000);
  }

  static int _powerOfTen(int exponent) {
    if (exponent < 0 || exponent > 9) {
      throw RangeError.range(exponent, 0, 9, 'decimalDigits');
    }
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
