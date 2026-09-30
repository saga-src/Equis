import 'package:decimal/decimal.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/investments/brazil_financial_calendar.dart';
import 'package:equis/domain/investments/fixed_income_contract.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/investments/fixed_income_terms_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpForm(
    WidgetTester tester,
    GlobalKey<FixedIncomeTermsFormState> key, {
    required Locale locale,
    FixedIncomeTerms? initial,
    String product = 'LCI',
    CurrencyCode? currency,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: FixedIncomeTermsForm(
              key: key,
              currency: currency ?? CurrencyCode.brl,
              acquiredOn: LocalDate(2025, 1, 2),
              defaultProductName: product,
              initial: initial,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseMode(WidgetTester tester, String label) async {
    final dropdown = find.byKey(const Key('fixed-income-mode'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('English fixed 12.08% produces an annual rate of 0.1208', (
    tester,
  ) async {
    final key = GlobalKey<FixedIncomeTermsFormState>();
    await pumpForm(tester, key, locale: const Locale('en', 'US'));
    await tester.enterText(
      find.byKey(const Key('fixed-income-principal')),
      '1000.00',
    );
    await tester.enterText(find.byKey(const Key('fixed-income-rate')), '12.08');
    final terms = key.currentState!.buildTerms();
    expect(terms, isNotNull);
    expect(terms!.productName, 'LCI');
    expect(terms.principal, Decimal.parse('1000'));
    expect(terms.annualRate, Decimal.parse('0.1208'));
    expect(terms.dayCountBasis, 365);
  });

  testWidgets('Portuguese CDI multipliers preserve 20, 118 and 119 percent', (
    tester,
  ) async {
    final key = GlobalKey<FixedIncomeTermsFormState>();
    await pumpForm(tester, key, locale: const Locale('pt', 'BR'));
    await tester.enterText(
      find.byKey(const Key('fixed-income-principal')),
      '1000,00',
    );
    await chooseMode(tester, 'Percentual do índice diário');
    expect(find.text('Percentual do índice (ex.: 118)'), findsOneWidget);
    for (final entry in <String, String>{
      '20': '0.2',
      '118': '1.18',
      '119': '1.19',
    }.entries) {
      await tester.enterText(
        find.byKey(const Key('fixed-income-multiplier')),
        entry.key,
      );
      final terms = key.currentState!.buildTerms();
      expect(terms, isNotNull);
      expect(terms!.indexCode, EconomicSeriesCode.cdiDaily);
      expect(terms.indexMultiplier, Decimal.parse(entry.value));
      expect(terms.calendarVersion, BrazilFinancialCalendar.currentVersion);
    }
  });

  testWidgets('CDI plus 1.2 points uses spread, not a CDI multiplier', (
    tester,
  ) async {
    final key = GlobalKey<FixedIncomeTermsFormState>();
    await pumpForm(
      tester,
      key,
      locale: const Locale('en', 'US'),
      product: 'CRI',
    );
    await tester.enterText(
      find.byKey(const Key('fixed-income-principal')),
      '500',
    );
    await chooseMode(tester, 'Daily index + annual spread');
    await tester.enterText(find.byKey(const Key('fixed-income-spread')), '1.2');
    final terms = key.currentState!.buildTerms();
    expect(terms, isNotNull);
    expect(terms!.mode, FixedIncomeRemunerationMode.dailyIndexSpread);
    expect(terms.indexCode, EconomicSeriesCode.cdiDaily);
    expect(terms.annualSpread, Decimal.parse('0.012'));
    expect(terms.indexMultiplier, isNull);
    expect(terms.dayCountBasis, 252);
  });

  testWidgets('monthly index uses anniversary and publication lag', (
    tester,
  ) async {
    final key = GlobalKey<FixedIncomeTermsFormState>();
    await pumpForm(tester, key, locale: const Locale('en', 'US'));
    await tester.enterText(
      find.byKey(const Key('fixed-income-principal')),
      '750',
    );
    await chooseMode(tester, 'Monthly index + optional spread');
    await tester.enterText(
      find.byKey(const Key('fixed-income-anniversary')),
      '15',
    );
    await tester.enterText(find.byKey(const Key('fixed-income-lag')), '2');
    await tester.enterText(find.byKey(const Key('fixed-income-spread')), '1.5');
    final terms = key.currentState!.buildTerms();
    expect(terms, isNotNull);
    expect(terms!.indexCode, EconomicSeriesCode.ipcaMonthly);
    expect(terms.anniversaryDay, 15);
    expect(terms.publicationLagMonths, 2);
    expect(terms.annualSpread, Decimal.parse('0.015'));
  });

  testWidgets('invalid amounts, dates and rates show localized field errors', (
    tester,
  ) async {
    final key = GlobalKey<FixedIncomeTermsFormState>();
    await pumpForm(tester, key, locale: const Locale('pt', 'BR'));
    await tester.enterText(
      find.byKey(const Key('fixed-income-principal')),
      '0',
    );
    await tester.enterText(find.byKey(const Key('fixed-income-rate')), 'abc');
    await tester.enterText(
      find.byKey(const Key('fixed-income-maturity')),
      '2024-12-31',
    );
    expect(key.currentState!.buildTerms(), isNull);
    await tester.pump();
    expect(find.text('Informe um principal maior que zero.'), findsOneWidget);
    expect(
      find.text('A data não pode ser anterior ao início do rendimento.'),
      findsOneWidget,
    );
    expect(
      find.text('Informe um percentual válido (maior que -100%).'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Brazilian index formulas require BRL; USD fixed and manual work',
    (tester) async {
      final key = GlobalKey<FixedIncomeTermsFormState>();
      await pumpForm(
        tester,
        key,
        locale: const Locale('en', 'US'),
        currency: CurrencyCode.usd,
      );
      await tester.enterText(
        find.byKey(const Key('fixed-income-principal')),
        '100',
      );
      await chooseMode(tester, 'Percentage of daily index');
      await tester.enterText(
        find.byKey(const Key('fixed-income-multiplier')),
        '118',
      );
      expect(key.currentState!.buildTerms(), isNull);
      await tester.pump();
      expect(
        find.text('Brazilian index formulas require BRL.'),
        findsOneWidget,
      );

      await chooseMode(tester, 'Fixed annual rate');
      await tester.enterText(find.byKey(const Key('fixed-income-rate')), '5');
      expect(key.currentState!.buildTerms()!.currency, CurrencyCode.usd);

      await chooseMode(tester, 'Manual balance only');
      final manual = key.currentState!.buildTerms();
      expect(manual!.mode, FixedIncomeRemunerationMode.manualOnly);
      expect(manual.currency, CurrencyCode.usd);
    },
  );
}
