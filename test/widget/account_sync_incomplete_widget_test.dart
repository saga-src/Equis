import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/wealth/net_worth_models.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:equis/presentation/investments/investment_screen.dart';
import 'package:equis/presentation/wealth/wealth_controller.dart';
import 'package:equis/presentation/wealth/wealth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['en', 'pt']) {
    final message = language == 'en'
        ? 'Known subtotal: some account data is waiting for a sync conflict to be resolved.'
        : 'Subtotal conhecido: há dados de contas aguardando a resolução de um conflito de sincronização.';
    final subtotal = language == 'en'
        ? 'Known net worth (partial)'
        : 'Patrimônio conhecido (parcial)';

    testWidgets(
      'home marks unavailable account data as subtotal in $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final finance = _finance();
        final wealth = _wealth();
        final dashboard = DashboardSnapshot(
          reportingCurrency: CurrencyCode.brl,
          periodStart: LocalDate(2026, 9, 1),
          periodEnd: LocalDate(2026, 9, 30),
          availableMoneyMinor: 0,
          incomeMinor: 0,
          expenseMinor: 0,
          spendingByCategory: const [],
          cashFlow: const [],
          accountBalances: const [],
          missingRates: const {},
          usesEstimatedRates: false,
          upcomingCount: 0,
          hasIncompleteAccounts: true,
        );
        await tester.pumpWidget(
          ProviderScope(
            child: _app(
              language,
              Scaffold(
                body: SingleChildScrollView(
                  child: DashboardOverview(
                    finance: finance,
                    reportOverride: dashboard,
                    wealthStateOverride: WealthState(report: wealth),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('available-money-incomplete')),
          findsOneWidget,
        );
        expect(find.text(message), findsNWidgets(2));
        expect(find.text(subtotal), findsOneWidget);
        expect(find.byIcon(Icons.verified_outlined), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('wealth marks zero known balance as partial in $language', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            language,
            WealthScreen(
              financeOverride: _finance(),
              stateOverride: WealthState(report: _wealth()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(subtotal), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const Key('net-worth-total')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('portfolio marks an account sync gap in $language', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final report = PortfolioReport(
        currency: CurrencyCode.brl,
        holdings: const [],
        marketValueMinor: 0,
        costBasisMinor: 0,
        unrealizedMinor: 0,
        realizedMinor: 0,
        incomeMinor: 0,
        hasIncompleteAccountSync: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            language,
            InvestmentScreen(
              financeOverride: _finance(),
              stateOverride: InvestmentState(report: report),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const Key('portfolio-value')), findsOneWidget);
      expect(
        find.text(
          language == 'en'
              ? 'Known investment subtotal'
              : 'Subtotal conhecido dos investimentos',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(String language, Widget child) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

LocalFinanceSnapshot _finance() => LocalFinanceSnapshot(
  vault: VaultProfile(
    id: EntityId.generate(),
    name: 'Local',
    baseCurrency: CurrencyCode.brl,
    locale: 'en-US',
    timezone: 'UTC',
    createdAt: const UtcInstant.fromEpochMicroseconds(1),
    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
  ),
);

NetWorthReport _wealth() {
  final point = NetWorthPoint(
    date: LocalDate(2026, 9, 28),
    assetsMinor: 0,
    liabilitiesMinor: 0,
    missingRates: const {},
    usesEstimatedRates: false,
    hasIncompleteAccounts: true,
  );
  return NetWorthReport(
    currency: CurrencyCode.brl,
    current: point,
    history: [point],
    physicalAssets: const [],
  );
}
