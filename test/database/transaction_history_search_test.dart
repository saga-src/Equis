import 'package:drift/native.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/ledger/transaction_search.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_transaction_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftLedgerRepository ledger;
  late DriftTransactionHistoryRepository history;
  late _Fixture fixture;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    ledger = DriftLedgerRepository(database);
    history = DriftTransactionHistoryRepository(
      database: database,
      ledger: ledger,
    );
    fixture = await _seed(database);
  });

  tearDown(() => database.close());

  test(
    'without-tags filter survives pagination and excludes tagged expenses',
    () async {
      for (var i = 0; i < 3; i++) {
        await _expense(
          ledger,
          fixture,
          amount: 1000,
          date: LocalDate(2026, 8, 10),
          title: 'Expense',
          categoryId: fixture.childCategory,
          createdMicros: 100 + i,
          tagIds: i == 0 ? [fixture.tag] : [],
        );
      }
      final filter = TransactionSearchFilter(
        vaultId: fixture.vault,
        withoutTags: true,
        reportingExpensesOnly: true,
        pageSize: 1,
      );
      final first = await history.search(filter);
      final second = await history.search(filter.nextPage(first.nextCursor!));
      expect(first.items.single.tagIds, isEmpty);
      expect(second.items.single.tagIds, isEmpty);
      expect(second.items.single.id, isNot(first.items.single.id));
      expect(second.hasMore, isFalse);
    },
  );

  test(
    'combines every advanced filter and includes child categories',
    () async {
      final matching = await _expense(
        ledger,
        fixture,
        amount: 7250,
        date: LocalDate(2026, 8, 10),
        title: 'Weekly purchase',
        notes: 'household staples',
        categoryId: fixture.childCategory,
        tagIds: [fixture.tag],
        createdMicros: 300,
      );
      await database.customStatement(
        'UPDATE transactions SET counterparty_id = ? WHERE id = ?',
        [fixture.counterparty.value, matching.id.value],
      );
      await _expense(
        ledger,
        fixture,
        amount: 50000,
        date: LocalDate(2026, 7, 1),
        title: 'Other merchant',
        notes: 'unrelated',
        categoryId: fixture.otherCategory,
        createdMicros: 200,
      );

      final result = await history.search(
        TransactionSearchFilter(
          vaultId: fixture.vault,
          merchantQuery: 'market',
          notesQuery: 'staples',
          minimumAmountMinor: 7000,
          maximumAmountMinor: 8000,
          fromDate: LocalDate(2026, 8, 1),
          toDate: LocalDate(2026, 8, 31),
          accountId: fixture.account,
          categoryId: fixture.parentCategory,
          includeDescendantCategories: true,
          tagId: fixture.tag,
          currency: CurrencyCode.brl,
          types: const {LedgerTransactionType.expense},
          statuses: const {LedgerTransactionStatus.cleared},
        ),
      );

      expect(result.items.map((item) => item.id), [matching.id]);
      expect(result.hasMore, isFalse);
    },
  );

  test('escapes wildcard characters in text searches', () async {
    final literal = await _expense(
      ledger,
      fixture,
      amount: 1000,
      date: LocalDate(2026, 8, 11),
      title: r'100% Market_A',
      categoryId: fixture.childCategory,
      createdMicros: 100,
    );
    await _expense(
      ledger,
      fixture,
      amount: 1000,
      date: LocalDate(2026, 8, 11),
      title: '1000 MarketXA',
      categoryId: fixture.childCategory,
      createdMicros: 99,
    );
    final result = await history.search(
      TransactionSearchFilter(
        vaultId: fixture.vault,
        merchantQuery: r'% Market_',
      ),
    );
    expect(result.items.map((item) => item.id), [literal.id]);
  });

  test('keyset pagination is stable and does not duplicate rows', () async {
    for (var index = 0; index < 5; index++) {
      await _expense(
        ledger,
        fixture,
        amount: 1000 + index,
        date: LocalDate(2026, 8, 12),
        title: 'Page $index',
        categoryId: fixture.childCategory,
        createdMicros: 1000 + index,
      );
    }
    final first = await history.search(
      TransactionSearchFilter(vaultId: fixture.vault, pageSize: 2),
    );
    final second = await history.search(
      TransactionSearchFilter(
        vaultId: fixture.vault,
        pageSize: 2,
        cursor: first.nextCursor,
      ),
    );
    final third = await history.search(
      TransactionSearchFilter(
        vaultId: fixture.vault,
        pageSize: 2,
        cursor: second.nextCursor,
      ),
    );
    final ids = [
      ...first.items,
      ...second.items,
      ...third.items,
    ].map((item) => item.id).toList();
    expect(ids, hasLength(5));
    expect(ids.toSet(), hasLength(5));
    expect(first.hasMore, isTrue);
    expect(second.hasMore, isTrue);
    expect(third.hasMore, isFalse);
  });

  test(
    'one-thousand-row local history returns first page under one second',
    () async {
      await database.transaction(() async {
        for (var index = 0; index < 1000; index++) {
          final transactionId = EntityId.generate();
          final movementId = EntityId.generate();
          final splitId = EntityId.generate();
          await database.customStatement(
            'INSERT INTO transactions '
            '(id, vault_id, transaction_type, status, title, financial_date, revision, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)',
            [
              transactionId.value,
              fixture.vault.value,
              'expense',
              'cleared',
              'Fixture $index',
              '2026-08-${(index % 28 + 1).toString().padLeft(2, '0')}',
              index + 10000,
              index + 10000,
            ],
          );
          await database.customStatement(
            'INSERT INTO account_movements '
            '(id, transaction_id, account_pocket_id, amount_minor, sort_order) '
            'VALUES (?, ?, ?, ?, 0)',
            [
              movementId.value,
              transactionId.value,
              fixture.pocket.value,
              -1000,
            ],
          );
          await database.customStatement(
            'INSERT INTO transaction_splits '
            '(id, transaction_id, category_id, currency_code, amount_minor, sort_order) '
            'VALUES (?, ?, ?, ?, ?, 0)',
            [
              splitId.value,
              transactionId.value,
              fixture.childCategory.value,
              'BRL',
              1000,
            ],
          );
        }
      });
      final stopwatch = Stopwatch()..start();
      final result = await history.search(
        TransactionSearchFilter(
          vaultId: fixture.vault,
          categoryId: fixture.parentCategory,
          includeDescendantCategories: true,
        ),
      );
      stopwatch.stop();
      expect(result.items, hasLength(50));
      expect(result.hasMore, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );
}

Future<_Fixture> _seed(EquisDatabase database) async {
  final vault = EntityId.generate();
  final account = EntityId.generate();
  final pocket = EntityId.generate();
  final parentCategory = EntityId.generate();
  final childCategory = EntityId.generate();
  final otherCategory = EntityId.generate();
  final tag = EntityId.generate();
  final counterparty = EntityId.generate();
  await database.customStatement(
    'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, 1, 1)',
    [vault.value, 'Local', 'BRL', 'America/Sao_Paulo'],
  );
  await database.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'currency.brl', 'R\$', 2)",
  );
  await database.customStatement(
    'INSERT INTO accounts '
    '(id, vault_id, name, account_type, nature, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, 1, 1)',
    [account.value, vault.value, 'Checking', 'checking', 'asset'],
  );
  await database.customStatement(
    'INSERT INTO account_pockets (id, account_id, currency_code, is_default) '
    'VALUES (?, ?, ?, 1)',
    [pocket.value, account.value, 'BRL'],
  );
  for (final category in [
    (parentCategory, null, 'Parent'),
    (childCategory, parentCategory, 'Child'),
    (otherCategory, null, 'Other'),
  ]) {
    await database.customStatement(
      'INSERT INTO categories '
      '(id, vault_id, parent_id, category_type, custom_name, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 1, 1)',
      [
        category.$1.value,
        vault.value,
        category.$2?.value,
        'expense',
        category.$3,
      ],
    );
  }
  await database.customStatement(
    'INSERT INTO tags (id, vault_id, name, created_at, updated_at) '
    'VALUES (?, ?, ?, 1, 1)',
    [tag.value, vault.value, 'Essential'],
  );
  await database.customStatement(
    'INSERT INTO counterparties (id, vault_id, name, created_at, updated_at) '
    'VALUES (?, ?, ?, 1, 1)',
    [counterparty.value, vault.value, 'Neighborhood Market'],
  );
  return _Fixture(
    vault: vault,
    account: account,
    pocket: pocket,
    parentCategory: parentCategory,
    childCategory: childCategory,
    otherCategory: otherCategory,
    tag: tag,
    counterparty: counterparty,
  );
}

