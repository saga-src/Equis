import 'package:decimal/decimal.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:equis/presentation/investments/investment_screen.dart';
import 'package:flutter/material.dart';
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
}
