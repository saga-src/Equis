import 'dart:io';
import 'dart:typed_data';

import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
import 'package:equis/application/ports/ledger_repository.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/local_database_lifecycle.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'edit rechecks active references and original revision atomically',
    () async {
      final temporary = await Directory.systemTemp.createTemp('equis-edit-');
      addTearDown(() => temporary.delete(recursive: true));
      final opened = await _open(
        File('${temporary.path}${Platform.pathSeparator}vault.db'),
      );
      addTearDown(opened.lifecycle.close);
      const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
      final setup = await opened.session.setupLocalVault(
        profileName: 'Personal',
        accountName: 'Checking',
        currency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'America/Sao_Paulo',
        now: now,
      );
      final account = setup.accounts.single;
      final food = setup.categories.singleWhere(
        (category) => category.systemKey == 'category.food',
      );
      final source = LedgerPocket(
        id: account.pockets.single.id,
        currency: CurrencyCode.brl,
        nature: account.account.nature,
      );
      final created = await opened.session.createEverydayTransaction(
        type: EverydayTransactionType.expense,
        source: source,
        amount: Money(currency: CurrencyCode.brl, minorUnits: 1000),
        categoryId: food.id,
        date: LocalDate(2026, 8, 13),
        now: now,
      );
      final createdId = created.recentTransactions.single.id;
      await opened.lifecycle.database.customStatement(
        'UPDATE transaction_splits SET memo = ? WHERE transaction_id = ?',
        ['Keep this memo', createdId.value],
      );
      final original = (await opened.session.loadTransactionDetail(
        id: createdId,
        vaultId: setup.vault!.id,
      ))!;
      Future<void> edit(LedgerTransaction existing) => opened.session
          .updateEverydayTransaction(
            existing: existing,
            source: source,
            amount: Money(currency: CurrencyCode.brl, minorUnits: 1200),
            categoryId: food.id,
            date: LocalDate(2026, 8, 13),
            now: const UtcInstant.fromEpochMicroseconds(1786636801123456),
          )
          .then((_) {});

      await opened.lifecycle.database.customStatement(
        'UPDATE categories SET archived = 1 WHERE id = ?',
        [food.id.value],
      );
      await expectLater(edit(original), throwsA(isA<StateError>()));
      await opened.lifecycle.database.customStatement(
        'UPDATE categories SET archived = 0 WHERE id = ?',
        [food.id.value],
      );
      await opened.lifecycle.database.customStatement(
        'UPDATE accounts SET archived = 1 WHERE id = ?',
        [account.account.id.value],
      );
      await expectLater(edit(original), throwsA(isA<StateError>()));
      await opened.lifecycle.database.customStatement(
        'UPDATE accounts SET archived = 0 WHERE id = ?',
        [account.account.id.value],
      );
      expect(
        (await opened.session.loadTransactionDetail(
          id: original.id,
          vaultId: setup.vault!.id,
        ))?.revision,
        1,
      );
      await edit(original);
      await expectLater(edit(original), throwsA(isA<LedgerRevisionConflict>()));
      final current = await opened.session.loadTransactionDetail(
        id: original.id,
        vaultId: setup.vault!.id,
      );
      expect(current?.revision, 2);
      expect(current?.movements.single.amountMinor, -1200);
      expect(current?.splits.single.memo, 'Keep this memo');
      expect(current?.splits.single.id, original.splits.single.id);
    },
  );

  test(
    'encrypted local presentation session survives restart offline',
    () async {
      final temporary = await Directory.systemTemp.createTemp('equis-session-');
      addTearDown(() => temporary.delete(recursive: true));
      final file = File('${temporary.path}${Platform.pathSeparator}vault.db');
      final first = await _open(file);
      const now = UtcInstant.fromEpochMicroseconds(1786636800123456);

      expect((await first.session.load()).requiresSetup, isTrue);
      var snapshot = await first.session.setupLocalVault(
        profileName: 'Personal',
        accountName: 'Carteira',
        currency: CurrencyCode.brl,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        now: now,
      );
      final account = snapshot.accounts.single;
      final pocket = account.pockets.single;
      final food = snapshot.categories.singleWhere(
        (category) => category.systemKey == 'category.food',
      );
      snapshot = await first.session.createEverydayTransaction(
        type: EverydayTransactionType.expense,
        source: LedgerPocket(
          id: pocket.id,
          currency: pocket.currency,
          nature: account.account.nature,
        ),
        amount: Money(currency: CurrencyCode.brl, minorUnits: 4590),
        categoryId: food.id,
        date: LocalDate.parse('2026-08-13'),
        now: now,
        title: 'Mercado',
      );
      expect(snapshot.recentTransactions.single.title, 'Mercado');
      final transactionId = snapshot.recentTransactions.single.id;
      final vaultId = snapshot.vault!.id;
      expect(
        (await first.session.loadTransactionDetail(
          id: transactionId,
          vaultId: vaultId,
        ))?.title,
        'Mercado',
      );
      final detail = await first.session.loadTransactionDetailData(
        id: transactionId,
        vaultId: vaultId,
      );
      expect(detail?.accounts.single.account.name, 'Carteira');
      expect(
        detail?.categories.any((category) => category.id == food.id),
        isTrue,
      );
      expect(detail?.transaction.splits.single.categoryId, food.id);
      await first.lifecycle.close();

      final reopened = await _open(file);
      addTearDown(reopened.lifecycle.close);
      snapshot = await reopened.session.load();
      expect(snapshot.vault?.name, 'Personal');
      expect(snapshot.accounts.single.account.name, 'Carteira');
      expect(snapshot.categories, hasLength(7));
      expect(
        snapshot.recentTransactions.single.movements.single.amountMinor,
        -4590,
      );

      snapshot = await reopened.session.reconcileTransaction(
        snapshot.recentTransactions.single,
        now: const UtcInstant.fromEpochMicroseconds(1786723200123456),
      );
      expect(
        snapshot.recentTransactions.single.status,
        LedgerTransactionStatus.reconciled,
      );
      snapshot = await reopened.session.deleteTransaction(
        snapshot.recentTransactions.single,
        now: const UtcInstant.fromEpochMicroseconds(1786809600123456),
      );
      expect(snapshot.recentTransactions, isEmpty);
      expect(
        await reopened.session.loadTransactionDetail(
          id: transactionId,
          vaultId: vaultId,
        ),
        isNull,
      );
    },
  );
}

Future<_OpenedSession> _open(File file) async {
  final lifecycle = EncryptedDriftDatabaseLifecycle(
    file: file,
    keyProvider: _FixedKeyProvider(),
  );
  await lifecycle.initialize();
  final database = lifecycle.database;
  final vaults = DriftVaultRepository(database);
  final currencies = DriftCurrencyRepository(database);
  final accounts = DriftAccountAggregateRepository(database);
  final categories = DriftCategoryRepository(database);
  final tags = DriftTagRepository(database);
  final ledger = DriftLedgerRepository(database);
  final unitOfWork = DriftLocalUnitOfWork(database);
  return _OpenedSession(
    lifecycle: lifecycle,
    session: LocalFinanceSessionService(
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
    ),
  );
}

final class _OpenedSession {
  const _OpenedSession({required this.lifecycle, required this.session});
  final EncryptedDriftDatabaseLifecycle lifecycle;
  final LocalFinanceSessionService session;
}

final class _FixedKeyProvider implements LocalDatabaseKeyProvider {
  @override
  Future<Uint8List> loadOrCreateKey() async =>
      Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
}
