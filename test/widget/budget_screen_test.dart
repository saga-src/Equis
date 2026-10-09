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
import 'package:equis/app/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/budget_test_repository.dart';

void main() {
  for (final locale in [const Locale('en', 'US'), const Locale('pt', 'BR')]) {
    testWidgets('name-only edit leaves monthly configuration alone: $locale', (
      tester,
    ) async {
      final repository = BudgetTestRepository();
      final controller = BudgetController(
        service: repository.service,
        vaultId: repository.vault,
        clock: () => DateTime.utc(2026, 8, 17),
      );
      await _mount(tester, repository, controller, locale);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(BudgetScreen)),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.editBudgetAction));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('budget-name')),
        'General name',
      );
      await tester.tap(find.byKey(const Key('budget-save')));
      await tester.pumpAndSettle();
      expect(repository.budget.name, 'General name');
      expect(repository.writes, 1);
      expect(repository.editedMonth, isNull);
      expect(repository.submitted, isNull);
    });

    testWidgets(
      'monthly cards and editor fit narrow large-text layout: $locale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = BudgetTestRepository();
        final controller = BudgetController(
          service: repository.service,
          vaultId: repository.vault,
          clock: () => DateTime.utc(2026, 8, 17),
        );
        await _mount(tester, repository, controller, locale, scale: 2);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BudgetScreen)),
        );
        expect(find.text(l10n.budgetUsageLabel), findsOneWidget);
        await tester.ensureVisible(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.editBudgetAction));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l10n.cancelAction));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'nonmonthly editor retains weekly yearly and custom periods: $locale',
      (tester) async {
        final repository = BudgetTestRepository();
        repository.budget = repository.budget.revise(
          periodType: BudgetPeriodType.weekly,
          at: UtcInstant.fromDateTime(DateTime.utc(2026, 8, 17)),
        );
        final controller = BudgetController(
          service: repository.service,
          vaultId: repository.vault,
          clock: () => DateTime.utc(2026, 8, 17),
        );
        await _mount(tester, repository, controller, locale);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BudgetScreen)),
        );
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.editBudgetAction));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('budget-limit-method')), findsNothing);
        expect(find.byKey(const Key('budget-edit-scope')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('budget-period')));
        await tester.tap(find.byKey(const Key('budget-period')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.customBudgetPeriod), findsOneWidget);
        await tester.tap(find.text(l10n.yearlyBudgetPeriod).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('budget-save')));
        await tester.pumpAndSettle();
        expect(repository.budget.periodType, BudgetPeriodType.yearly);
        expect(repository.submitted, isNull);
      },
    );
    for (final width in [360.0, 1280.0]) {
      testWidgets(
        'monthly preview, validation and creation: $locale width=$width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repository = BudgetTestRepository();
          final controller = BudgetController(
            service: repository.service,
            vaultId: repository.vault,
            clock: () => DateTime.utc(2024, 2, 29, 12),
          );
          await _mount(tester, repository, controller, locale, scale: 1.5);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(BudgetScreen)),
          );
          await tester.tap(find.text(l10n.addBudgetAction));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('budget-name')),
            'Daily plan',
          );
          await tester.tap(find.byKey(const Key('budget-limit-method')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.budgetPerWeekday).last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('budget-amount')),
            '10,00',
          );
          await tester.pump();
          final preview = tester
              .widget<Text>(find.byKey(const Key('budget-limit-preview')))
              .data!;
          expect(preview, contains('21'));
          expect(
            preview,
            contains(locale.languageCode == 'pt' ? '210,00' : '210.00'),
          );
          await tester.enterText(find.byKey(const Key('budget-amount')), '0');
          await tester.tap(find.byKey(const Key('budget-save')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('budget-editor-error')), findsOneWidget);
          expect(repository.writes, 0);
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('budget-name')))
                .controller!
                .text,
            'Daily plan',
          );
          await tester.enterText(find.byKey(const Key('budget-amount')), '10');
          await tester.tap(find.byKey(const Key('budget-save')));
          await tester.pumpAndSettle();
          expect(repository.submitted!.limitMethod, BudgetLimitMethod.weekday);
          expect(repository.submitted!.amountMinor, 1000);
          expect(repository.budget.limitMinor, 21000);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'monthly editor submits selected month, scope, rate and warning: $locale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = BudgetTestRepository();
        repository.configuration = BudgetMonthlyConfiguration(
          limitMethod: BudgetLimitMethod.calendarDay,
          amountMinor: 1000,
          warningThresholdBps: 7555,
          scope: BudgetScope(
            categories: [
              BudgetCategoryScope(
                categoryId: EntityId.generate(),
                includeDescendants: false,
              ),
              BudgetCategoryScope(
                categoryId: EntityId.generate(),
                includeDescendants: true,
              ),
            ],
          ),
        );
        final controller = BudgetController(
          service: repository.service,
          vaultId: repository.vault,
          clock: () => DateTime.utc(2026, 8, 17),
        );
        await _mount(tester, repository, controller, locale);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BudgetScreen)),
        );
        await tester.tap(find.byKey(const Key('budget-previous-month')));
        await tester.pumpAndSettle();
        expect(controller.state.selectedMonth, BudgetMonth(2026, 7));
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.editBudgetAction));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-amount')))
              .controller!
              .text,
          '10.00',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-threshold')))
              .controller!
              .text,
          '75.55',
        );
        expect(find.text(l10n.budgetGeneralNameHint), findsOneWidget);
        await tester.enterText(find.byKey(const Key('budget-name')), 'Renamed');
        await tester.ensureVisible(find.byKey(const Key('budget-edit-scope')));
        await tester.tap(find.byKey(const Key('budget-edit-scope')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.budgetFromMonth).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('budget-amount')));
        await tester.enterText(find.byKey(const Key('budget-amount')), '12');
        repository.failWrites = true;
        await tester.tap(find.byKey(const Key('budget-save')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.budgetRevisionChanged), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-name')))
              .controller!
              .text,
          'Renamed',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('budget-amount')))
              .controller!
              .text,
          '12',
        );
        repository.failWrites = false;
        await tester.tap(find.byKey(const Key('budget-save')));
        await tester.pumpAndSettle();
        expect(repository.editedMonth, BudgetMonth(2026, 7));
        expect(repository.editScope, BudgetMonthlyEditScope.fromMonth);
        expect(repository.submittedName, 'Renamed');
        expect(repository.submitted!.amountMinor, 1200);
        expect(
          repository.submitted!.limitMethod,
          BudgetLimitMethod.calendarDay,
        );
        expect(repository.submitted!.warningThresholdBps, 7555);
        expect(
          repository.submitted!.scope.categories.map(
            (item) => item.includeDescendants,
          ),
          [false, true],
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'month picker, future usage, deleted read-only history and retry: $locale',
      (tester) async {
        final repository = BudgetTestRepository(deleted: true);
        final controller = BudgetController(
          service: repository.service,
          vaultId: repository.vault,
          clock: () => DateTime.utc(2026, 8, 17),
        );
        await _mount(tester, repository, controller, locale);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BudgetScreen)),
        );
        expect(find.text(l10n.budgetEmptyMonth), findsOneWidget);
        await tester.tap(find.byKey(const Key('budget-show-deleted')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.budgetDeletedReadOnly), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsNothing);
        await tester.tap(find.byKey(const Key('budget-select-month')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('budget-month-year')), '0');
        await tester.tap(find.byKey(const Key('budget-month-apply')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.budgetInvalidMonth), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('budget-month-year')),
          '2027',
        );
        await tester.tap(find.byKey(const Key('budget-month-apply')));
        await tester.pumpAndSettle();
        expect(controller.state.selectedMonth, BudgetMonth(2027, 8));
        expect(find.text(l10n.budgetFutureMonthHint), findsOneWidget);
        expect(controller.state.items.single.usedMinor, 0);
        expect(controller.state.currentItems, isEmpty);
        repository.failReads = true;
        await controller.reload();
        await tester.pumpAndSettle();
        expect(find.text(l10n.budgetLoadFailedMessage), findsOneWidget);
        repository.failReads = false;
        await tester.tap(find.text(l10n.budgetRetryAction));
        await tester.pumpAndSettle();
        expect(find.text(l10n.budgetLoadFailedMessage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
    expect(find.text('Overall spending'), findsNWidgets(2));
  });
}

Future<void> _mount(
  WidgetTester tester,
  BudgetTestRepository repository,
  BudgetController controller,
  Locale locale, {
  double scale = 1,
}) async {
  await controller.reload();
  final instant = UtcInstant.fromDateTime(DateTime.utc(2026, 7, 1));
  final finance = LocalFinanceSnapshot(
    vault: VaultProfile(
      id: repository.vault,
      name: 'Fixture',
      baseCurrency: CurrencyCode.brl,
      locale: locale.toLanguageTag(),
      timezone: 'UTC',
      createdAt: instant,
      updatedAt: instant,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [budgetControllerProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: BudgetScreen(financeOverride: finance),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
