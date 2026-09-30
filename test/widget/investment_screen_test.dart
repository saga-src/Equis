import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/investments/fixed_income_valuation.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/formatting/equis_formatters.dart';
import 'package:equis/presentation/investments/fixed_income_terms_form.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:equis/presentation/investments/investment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders portfolio performance, holding, and trade actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final vault = EntityId.generate();
    final instrument = InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vault,
      symbol: 'ACME3',
      name: 'Acme',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      exchange: 'B3',
      createdAt: instant,
      updatedAt: instant,
    );
    final report = PortfolioReport(
      currency: CurrencyCode.brl,
      marketValueMinor: 6000,
      costBasisMinor: 3630,
      unrealizedMinor: 2370,
      realizedMinor: 5180,
      incomeMinor: 500,
      holdings: [
        HoldingReport(
          instrument: instrument,
          quantity: Decimal.fromInt(3),
          costBasisMinor: 3630,
          averageCost: Decimal.parse('12.1'),
          realizedMinor: 5180,
          incomeMinor: 500,
          marketValueMinor: 6000,
          reportingMarketValueMinor: 6000,
          unrealizedMinor: 2370,
          allocationBps: 10000,
          price: InvestmentPrice(
            price: Decimal.fromInt(20),
            currency: CurrencyCode.brl,
            date: LocalDate(2026, 8, 18),
            manual: true,
          ),
          lots: const [],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: InvestmentScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vault,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: InvestmentState(
              report: report,
              lastRefresh: const MarketRefreshSummary(updated: 2, failed: 1),
              prices: [
                MarketPriceState(
                  instrument: instrument,
                  quote: MarketQuote(
                    instrumentId: instrument.id,
                    price: Decimal.fromInt(20),
                    currency: CurrencyCode.brl,
                    timestamp: instant,
                    provider: 'brapi',
                  ),
                  source: MarketPriceSource.automatic,
                  stale: true,
                  refreshFailed: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portfolio-value')), findsOneWidget);
    expect(find.textContaining('ACME3'), findsOneWidget);
    expect(find.text('Unrealized gain/loss'), findsOneWidget);
    expect(find.text('Add asset'), findsOneWidget);
    expect(
      find.text('The cached market price is out of date.'),
      findsOneWidget,
    );
    expect(
      find.text('Price refresh failed. The last local value is still in use.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Refresh market prices'), findsOneWidget);
    expect(find.byTooltip('About market data'), findsOneWidget);
    await tester.tap(find.byKey(const Key('market-data-info')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('market-data-info-dialog')), findsOneWidget);
    expect(find.text('Market data'), findsOneWidget);
    expect(find.textContaining('BRAPI for Brazilian assets'), findsOneWidget);
    expect(find.textContaining('not real-time quotes'), findsOneWidget);
    expect(
      find.text('Data provided by Twelve Data. Powered by CoinGecko.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('2 updated, 1 failed.'), findsOneWidget);
    expect(find.byKey(const Key('create-investment-account')), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Link market quote'), findsOneWidget);
    expect(find.text('Delete asset'), findsOneWidget);
    await tester.tap(find.text('Delete asset'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This is allowed only when the asset has no'),
      findsOneWidget,
    );
  });

  testWidgets('guides account setup and exposes asset currency', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final vault = EntityId.generate();
    final finance = LocalFinanceSnapshot(
      vault: VaultProfile(
        id: vault,
        name: 'Local',
        baseCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        createdAt: instant,
        updatedAt: instant,
      ),
    );
    final report = PortfolioReport(
      currency: CurrencyCode.brl,
      holdings: const [],
      marketValueMinor: 0,
      costBasisMinor: 0,
      unrealizedMinor: 0,
      realizedMinor: 0,
      incomeMinor: 0,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: InvestmentScreen(
            financeOverride: finance,
            stateOverride: InvestmentState(
              report: report,
              error: StateError('kept previous report'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up an investment account'), findsOneWidget);
    expect(
      find.text(
        'The investment action could not be completed. Check the values and required accounts.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('create-investment-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('brokerage-name')), findsOneWidget);
    expect(find.byKey(const Key('brokerage-currency')), findsOneWidget);
    expect(find.text('Brokerage account name'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add asset'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('instrument-currency')), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Search symbol or name'), findsOneWidget);
    expect(find.text('Add manually'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search symbol or name'),
      'PETR',
    );
    await tester.pump(const Duration(milliseconds: 349));
    expect(
      find.text('Market search failed. You can still add the asset manually.'),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(
      find.text('Market search failed. You can still add the asset manually.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('instrument-currency')));
    await tester.pumpAndSettle();
    expect(find.text('USD'), findsOneWidget);
  });

  testWidgets('buy and sell start with the latest recorded asset price', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final vault = EntityId.generate();
    final accountId = EntityId.generate();
    final instrument = InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vault,
      symbol: 'ACME3',
      name: 'Acme',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      exchange: 'B3',
      createdAt: instant,
      updatedAt: instant,
    );
    final report = PortfolioReport(
      currency: CurrencyCode.brl,
      marketValueMinor: 12000,
      costBasisMinor: 9000,
      unrealizedMinor: 3000,
      realizedMinor: 0,
      incomeMinor: 0,
      holdings: [
        HoldingReport(
          instrument: instrument,
          quantity: Decimal.fromInt(3),
          costBasisMinor: 9000,
          averageCost: Decimal.fromInt(30),
          realizedMinor: 0,
          incomeMinor: 0,
          marketValueMinor: 12000,
          reportingMarketValueMinor: 12000,
          unrealizedMinor: 3000,
          allocationBps: 10000,
          price: InvestmentPrice(
            price: Decimal.fromInt(40),
            currency: CurrencyCode.brl,
            date: LocalDate(2026, 9, 22),
            manual: true,
          ),
          lots: const [],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: InvestmentScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vault,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
              accounts: [
                AccountAggregate(
                  account: AccountProfile(
                    id: accountId,
                    vaultId: vault,
                    name: 'Brokerage',
                    type: AccountType.investment,
                    nature: AccountNature.asset,
                    createdAt: instant,
                    updatedAt: instant,
                  ),
                  pockets: [
                    AccountPocketProfile(
                      id: EntityId.generate(),
                      accountId: accountId,
                      currency: CurrencyCode.brl,
                      isDefault: true,
                    ),
                  ],
                ),
              ],
            ),
            stateOverride: InvestmentState(
              report: report,
              prices: [
                MarketPriceState(
                  instrument: instrument,
                  quote: MarketQuote(
                    instrumentId: instrument.id,
                    price: Decimal.parse('42.75'),
                    currency: CurrencyCode.brl,
                    timestamp: instant,
                    provider: 'brapi',
                  ),
                  source: MarketPriceSource.automatic,
                  stale: false,
                  refreshFailed: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final action in ['Buy', 'Sell']) {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Unit price'),
      );
      expect(field.controller?.text, '42.75');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('hides every allocation when one holding has an unknown value', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const locale = Locale('en', 'US');
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final vaultId = EntityId.generate();
    InvestmentInstrument instrument(
      String name,
      InvestmentAssetClass assetClass,
    ) => InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: name,
      assetClass: assetClass,
      currency: CurrencyCode.brl,
      createdAt: instant,
      updatedAt: instant,
    );
    final stock = instrument('Known stock', InvestmentAssetClass.stock);
    final fixed = instrument('Unknown CDB', InvestmentAssetClass.fixedIncome);
    HoldingReport holding(
      InvestmentInstrument asset,
      int? value,
      int allocation,
    ) => HoldingReport(
      instrument: asset,
      quantity: Decimal.one,
      costBasisMinor: 10000,
      averageCost: Decimal.fromInt(100),
      realizedMinor: 0,
      incomeMinor: 0,
      marketValueMinor: value,
      reportingMarketValueMinor: value,
      knownValueMinor: value,
      unrealizedMinor: null,
      allocationBps: allocation,
      price: null,
      lots: const [],
      hasIncompleteValuations: value == null,
    );
    final report = PortfolioReport(
      currency: CurrencyCode.brl,
      marketValueMinor: 10000,
      costBasisMinor: 20000,
      unrealizedMinor: 0,
      realizedMinor: 0,
      incomeMinor: 0,
      hasIncompleteValuations: true,
      holdings: [holding(stock, 10000, 10000), holding(fixed, null, 0)],
    );
    await tester.pumpWidget(
      _investmentApp(
        locale: locale,
        finance: _financeSnapshot(vaultId, instant, locale: locale),
        report: report,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Known stock'), findsOneWidget);
    expect(find.text('Unknown CDB'), findsOneWidget);
    expect(find.textContaining('Allocation:'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  for (final locale in const [Locale('en', 'US'), Locale('pt', 'BR')]) {
    testWidgets(
      'fixed income shows known subtotal, lot details, and manual actions (${locale.languageCode})',
      (tester) async {
        if (Platform.environment['EQUIS_P5_VISUAL_DIR'] != null) {
          final font = FontLoader('Roboto');
          font.addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
          await font.load();
        }
        await tester.binding.setSurfaceSize(const Size(1000, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final l = await AppLocalizations.delegate.load(locale);
        const instant = UtcInstant.fromEpochMicroseconds(1);
        final vaultId = EntityId.generate();
        final instrument = InvestmentInstrument(
          id: EntityId.generate(),
          vaultId: vaultId,
          name: 'LCI 12.08%',
          assetClass: InvestmentAssetClass.fixedIncome,
          currency: CurrencyCode.brl,
          createdAt: instant,
          updatedAt: instant,
        );
        final incompleteLot = InvestmentLot(
          id: EntityId.generate(),
          acquisitionEventId: EntityId.generate(),
          instrumentId: instrument.id,
          acquiredOn: LocalDate(2026, 8, 1),
          originalQuantity: Decimal.one,
          costBasisMinor: 50000,
          costCurrency: CurrencyCode.brl,
        );
        final manualLot = InvestmentLot(
          id: EntityId.generate(),
          acquisitionEventId: EntityId.generate(),
          instrumentId: instrument.id,
          acquiredOn: LocalDate(2026, 8, 12),
          originalQuantity: Decimal.one,
          costBasisMinor: 100000,
          costCurrency: CurrencyCode.brl,
        );
        final report = PortfolioReport(
          currency: CurrencyCode.brl,
          marketValueMinor: 100000,
          costBasisMinor: 150000,
          unrealizedMinor: 0,
          realizedMinor: 0,
          incomeMinor: 0,
          hasIncompleteValuations: true,
          holdings: [
            HoldingReport(
              instrument: instrument,
              quantity: Decimal.fromInt(2),
              costBasisMinor: 150000,
              averageCost: Decimal.fromInt(750),
              realizedMinor: 0,
              incomeMinor: 0,
              marketValueMinor: 100000,
              reportingMarketValueMinor: 100000,
              knownValueMinor: 100000,
              unrealizedMinor: null,
              allocationBps: 10000,
              price: null,
              lots: [
                LotPosition(
                  lot: incompleteLot,
                  disposedQuantity: Decimal.zero,
                  allocatedCostMinor: 0,
                ),
                LotPosition(
                  lot: manualLot,
                  disposedQuantity: Decimal.zero,
                  allocatedCostMinor: 0,
                ),
              ],
              lotValuations: [
                PositionValuation(
                  amountMinor: null,
                  currency: CurrencyCode.brl,
                  valueDate: LocalDate(2026, 9, 23),
                  calculatedAt: instant,
                  origin: ValuationOrigin.contractual,
                  state: ValuationState.incomplete,
                  source: 'contract+BCB_SGS:12',
                  missingPeriods: const [],
                ),
                PositionValuation(
                  amountMinor: 100000,
                  currency: CurrencyCode.brl,
                  valueDate: LocalDate(2026, 9, 20),
                  calculatedAt: instant,
                  origin: ValuationOrigin.manual,
                  state: ValuationState.current,
                  source: 'user_manual',
                  missingPeriods: const [],
                ),
              ],
              hasIncompleteValuations: true,
            ),
          ],
        );
        final finance = _financeSnapshot(vaultId, instant, locale: locale);

        await tester.pumpWidget(
          _investmentApp(locale: locale, finance: finance, report: report),
        );
        await tester.pumpAndSettle();

        expect(find.text(l.fixedIncomeKnownSubtotalLabel), findsWidgets);
        final valueContext = tester.element(
          find.byKey(const Key('portfolio-value')),
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('portfolio-value'))).data,
          EquisFormatters.moneyMinor(
            valueContext,
            currency: CurrencyCode.brl,
            minor: 100000,
          ),
        );
        expect(find.text(l.fixedIncomeIncompleteLabel), findsWidgets);
        expect(find.text(l.missingMarketPriceMessage), findsNothing);

        final lotsKey = Key('fixed-income-lots-${instrument.id.value}');
        await tester.tap(find.byKey(lotsKey));
        await tester.pumpAndSettle();
        await _captureVisual(tester, locale, 'incomplete-manual');
        final incompleteTile = find.byKey(
          Key('fixed-income-lot-${incompleteLot.id.value}'),
        );
        final manualTile = find.byKey(
          Key('fixed-income-lot-${manualLot.id.value}'),
        );
        expect(incompleteTile, findsOneWidget);
        expect(manualTile, findsOneWidget);
        expect(
          find.text(
            '${l.fixedIncomeSourceLabel}: ${l.fixedIncomeContractSourceLabel} 12',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            '${l.fixedIncomeSourceLabel}: ${l.fixedIncomeManualBalanceLabel}',
          ),
          findsOneWidget,
        );
        expect(find.text(l.fixedIncomeCachedDataNotice), findsOneWidget);
        expect(find.text(l.fixedIncomeDatedManualNotice), findsOneWidget);
        final incompleteContext = tester.element(incompleteTile);
        final acquiredDate = EquisFormatters.date(
          incompleteContext,
          LocalDate(2026, 8, 1),
        );
        final incompleteValueDate = EquisFormatters.date(
          incompleteContext,
          LocalDate(2026, 9, 23),
        );
        expect(find.textContaining(acquiredDate), findsWidgets);
        expect(
          find.text('${l.fixedIncomeValueDateLabel}: $incompleteValueDate'),
          findsOneWidget,
        );
        expect(
          find.text(l.fixedIncomeNoRedemptionQuoteNotice),
          findsNWidgets(2),
        );
        await tester.tap(
          find.descendant(
            of: incompleteTile,
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.fixedIncomeEditManualAction), findsOneWidget);
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();

        final manualContext = tester.element(manualTile);
        final manualDate = EquisFormatters.date(
          manualContext,
          LocalDate(2026, 9, 20),
        );
        expect(
          find.text('${l.fixedIncomeValueDateLabel}: $manualDate'),
          findsOneWidget,
        );
        expect(
          find.text(
            '${l.fixedIncomeManualBalanceLabel}: ${EquisFormatters.moneyMinor(manualContext, currency: CurrencyCode.brl, minor: 100000)}',
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(manualTile);
        await tester.tap(
          find.descendant(
            of: manualTile,
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.fixedIncomeEditTermsAction), findsOneWidget);
        expect(find.text(l.fixedIncomeSetManualAction), findsOneWidget);
        expect(find.text(l.fixedIncomeEditManualAction), findsOneWidget);
        expect(find.text(l.fixedIncomeRemoveManualAction), findsOneWidget);
      },
    );

    testWidgets(
      'fixed income creation skips market search and buying requires contract terms (${locale.languageCode})',
      (tester) async {
        if (Platform.environment['EQUIS_P5_VISUAL_DIR'] != null) {
          final font = FontLoader('Roboto');
          font.addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
          await font.load();
        }
        await tester.binding.setSurfaceSize(const Size(1000, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final l = await AppLocalizations.delegate.load(locale);
        const instant = UtcInstant.fromEpochMicroseconds(1);
        final vaultId = EntityId.generate();
        final emptyReport = PortfolioReport(
          currency: CurrencyCode.brl,
          holdings: const [],
          marketValueMinor: 0,
          costBasisMinor: 0,
          unrealizedMinor: 0,
          realizedMinor: 0,
          incomeMinor: 0,
        );
        final finance = _financeSnapshot(vaultId, instant, locale: locale);
        await tester.pumpWidget(
          _investmentApp(locale: locale, finance: finance, report: emptyReport),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(l.addInstrumentAction));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byType(DropdownButtonFormField<InvestmentAssetClass>),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(l.investmentAssetClassLabel('fixedIncome')).last,
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextField, l.assetSearchLabel),
          findsNothing,
        );
        expect(find.text(l.addAssetManuallyAction), findsNothing);

        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(find.byType(FixedIncomeTermsForm), findsOneWidget);
        expect(find.text(l.fixedIncomeProductLabel), findsOneWidget);
        await tester.tap(find.text(l.cancelAction));
        await tester.pumpAndSettle();

        final accountId = EntityId.generate();
        final instrument = InvestmentInstrument(
          id: EntityId.generate(),
          vaultId: vaultId,
          name: 'CRI CDI + 1.2%',
          assetClass: InvestmentAssetClass.fixedIncome,
          currency: CurrencyCode.brl,
          createdAt: instant,
          updatedAt: instant,
        );
        final lot = InvestmentLot(
          id: EntityId.generate(),
          acquisitionEventId: EntityId.generate(),
          instrumentId: instrument.id,
          acquiredOn: LocalDate(2026, 1, 15),
          originalQuantity: Decimal.fromInt(2),
          costBasisMinor: 200000,
          costCurrency: CurrencyCode.brl,
        );
        final report = PortfolioReport(
          currency: CurrencyCode.brl,
          marketValueMinor: 250123,
          costBasisMinor: 200000,
          unrealizedMinor: 50123,
          realizedMinor: 0,
          incomeMinor: 0,
          holdings: [
            HoldingReport(
              instrument: instrument,
              quantity: Decimal.fromInt(2),
              costBasisMinor: 200000,
              averageCost: Decimal.fromInt(1000),
              realizedMinor: 0,
              incomeMinor: 0,
              marketValueMinor: 250123,
              reportingMarketValueMinor: 250123,
              unrealizedMinor: 50123,
              allocationBps: 10000,
              price: null,
              lots: [
                LotPosition(
                  lot: lot,
                  disposedQuantity: Decimal.zero,
                  allocatedCostMinor: 0,
                ),
              ],
              lotValuations: [
                PositionValuation(
                  amountMinor: 250123,
                  currency: CurrencyCode.brl,
                  valueDate: LocalDate(2026, 9, 23),
                  calculatedAt: instant,
                  origin: ValuationOrigin.contractual,
                  state: ValuationState.current,
                  source: 'contract',
                  missingPeriods: const [],
                ),
              ],
            ),
          ],
        );
        final financeWithPocket = _financeSnapshot(
          vaultId,
          instant,
          locale: locale,
          accountId: accountId,
        );
        await tester.pumpWidget(
          _investmentApp(
            locale: locale,
            finance: financeWithPocket,
            report: report,
          ),
        );
        await tester.pumpAndSettle();
        if (Platform.environment['EQUIS_P5_VISUAL_DIR'] != null) {
          await tester.tap(
            find.byKey(Key('fixed-income-lots-${instrument.id.value}')),
          );
          await tester.pumpAndSettle();
          await _captureVisual(tester, locale, 'current');
        }
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.buyInvestmentAction));
        await tester.pumpAndSettle();

        expect(find.byType(FixedIncomeTermsForm), findsOneWidget);
        final unitPrice = tester.widget<TextField>(
          find.widgetWithText(TextField, l.unitPriceLabel),
        );
        expect(unitPrice.controller?.text, isEmpty);
      },
    );
  }
}

Future<void> _captureVisual(
  WidgetTester tester,
  Locale locale,
  String state,
) async {
  final captureDir = Platform.environment['EQUIS_P5_VISUAL_DIR'];
  if (captureDir == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('investment-visual-boundary')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$captureDir/p5-$state-${locale.languageCode}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

LocalFinanceSnapshot _financeSnapshot(
  EntityId vaultId,
  UtcInstant instant, {
  required Locale locale,
  EntityId? accountId,
}) {
  return LocalFinanceSnapshot(
    vault: VaultProfile(
      id: vaultId,
      name: 'Local',
      baseCurrency: CurrencyCode.brl,
      locale: locale.toLanguageTag(),
      timezone: 'UTC',
      createdAt: instant,
      updatedAt: instant,
    ),
    accounts: accountId == null
        ? const []
        : [
            AccountAggregate(
              account: AccountProfile(
                id: accountId,
                vaultId: vaultId,
                name: 'Brokerage',
                type: AccountType.investment,
                nature: AccountNature.asset,
                createdAt: instant,
                updatedAt: instant,
              ),
              pockets: [
                AccountPocketProfile(
                  id: EntityId.generate(),
                  accountId: accountId,
                  currency: CurrencyCode.brl,
                  isDefault: true,
                ),
              ],
            ),
          ],
  );
}

Widget _investmentApp({
  required Locale locale,
  required LocalFinanceSnapshot finance,
  required PortfolioReport report,
}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: RepaintBoundary(
      key: const Key('investment-visual-boundary'),
      child: InvestmentScreen(
        financeOverride: finance,
        stateOverride: InvestmentState(report: report),
      ),
    ),
  ),
);
