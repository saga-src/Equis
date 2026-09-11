import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/budgets/budget_controller.dart';
import 'package:equis/presentation/budgets/budget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders warning, projection, and budget editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vaultId = EntityId.generate();
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final finance = LocalFinanceSnapshot(
      vault: VaultProfile(
        id: vaultId,
        name: 'Local',
        baseCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        createdAt: instant,
        updatedAt: instant,
      ),
    );
    final budget = BudgetDefinition(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Food plan',
      currency: CurrencyCode.brl,
      limitMinor: 10000,
      periodType: BudgetPeriodType.monthly,
      warningThresholdBps: 8000,
      scope: BudgetScope(),
      createdAt: instant,
      updatedAt: instant,
    );
    final progress = BudgetProgress(
      budget: budget,
      period: BudgetPeriod(
        start: LocalDate(2026, 8, 1),
        end: LocalDate(2026, 8, 31),
      ),
      usedMinor: 12000,
      projectedMinor: 18000,
      warningState: BudgetWarningState.exceeded,
      usageBps: 12000,
      missingRates: {CurrencyCode.usd},
      usesEstimatedRates: false,
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
          home: BudgetScreen(
            financeOverride: finance,
            stateOverride: BudgetState(items: [progress]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Food plan'), findsOneWidget);
    expect(find.text('Exceeded'), findsOneWidget);
    expect(find.text('Projected'), findsOneWidget);
    expect(find.textContaining('likely to be exceeded'), findsOneWidget);
    expect(find.textContaining('exchange rate is unavailable'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Add budget'));
    await tester.pumpAndSettle();
    expect(find.text('Budget name'), findsOneWidget);
    expect(find.text('Warning threshold (%)'), findsOneWidget);
    expect(find.text('Overall spending'), findsOneWidget);
  });
}
