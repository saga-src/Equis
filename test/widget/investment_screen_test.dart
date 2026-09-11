import 'package:decimal/decimal.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
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
    expect(find.text('Add instrument'), findsOneWidget);
    expect(
      find.text('The cached market price is out of date.'),
      findsOneWidget,
    );
    expect(
      find.text('Price refresh failed. The last local value is still in use.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Refresh market prices'), findsOneWidget);
  });
}
