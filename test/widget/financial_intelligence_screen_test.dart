import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/intelligence/financial_intelligence_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/intelligence/financial_intelligence_controller.dart';
import 'package:equis/presentation/intelligence/financial_intelligence_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders local privacy disclosure and traceable formula', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final report = FinancialIntelligenceReport(
      enabled: true,
      asOf: LocalDate(2026, 8, 15),
      currency: CurrencyCode.brl,
      insights: [
        FinancialInsight(
          kind: FinancialInsightKind.spendingTrend,
          severity: FinancialInsightSeverity.caution,
          metrics: const {
            'current_minor': 120000,
            'projected_minor': 248000,
            'previous_minor': 100000,
            'delta_bps': 14800,
            'elapsed_days': 15,
            'period_days': 31,
          },
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
          home: FinancialIntelligenceScreen(
            financeOverride: LocalFinanceSnapshot(
              vault: VaultProfile(
                id: vaultId,
                name: 'Local',
                baseCurrency: CurrencyCode.brl,
                locale: 'en-US',
                timezone: 'UTC',
                createdAt: instant,
                updatedAt: instant,
              ),
            ),
            stateOverride: FinancialIntelligenceState(report: report),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-intelligence-privacy')), findsOneWidget);
    expect(find.byKey(const Key('insight-spendingTrend')), findsOneWidget);
    expect(
      find.textContaining('Transaction history is not sent'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('insight-spendingTrend')));
    await tester.pumpAndSettle();
    expect(find.text('How this was estimated'), findsOneWidget);
    expect(find.textContaining('15 × 31'), findsOneWidget);
  });
}
