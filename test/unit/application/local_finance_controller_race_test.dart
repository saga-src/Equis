import 'dart:async';

import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/application/ports/foundational_repositories.dart';
import 'package:equis/application/ports/ledger_repository.dart';
import 'package:equis/application/ports/local_unit_of_work.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'failed edit cannot restore a snapshot superseded by sync reload',
    () async {
      const now = UtcInstant.fromEpochMicroseconds(1);
      final vaultId = EntityId.generate();
      final vaults = _Vaults(
        VaultProfile(
          id: vaultId,
          name: 'Before pull',
          baseCurrency: CurrencyCode.brl,
          locale: 'en-US',
          timezone: 'UTC',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final accounts = _Accounts();
      final categories = _Categories();
      final tags = _Tags();
      final ledger = _Ledger();
      final unitOfWork = _BlockedUnitOfWork();
      final session = LocalFinanceSessionService(
        vaults: vaults,
        accounts: accounts,
        categories: categories,
        tags: tags,
        ledger: ledger,
        unitOfWork: unitOfWork,
        containers: LocalFinanceContainerService(
          vaults: vaults,
          currencies: _Currencies(),
          accounts: accounts,
          ledger: ledger,
          unitOfWork: unitOfWork,
        ),
        taxonomy: TaxonomyService(categories: categories, tags: tags),
        everydayTransactions: EverydayTransactionService(ledger: ledger),
      );
      final controller = LocalFinanceController(session, null);
      addTearDown(controller.dispose);
      await controller.reload();
      // ignore: deprecated_member_use
      expect(controller.debugState.valueOrNull?.vault?.name, 'Before pull');

      final pocket = LedgerPocket(
        id: EntityId.generate(),
        currency: CurrencyCode.brl,
        nature: AccountNature.asset,
      );
      final existing = LedgerTransaction(
        id: EntityId.generate(),
        vaultId: vaultId,
        type: LedgerTransactionType.expense,
        status: LedgerTransactionStatus.cleared,
        financialDate: LocalDate(2026, 9, 1),
        movements: [
          LedgerMovement(
            id: EntityId.generate(),
            pocket: pocket,
            amountMinor: -1000,
            sortOrder: 0,
          ),
        ],
        splits: [
          LedgerSplit(
            id: EntityId.generate(),
            categoryId: EntityId.generate(),
            money: Money(currency: CurrencyCode.brl, minorUnits: 1000),
            sortOrder: 0,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final edit = controller.updateTransaction(
        existing: existing,
        source: pocket,
        amountText: '12.00',
        date: LocalDate(2026, 9, 1),
      );
      await unitOfWork.entered.future;
      vaults.current = vaults.current.revise(name: 'After pull', at: now);
      await controller.reload();
      // ignore: deprecated_member_use
      expect(controller.debugState.valueOrNull?.vault?.name, 'After pull');

      unitOfWork.release.complete();
      await expectLater(edit, throwsA(isA<LedgerRevisionConflict>()));
      // ignore: deprecated_member_use
      expect(controller.debugState.valueOrNull?.vault?.name, 'After pull');
    },
  );
}

final class _Vaults implements VaultRepository {
  _Vaults(this.current);
  VaultProfile current;
  @override
  Future<List<VaultProfile>> listActive() async => [current];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Accounts implements AccountAggregateRepository {
  @override
  Future<List<AccountAggregate>> listAggregatesForVault(
    EntityId vaultId,
  ) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Categories implements CategoryRepository {
  @override
  Future<List<CategoryNode>> listForVault(EntityId vaultId) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Tags implements TagRepository {
  @override
  Future<List<Tag>> listForVault(EntityId vaultId) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Currencies implements CurrencyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Ledger implements LedgerRepository {
  @override
  Future<List<LedgerTransaction>> listRecentForVault(
    EntityId vaultId, {
    int limit = 20,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BlockedUnitOfWork implements LocalUnitOfWork {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<T> run<T>(Future<T> Function() action) async {
    entered.complete();
    await release.future;
    throw LedgerRevisionConflict(
      transactionId: EntityId.generate(),
      expectedRevision: 1,
      actualRevision: 2,
    );
  }
}
