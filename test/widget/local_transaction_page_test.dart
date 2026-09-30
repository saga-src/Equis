import 'package:drift/native.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/router/app_router.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_transaction_history_repository.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/history/transaction_history_controller.dart';
import 'package:equis/presentation/history/transaction_history_screen.dart';
import 'package:equis/presentation/transactions/local_transaction_page.dart';
import 'package:equis/presentation/transactions/quick_transaction_screen.dart';
import 'package:equis/presentation/transactions/transaction_detail_controller.dart';
import 'package:equis/presentation/transactions/transaction_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('direct editor finds an expense outside the 20 recent entries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final vaults = DriftVaultRepository(database);
    final currencies = DriftCurrencyRepository(database);
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
        currencies: currencies,
        accounts: accounts,
        ledger: ledger,
        unitOfWork: unitOfWork,
      ),
      taxonomy: TaxonomyService(categories: categories, tags: tags),
      everydayTransactions: EverydayTransactionService(ledger: ledger),
    );
    const now = UtcInstant.fromEpochMicroseconds(1000);
    final setup = await session.setupLocalVault(
      profileName: 'Personal',
      accountName: 'Checking',
      currency: CurrencyCode.brl,
      locale: 'en-US',
      timezone: 'UTC',
      now: now,
    );
    final pocket = setup.accounts.single.pockets.single;
    final ledgerPocket = LedgerPocket(
      id: pocket.id,
      currency: pocket.currency,
      nature: setup.accounts.single.account.nature,
    );
    final category = setup.categories.singleWhere(
      (entry) => entry.systemKey == 'category.food',
    );
    final created = await session.createEverydayTransaction(
      type: EverydayTransactionType.expense,
      source: ledgerPocket,
      amount: Money(currency: CurrencyCode.brl, minorUnits: 1000),
      categoryId: category.id,
      date: LocalDate(2026, 9, 1),
      now: now,
    );
    final oldId = created.recentTransactions.single.id;
    EntityId? specialId;
    for (var day = 2; day <= 21; day++) {
      final transaction = LedgerTransaction(
        id: EntityId.generate(),
        vaultId: setup.vault!.id,
        type: LedgerTransactionType.openingBalance,
        status: LedgerTransactionStatus.cleared,
        financialDate: LocalDate(2026, 9, day),
        movements: [
          LedgerMovement(
            id: EntityId.generate(),
            pocket: ledgerPocket,
            amountMinor: 100,
            sortOrder: 0,
          ),
        ],
        splits: const [],
        createdAt: UtcInstant.fromEpochMicroseconds(1000 + day),
        updatedAt: UtcInstant.fromEpochMicroseconds(1000 + day),
      );
      await ledger.save(transaction);
      specialId ??= transaction.id;
    }
    expect(
      (await session.load()).recentTransactions.map((item) => item.id),
      isNot(contains(oldId)),
    );

    final router = createAppRouter();
    TransactionDetailController? oldDetailController;
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFinanceControllerProvider.overrideWith((ref) {
            final controller = LocalFinanceController(session, null);
            controller.reload();
            return controller;
          }),
          transactionDetailControllerProvider.overrideWith((ref, key) {
            final controller = TransactionDetailController(
              () => session.loadTransactionDetailData(
                id: key.transactionId,
                vaultId: key.vaultId,
              ),
            );
            if (key.transactionId == oldId) oldDetailController = controller;
            controller.reload();
            return controller;
          }),
          transactionHistoryControllerProvider.overrideWith((ref) {
            final controller = TransactionHistoryController(
              repository: DriftTransactionHistoryRepository(
                database: database,
                ledger: ledger,
              ),
              vaultId: setup.vault!.id,
            );
            controller.loadInitial();
            return controller;
          }),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    router.go('/transactions/${specialId!.value}/details');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump(const Duration(milliseconds: 500));
    expect(router.routeInformationProvider.value.uri.path, '/');

    router.go('/transactions/${oldId.value}');
    await tester.pumpAndSettle();
    expect(find.byType(LocalTransactionPage), findsOneWidget);
    expect(find.byType(QuickTransactionScreen), findsOneWidget);
    expect(find.text('Edit transaction'), findsOneWidget);

    router.go('/transactions/${specialId.value}');
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.text('Opening balance'), findsWidgets);

    router.go('/history');
    await tester.pumpAndSettle();
    expect(find.byType(TransactionHistoryScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Expense'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(TransactionHistoryScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.text('Expense'), findsWidgets);

    router.push('/transactions/${specialId.value}');
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.text('Opening balance'), findsWidgets);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.text('Expense'), findsWidgets);

    router.go('/transactions/not-a-uuid');
    await tester.pumpAndSettle();
    expect(find.text('Transaction not found.'), findsOneWidget);

    router.go('/transactions/${oldId.value}');
    await tester.pumpAndSettle();
    expect(find.byType(QuickTransactionScreen), findsOneWidget);
    await database.customStatement(
      'UPDATE accounts SET archived = 1 WHERE id = ?',
      [setup.accounts.single.account.id.value],
    );
    await oldDetailController!.reload();
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.byType(QuickTransactionScreen), findsNothing);
  });
}
