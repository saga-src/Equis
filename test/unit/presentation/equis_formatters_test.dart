import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/presentation/formatting/equis_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('formats exact minor units and dates for en-US', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'US'), Locale('pt', 'BR')],
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      EquisFormatters.moneyMinor(
        context,
        currency: CurrencyCode.usd,
        minor: -9223372036854775807,
      ),
      r'-$92,233,720,368,547,758.07',
    );
    expect(EquisFormatters.date(context, LocalDate(2026, 8, 22)), '8/22/2026');
    expect(EquisFormatters.percentFromBasisPoints(context, 1250), '12.5%');
  });

  testWidgets('formats exact minor units and dates for pt-BR', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en', 'US'), Locale('pt', 'BR')],
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      EquisFormatters.moneyMinor(
        context,
        currency: CurrencyCode.brl,
        minor: 123456789,
      ),
      contains('1.234.567,89'),
    );
    expect(EquisFormatters.date(context, LocalDate(2026, 8, 22)), '22/08/2026');
    expect(EquisFormatters.percentFromBasisPoints(context, 1250), '12,5%');
  });
}