Future<LedgerTransaction> _expense(
  DriftLedgerRepository ledger,
  _Fixture fixture, {
  required int amount,
  required LocalDate date,
  required String title,
  required EntityId categoryId,
  required int createdMicros,
  String? notes,
  List<EntityId> tagIds = const [],
}) async {
  final now = UtcInstant.fromEpochMicroseconds(createdMicros);
  final transaction = LedgerTransaction(
    id: EntityId.generate(),
    vaultId: fixture.vault,
    type: LedgerTransactionType.expense,
    status: LedgerTransactionStatus.cleared,
    financialDate: date,
    movements: [
      LedgerMovement(
        id: EntityId.generate(),
        pocket: LedgerPocket(
          id: fixture.pocket,
          currency: CurrencyCode.brl,
          nature: AccountNature.asset,
        ),
        amountMinor: -amount,
        sortOrder: 0,
      ),
    ],
    splits: [
      LedgerSplit(
        id: EntityId.generate(),
        categoryId: categoryId,
        money: Money(currency: CurrencyCode.brl, minorUnits: amount),
        sortOrder: 0,
      ),
    ],
    title: title,
    notes: notes,
    tagIds: tagIds,
    createdAt: now,
    updatedAt: now,
  );
  await ledger.save(transaction);
  return transaction;
}

final class _Fixture {
  const _Fixture({
    required this.vault,
    required this.account,
    required this.pocket,
    required this.parentCategory,
    required this.childCategory,
    required this.otherCategory,
    required this.tag,
    required this.counterparty,
  });

  final EntityId vault;
  final EntityId account;
  final EntityId pocket;
  final EntityId parentCategory;
  final EntityId childCategory;
  final EntityId otherCategory;
  final EntityId tag;
  final EntityId counterparty;
}
