import 'package:drift/native.dart';
import 'package:equis/application/ports/ledger_repository.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/dao/ledger_balance_reader.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'archived zero balance cannot change through historical edits',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _fixture(database);
      final repository = DriftLedgerRepository(database);
      final original = LedgerEngine().expense(
        vaultId: fixture.vault,
        pocket: fixture.bank,
        amount: Money(currency: CurrencyCode.brl, minorUnits: 7250),
        categoryId: fixture.category,
        date: LocalDate(2026, 8, 13),
        now: fixture.now,
      );
      await repository.save(original);
      await repository.save(
        original.reversed(
          id: EntityId.generate(),
          nextId: EntityId.generate,
          at: fixture.now,
        ),
      );
      final accounts = DriftAccountAggregateRepository(database);
      final accountId = (await accounts.listAggregatesForVault(
        fixture.vault,
      )).single.account.id;
      final now = UtcInstant.fromEpochMicroseconds(
        DateTime.utc(2026, 8, 14).microsecondsSinceEpoch,
      );
      await accounts.remove(
        vaultId: fixture.vault,
        accountId: accountId,
        expectedRevision: 1,
        now: now,
      );
      for (final edit in [
        original.softDelete(at: now),
        original.transitionTo(LedgerTransactionStatus.cancelled, at: now),
        original.revise(
          movements: original.movements,
          splits: original.splits,
          financialDate: LocalDate(2026, 8, 12),
          at: now,
        ),
      ]) {
        await expectLater(repository.save(edit), throwsStateError);
        expect((await repository.find(original.id))!.revision, 1);
        expect(await LedgerBalanceReader(database).rebuildAll(), {
          fixture.bank.id.value: 0,
        });
      }
      await accounts.restore(
        vaultId: fixture.vault,
        accountId: accountId,
        expectedRevision: 2,
        now: now,
      );
      await repository.save(
        original.transitionTo(LedgerTransactionStatus.cancelled, at: now),
      );
      expect(await LedgerBalanceReader(database).rebuildAll(), {
        fixture.bank.id.value: 7250,
      });
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'ledger aggregate saves, reloads, revises, and cancels atomically',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _fixture(database);
      final repository = DriftLedgerRepository(database);
      final original = LedgerEngine().expense(
        vaultId: fixture.vault,
        pocket: fixture.bank,
        amount: Money(currency: CurrencyCode.brl, minorUnits: 7250),
        categoryId: fixture.category,
        date: LocalDate.parse('2026-08-13'),
        now: fixture.now,
      );

      await repository.save(original);
      final loaded = await repository.find(original.id);
      expect(loaded?.type, LedgerTransactionType.expense);
      expect(loaded?.movements.single.amountMinor, -7250);
      expect(loaded?.splits.single.money.minorUnits, 7250);
      expect(await LedgerBalanceReader(database).rebuildAll(), {
        fixture.bank.id.value: -7250,
      });

      final revised = original.revise(
        movements: [
          LedgerMovement(
            id: EntityId.generate(),
            pocket: fixture.bank,
            amountMinor: -8000,
            sortOrder: 0,
          ),
        ],
        splits: [
          LedgerSplit(
            id: EntityId.generate(),
            categoryId: fixture.category,
            money: Money(currency: CurrencyCode.brl, minorUnits: 8000),
            sortOrder: 0,
          ),
        ],
        at: fixture.now,
        title: 'Revised expense',
      );
      await repository.save(revised);
      expect((await repository.find(original.id))?.revision, 2);
      expect(await LedgerBalanceReader(database).rebuildAll(), {
        fixture.bank.id.value: -8000,
      });

      await expectLater(
        repository.save(original),
        throwsA(isA<LedgerRevisionConflict>()),
      );
      expect(
        (await repository.find(original.id))?.movements.single.amountMinor,
        -8000,
      );

      final cancelled = revised.transitionTo(
        LedgerTransactionStatus.cancelled,
        at: fixture.now,
      );
      await repository.save(cancelled);
      expect(
        (await repository.find(original.id))?.status,
        LedgerTransactionStatus.cancelled,
      );
      expect(await LedgerBalanceReader(database).rebuildAll(), isEmpty);
    },
  );

  test(
    'reversal persists as a linked aggregate and neutralizes the balance',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _fixture(database);
      final repository = DriftLedgerRepository(database);
      final income = LedgerEngine().income(
        vaultId: fixture.vault,
        pocket: fixture.bank,
        amount: Money(currency: CurrencyCode.brl, minorUnits: 10000),
        categoryId: fixture.category,
        date: LocalDate.parse('2026-08-13'),
        now: fixture.now,
      );
      final reversal = income.reversed(
        id: EntityId.generate(),
        nextId: EntityId.generate,
        at: fixture.now,
      );
      await repository.save(income);
      await repository.save(reversal);
      expect((await repository.find(reversal.id))?.reversalOfId, income.id);
      expect(await LedgerBalanceReader(database).rebuildAll(), {
        fixture.bank.id.value: 0,
      });
    },
  );

  test('archived pocket rejects new movements but retains history', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final fixture = await _fixture(database);
    final repository = DriftLedgerRepository(database);
    LedgerTransaction expense(int amount) => LedgerEngine().expense(
      vaultId: fixture.vault,
      pocket: fixture.bank,
      amount: Money(currency: CurrencyCode.brl, minorUnits: amount),
      categoryId: fixture.category,
      date: LocalDate(2026, 8, 13),
      now: fixture.now,
    );
    final original = expense(7250);
    await repository.save(original);
    final pending = LedgerEngine().expense(
      vaultId: fixture.vault,
      pocket: fixture.bank,
      amount: Money(currency: CurrencyCode.brl, minorUnits: 100),
      categoryId: fixture.category,
      date: LocalDate(2026, 8, 14),
      now: fixture.now,
      status: LedgerTransactionStatus.pending,
    );
    await repository.save(pending);
    await database.customStatement(
      "UPDATE accounts SET archived = 1, closed_on = '2026-08-14' "
      'WHERE id = (SELECT account_id FROM account_pockets WHERE id = ?)',
      [fixture.bank.id.value],
    );
    await expectLater(repository.save(expense(100)), throwsStateError);
    await expectLater(
      repository.save(
        pending.transitionTo(LedgerTransactionStatus.cleared, at: fixture.now),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.save(
        original.revise(
          movements: [
            LedgerMovement(
              id: original.movements.single.id,
              pocket: fixture.bank,
              amountMinor: -8000,
              sortOrder: 0,
            ),
          ],
          splits: [
            LedgerSplit(
              id: original.splits.single.id,
              categoryId: fixture.category,
              money: Money(currency: CurrencyCode.brl, minorUnits: 8000),
              sortOrder: 0,
            ),
          ],
          at: fixture.now,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.save(
        original.transitionTo(
          LedgerTransactionStatus.cancelled,
          at: fixture.now,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.save(
        pending.transitionTo(
          LedgerTransactionStatus.cancelled,
          at: fixture.now,
        ),
      ),
      throwsStateError,
    );
    await database.customStatement(
      'UPDATE accounts SET archived = 0, closed_on = NULL '
      'WHERE id = (SELECT account_id FROM account_pockets WHERE id = ?)',
      [fixture.bank.id.value],
    );
    await database.customStatement(
      'UPDATE account_pockets SET archived = 1 WHERE id = ?',
      [fixture.bank.id.value],
    );
    await expectLater(repository.save(expense(100)), throwsStateError);
    await database.customStatement(
      'UPDATE account_pockets SET archived = 0 WHERE id = ?',
      [fixture.bank.id.value],
    );
    await database.customStatement(
      'UPDATE accounts SET deleted_at = ? '
      'WHERE id = (SELECT account_id FROM account_pockets WHERE id = ?)',
      [fixture.now.epochMicroseconds, fixture.bank.id.value],
    );
    await expectLater(repository.save(expense(100)), throwsStateError);
    expect(
      (await repository.find(original.id))!.movements.single.amountMinor,
      -7250,
    );
    expect(
      (await database
              .customSelect('SELECT COUNT(*) AS total FROM transactions')
              .getSingle())
          .read<int>('total'),
      2,
    );
  });
}

Future<_LedgerFixture> _fixture(EquisDatabase database) async {
  final vault = EntityId.generate();
  final account = EntityId.generate();
  final pocket = EntityId.generate();
  final category = EntityId.generate();
  const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
  await database.customStatement(
    'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [
      vault.value,
      'Vault',
      'BRL',
      'America/Sao_Paulo',
      now.epochMicroseconds,
      now.epochMicroseconds,
    ],
  );
  await database.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'currency.brl', 'R\$', 2)",
  );
  await database.customStatement(
    'INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      account.value,
      vault.value,
      'Checking',
      'checking',
      'asset',
      now.epochMicroseconds,
      now.epochMicroseconds,
    ],
  );
  await database.customStatement(
    'INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, ?, 1)',
    [pocket.value, account.value, 'BRL'],
  );
  await database.customStatement(
    'INSERT INTO categories (id, vault_id, category_type, custom_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [
      category.value,
      vault.value,
      'expense',
      'General',
      now.epochMicroseconds,
      now.epochMicroseconds,
    ],
  );
  return _LedgerFixture(
    vault: vault,
    category: category,
    bank: LedgerPocket(
      id: pocket,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    ),
    now: now,
  );
}

final class _LedgerFixture {
  const _LedgerFixture({
    required this.vault,
    required this.category,
    required this.bank,
    required this.now,
  });

  final EntityId vault;
  final EntityId category;
  final LedgerPocket bank;
  final UtcInstant now;
}
