import 'package:drift/native.dart';
import 'package:equis/app/equis_app.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/router/app_router.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/budgets/budget_screen.dart';
import 'package:equis/presentation/cloud/cloud_account_screen.dart';
import 'package:equis/presentation/guide/getting_started_screen.dart';
import 'package:equis/presentation/shared/vault_required.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final locale in [const Locale('en', 'US'), const Locale('pt', 'BR')]) {
    for (final width in [360.0, 1280.0]) {
      testWidgets('guide feature clicks without a vault: $locale $width', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = _Fixture(locale);
        addTearDown(fixture.close);
        await fixture.finance.reload();
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        );
        for (final title in [
          l.guideVaultsTitle,
          l.accountManagementTitle,
          l.guideTransactionsTitle,
          l.manageCategoriesTagsAction,
          l.recurringTitle,
          l.budgetsNavigationLabel,
          l.reportsSectionTitle,
          l.portabilityTitle,
          l.guideSyncTitle,
        ]) {
          fixture.router.go('/settings');
          await tester.pumpAndSettle();
          final guideLink = find.byKey(const Key('settings-getting-started'));
          await tester.ensureVisible(guideLink);
          await tester.pumpAndSettle();
          await tester.tap(guideLink);
          await tester.pumpAndSettle();
          final guide = find.byType(GettingStartedScreen);
          final heading = find.descendant(
            of: guide,
            matching: find.text(title),
          );
          await tester.scrollUntilVisible(
            heading,
            250,
            scrollable: find.descendant(
              of: guide,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.ancestor(
            of: heading,
            matching: find.byType(EquisGlassCard),
          );
          final open = find.descendant(
            of: card,
            matching: find.widgetWithText(TextButton, l.guideOpenAction),
          );
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: title);
          if (title == l.guideVaultsTitle || title == l.reportsSectionTitle) {
            expect(
              find.text(l.setupLocalVaultBody),
              findsOneWidget,
              reason: title,
            );
          } else {
            expect(
              find.text(l.setupRequiredMessage),
              findsOneWidget,
              reason: title,
            );
          }
        }
      });
      testWidgets('missing-vault routes and setup links: $locale $width', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = _Fixture(locale);
        addTearDown(fixture.close);
        await fixture.finance.reload();
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        );
        for (final route in [
          '/accounts',
          '/history',
          '/recurring',
          '/cards',
          '/budgets',
          '/goals',
          '/wealth',
          '/investments',
          '/intelligence',
          '/taxonomy',
          '/vault-sync',
          '/transactions/new',
          '/transactions/invalid',
          '/transactions/invalid/details',
        ]) {
          fixture.router.go(route);
          await tester.pumpAndSettle();
          expect(
            find.text(l.setupRequiredMessage),
            findsOneWidget,
            reason: route,
          );
          expect(
            find.byKey(const Key('vault-required-create')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: route);
        }
        await tester.ensureVisible(
          find.byKey(const Key('vault-required-create')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('vault-required-create')));
        await tester.pumpAndSettle();
        expect(fixture.router.routeInformationProvider.value.uri.path, '/');
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(find.text(l.setupLocalVaultBody), findsOneWidget);

        fixture.router.go('/budgets');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('vault-required-open')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('vault-required-open')));
        await tester.pumpAndSettle();
        expect(
          fixture.router.routeInformationProvider.value.uri.path,
          '/cloud-account',
        );
        expect(find.text(l.setupRequiredMessage), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('restore-existing-vault-card')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('restore-existing-vault-card')),
          findsOneWidget,
        );

        fixture.router.go('/portability');
        await tester.pumpAndSettle();
        expect(find.text(l.setupRequiredMessage), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text(l.restoreBackupAction),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text(l.restoreBackupAction), findsOneWidget);
        fixture.router.go('/settings');
        await tester.pumpAndSettle();
        expect(find.byType(VaultRequiredNotice), findsNothing);
        fixture.router.go('/guide');
        await tester.pumpAndSettle();
        expect(find.text(l.guideIntroBody), findsOneWidget);
        expect(find.text(l.guideVaultsBody), findsOneWidget);
        await tester.ensureVisible(find.text(l.createLocalVaultAction));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.createLocalVaultAction));
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets(
      'vault creation unlocks a route; missing vault relocks it: $locale',
      (tester) async {
        final fixture = _Fixture(locale);
        addTearDown(fixture.close);
        await fixture.finance.reload();
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();
        fixture.router.go('/budgets');
        await tester.pumpAndSettle();
        expect(find.byType(BudgetScreen), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('vault-required-create')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('vault-required-create')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), 'Test vault');
        await tester.enterText(find.byType(TextFormField).at(1), 'Checking');
        await tester.ensureVisible(find.byKey(const Key('continue-offline')));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const Key('continue-offline')));
          for (var attempt = 0; attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            if (fixture.container
                    .read(localFinanceControllerProvider)
                    .valueOrNull
                    ?.vault !=
                null) {
              return;
            }
          }
          fail('Vault setup did not finish');
        });
        final snapshot = fixture.container
            .read(localFinanceControllerProvider)
            .valueOrNull;
        expect(snapshot?.vault?.name, 'Test vault');
        expect(snapshot?.accounts, hasLength(1));
        fixture.router.go('/budgets');
        await tester.pumpAndSettle();
        expect(find.byType(BudgetScreen), findsOneWidget);
        expect(find.byType(VaultRequiredNotice), findsNothing);
        fixture.router.go('/settings');
        await tester.pumpAndSettle();
        final guideLink = find.byKey(const Key('settings-getting-started'));
        await tester.ensureVisible(guideLink);
        await tester.pumpAndSettle();
        await tester.tap(guideLink);
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(GettingStartedScreen)),
        );
        await tester.ensureVisible(find.text(l.guideOpenAction).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.guideOpenAction).first);
        await tester.pumpAndSettle();
        expect(find.byType(CloudAccountScreen), findsOneWidget);

        fixture.router.go('/settings');
        await tester.pumpAndSettle();
        await tester.ensureVisible(guideLink);
        await tester.pumpAndSettle();
        await tester.tap(guideLink);
        await tester.pumpAndSettle();
        final guide = find.byType(GettingStartedScreen);
        final budgetHeading = find.descendant(
          of: guide,
          matching: find.text(l.budgetsNavigationLabel),
        );
        await tester.scrollUntilVisible(
          budgetHeading,
          250,
          scrollable: find.descendant(
            of: guide,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        final openBudget = find.descendant(
          of: find.ancestor(
            of: budgetHeading,
            matching: find.byType(EquisGlassCard),
          ),
          matching: find.widgetWithText(TextButton, l.guideOpenAction),
        );
        await tester.ensureVisible(openBudget);
        await tester.pumpAndSettle();
        await tester.tap(openBudget);
        await tester.pumpAndSettle();
        expect(find.byType(BudgetScreen), findsOneWidget);
        expect(find.byType(VaultRequiredNotice), findsNothing);

        await fixture.database.customStatement(
          'UPDATE vaults SET deleted_at = 1',
        );
        await fixture.finance.reload();
        fixture.router.go('/budgets');
        await tester.pumpAndSettle();
        expect(find.byType(BudgetScreen), findsNothing);
        expect(find.byType(VaultRequiredNotice), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'loading and failed vault reads do not show a create-vault prompt',
    (tester) async {
      final fixture = _Fixture(const Locale('en', 'US'));
      addTearDown(fixture.close);
      await tester.pumpWidget(fixture.app);
      fixture.router.go('/budgets');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(VaultRequiredNotice), findsNothing);
      await fixture.finance.reload();
      await fixture.database.customStatement('DROP TABLE vaults');
      await fixture.finance.reload();
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(find.text(l.localVaultErrorMessage), findsOneWidget);
      expect(find.text(l.transactionDetailRetryAction), findsOneWidget);
      expect(find.byType(VaultRequiredNotice), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Fixture {
  _Fixture(Locale locale) {
    final vaults = DriftVaultRepository(database);
    final accounts = DriftAccountAggregateRepository(database);
    final categories = DriftCategoryRepository(database);
    final tags = DriftTagRepository(database);
    final ledger = DriftLedgerRepository(database);
    final unitOfWork = DriftLocalUnitOfWork(database);
    final session = LocalFinanceSessionService(
      vaults: vaults,
      accounts: accounts,
      categories: categories,
      tags: tags,
      ledger: ledger,
      unitOfWork: unitOfWork,
      containers: LocalFinanceContainerService(
        vaults: vaults,
        currencies: DriftCurrencyRepository(database),
        accounts: accounts,
        ledger: ledger,
        unitOfWork: unitOfWork,
      ),
      taxonomy: TaxonomyService(categories: categories, tags: tags),
      everydayTransactions: EverydayTransactionService(ledger: ledger),
    );
    finance = LocalFinanceController(session, null);
    container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        localeProvider.overrideWith((ref) => locale),
        localFinanceControllerProvider.overrideWith((ref) => finance),
      ],
    );
  }
  final database = EquisDatabase(NativeDatabase.memory());
  final router = createAppRouter();
  late final LocalFinanceController finance;
  late final ProviderContainer container;
  Widget get app => UncontrolledProviderScope(
    container: container,
    child: const MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: EquisApp(),
    ),
  );
  Future<void> close() async {
    router.dispose();
    container.dispose();
    await database.close();
  }
}
