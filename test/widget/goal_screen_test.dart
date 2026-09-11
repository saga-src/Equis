import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/goals/cash_flow_projection.dart';
import 'package:equis/domain/goals/goal_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/goals/goal_controller.dart';
import 'package:equis/presentation/goals/goal_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders goal calculations and estimated future cash flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
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
    final goal = GoalDefinition(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Emergency fund',
      type: GoalType.emergencyFund,
      currency: CurrencyCode.brl,
      targetMinor: 3000000,
      targetDate: LocalDate(2028, 6, 30),
      plannedMonthlyMinor: 120000,
      trackingMode: GoalTrackingMode.manual,
      priority: 10,
      accountPocketIds: const {},
      createdAt: instant,
      updatedAt: instant,
    );
    final progress = GoalProgress(
      goal: goal,
      currentMinor: 850000,
      progressBps: 2833,
      requiredMonthlyMinor: 100000,
      expectedCompletionDate: LocalDate(2028, 2, 29),
      missingRates: const {},
      usesEstimatedRates: false,
    );
    final source = EntityId.generate();
    final projection = CashFlowProjection(
      reportingCurrency: CurrencyCode.brl,
      from: LocalDate(2026, 8, 19),
      through: LocalDate(2026, 11, 17),
      openingAvailableMinor: 100000,
      closingProjectedMinor: 95000,
      events: [
        ProjectedCashFlowEvent(
          sourceId: source,
          type: CashFlowEventType.installment,
          date: LocalDate(2026, 9, 3),
          amountMinor: -5000,
          balanceAfterMinor: 95000,
          name: 'Course',
        ),
      ],
      missingRates: const {},
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
          home: GoalScreen(
            financeOverride: finance,
            stateOverride: GoalState(items: [progress], cashFlow: projection),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Emergency fund'), findsOneWidget);
    expect(find.text('Required monthly contribution'), findsOneWidget);
    expect(find.text('Estimated completion'), findsOneWidget);
    expect(find.text('Add contribution'), findsOneWidget);

    await tester.tap(find.text('Future cash flow'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not a guaranteed future balance'),
      findsOneWidget,
    );
    expect(find.text('Course'), findsOneWidget);
    expect(find.textContaining('Future installment'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);

    await tester.tap(find.text('Add goal'));
    await tester.pumpAndSettle();
    expect(find.text('Goal name'), findsOneWidget);
    expect(find.text('Progress tracking'), findsOneWidget);
  });
}
