import 'package:drift/native.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const now = UtcInstant.fromEpochMicroseconds(1786636800123456);

  test(
    'stable localized defaults coexist with unlimited nested user categories and tags',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _fixture(database, now);
      final categories = DriftCategoryRepository(database);
      final tags = DriftTagRepository(database);
      final service = TaxonomyService(categories: categories, tags: tags);
      await service.seedDefaults(fixture.vault, now);
      final defaults = await categories.listForVault(fixture.vault);
      expect(defaults, hasLength(7));
      expect(
        defaults.every(
          (category) =>
              category.systemKey != null && category.customName == null,
        ),
        isTrue,
      );

      var parent = await service.createCategory(
        vaultId: fixture.vault,
        type: CategoryType.expense,
        name: 'Comida',
        nameEnUs: 'Food',
        namePtBr: 'Alimentação',
        now: now,
      );
      for (var depth = 0; depth < 12; depth++) {
        parent = await service.createCategory(
          vaultId: fixture.vault,
          type: CategoryType.expense,
          name: 'Level $depth',
          parentId: parent.id,
          now: now,
        );
      }
      final tag = await service.createTag(
        vaultId: fixture.vault,
        name: 'Daily',
        nameEnUs: 'Daily',
        namePtBr: 'Diário',
        color: '#ff00ff',
        now: now,
      );
      expect((await tags.find(tag.id))?.name, 'Daily');
      expect((await tags.find(tag.id))?.namePtBr, 'Diário');
      expect((await categories.find(parent.id))?.customName, 'Level 11');
      final localizedRoot = (await categories.listForVault(
        fixture.vault,
      )).singleWhere((category) => category.customName == 'Comida');
      expect(localizedRoot.customNameEnUs, 'Food');
      expect(localizedRoot.customNamePtBr, 'Alimentação');
      expect(await categories.listForVault(fixture.vault), hasLength(20));
    },
  );

  test(
    'category hierarchy rejects cycles, missing parents, and cross-type parents',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _fixture(database, now);
      final categories = DriftCategoryRepository(database);
      final service = TaxonomyService(
        categories: categories,
        tags: DriftTagRepository(database),
      );
      final expense = await service.createCategory(
        vaultId: fixture.vault,
        type: CategoryType.expense,
        name: 'Expense',
        now: now,
      );
      final child = await service.createCategory(
        vaultId: fixture.vault,
        type: CategoryType.expense,
        name: 'Child',
        parentId: expense.id,
        now: now,
      );
      final income = await service.createCategory(
        vaultId: fixture.vault,
        type: CategoryType.income,
        name: 'Income',
        now: now,
      );
      await expectLater(
        service.validateReparent(expense, child.id),
        throwsStateError,
      );
      await expectLater(
        service.validateReparent(expense, income.id),
        throwsStateError,
      );
      await expectLater(
        service.createCategory(
          vaultId: fixture.vault,
          type: CategoryType.expense,
          name: 'Orphan',
          parentId: EntityId.generate(),
          now: now,
        ),
        throwsStateError,
      );
      await expectLater(
        service.archiveUserCategory(expense, now: now),
        throwsStateError,
      );
      final archivedChild = await service.archiveUserCategory(child, now: now);
      expect(archivedChild.archived, isTrue);
      final archivedParent = await service.archiveUserCategory(
        expense,
        now: now,
      );
      expect(archivedParent.archived, isTrue);
    },
  );

  test(
    'quick expense commits locally with category and tags before returning',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _fixture(database, now);
      final taxonomy = TaxonomyService(
        categories: DriftCategoryRepository(database),
        tags: DriftTagRepository(database),
      );
      final category = await taxonomy.createCategory(
        vaultId: fixture.vault,
        type: CategoryType.expense,
        name: 'Groceries',
        now: now,
      );
      final tag = await taxonomy.createTag(
        vaultId: fixture.vault,
        name: 'Essential',
        now: now,
      );
      final repository = DriftLedgerRepository(database);
      final transaction = await EverydayTransactionService(ledger: repository)
          .addExpense(
            vaultId: fixture.vault,
            pocket: fixture.pocket,
            amount: Money(currency: CurrencyCode.brl, minorUnits: 4590),
            categoryId: category.id,
            tagIds: [tag.id],
            date: LocalDate.parse('2026-08-13'),
            now: now,
          );
      final reloaded = await repository.find(transaction.id);
      expect(reloaded?.splits.single.categoryId, category.id);
      expect(reloaded?.tagIds, [tag.id]);
      expect(reloaded?.movements.single.amountMinor, -4590);

      final revised = await EverydayTransactionService(ledger: repository)
          .update(
            existing: reloaded!,
            source: fixture.pocket,
            amount: Money(currency: CurrencyCode.brl, minorUnits: 5100),
            categoryId: category.id,
            tagIds: [tag.id],
            title: 'Market',
            date: LocalDate.parse('2026-08-14'),
            now: const UtcInstant.fromEpochMicroseconds(1786723200123456),
          );
      expect(revised.revision, 2);
      expect((await repository.find(transaction.id))?.title, 'Market');
      expect(
        (await repository.listRecentForVault(fixture.vault)),
        hasLength(1),
      );

      await repository.save(
        revised.softDelete(
          at: const UtcInstant.fromEpochMicroseconds(1786809600123456),
        ),
      );
      expect(await repository.listRecentForVault(fixture.vault), isEmpty);
      expect((await repository.find(transaction.id))?.deletedAt, isNotNull);
    },
  );
}

Future<_Fixture> _fixture(EquisDatabase database, UtcInstant now) async {
  final vault = EntityId.generate();
  final account = EntityId.generate();
  final pocket = EntityId.generate();
  await database.customStatement(
    'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
    [
      vault.value,
      'Vault',
      'BRL',
      'UTC',
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
      'Cash',
      'cash',
      'asset',
      now.epochMicroseconds,
      now.epochMicroseconds,
    ],
  );
  await database.customStatement(
    'INSERT INTO account_pockets (id, account_id, currency_code) VALUES (?, ?, ?)',
    [pocket.value, account.value, 'BRL'],
  );
  return _Fixture(
    vault: vault,
    pocket: LedgerPocket(
      id: pocket,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    ),
  );
}

final class _Fixture {
  const _Fixture({required this.vault, required this.pocket});
  final EntityId vault;
  final LedgerPocket pocket;
}
