import 'dart:io';
import 'dart:typed_data';

import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
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
