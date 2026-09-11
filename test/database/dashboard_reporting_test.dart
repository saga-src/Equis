import 'package:drift/native.dart';
import 'package:equis/application/services/dashboard_service.dart';
import 'package:equis/application/services/recurring_transaction_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_recurring_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftLedgerRepository ledger;
  late DriftDashboardRepository repository;
  late DashboardService service;
  late _Fixture fixture;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    ledger = DriftLedgerRepository(database);
    repository = DriftDashboardRepository(database);
    final recurringRepository = DriftRecurringRepository(
      database: database,
      ledger: ledger,
    );
    service = DashboardService(
      repository: repository,
      recurring: RecurringTransactionService(
        repository: recurringRepository,
        ledger: ledger,
        unitOfWork: DriftLocalUnitOfWork(database),
      ),
    );
    fixture = await _seed(database, ledger);
  });

  tearDown(() => database.close());

  test(
    'split transactions with multiple tags retain the original expense total',
    () async {
      final tags = [EntityId.generate(), EntityId.generate()];
      final transaction = LedgerEngine().expense(
        vaultId: fixture.vault,
        pocket: fixture.bank,
        amount: Money(currency: CurrencyCode.brl, minorUnits: 1000),
        categoryId: fixture.category,
        date: LocalDate(2026, 8, 17),
        now: const UtcInstant.fromEpochMicroseconds(9000),
      );
      await ledger.save(transaction);
      await database.customStatement(
        'UPDATE transaction_splits SET amount_minor = 400 WHERE transaction_id = ?',
        [transaction.id.value],
      );
      await database.customStatement(
        'INSERT INTO transaction_splits (id, transaction_id, category_id, currency_code, amount_minor) VALUES (?, ?, ?, ?, 600)',
        [
          EntityId.generate().value,
          transaction.id.value,
          fixture.category.value,
          'BRL',
        ],
      );
      for (final tag in tags) {
        await database.customStatement(
          'INSERT INTO tags (id, vault_id, name, created_at, updated_at) VALUES (?, ?, ?, 1, 1)',
          [tag.value, fixture.vault.value, tag.value],
        );
        await database.customStatement(
          'INSERT INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)',
          [transaction.id.value, tag.value],
        );
      }
      final report = await service.load(
        vaultId: fixture.vault,
        reportingCurrency: CurrencyCode.brl,
        asOf: LocalDate(2026, 8, 17),
      );
      expect(report.expenseMinor, 21000);
      expect(
        report.spendingByTag
            .where((item) => item.tagId != null)
            .map((item) => item.amountMinor),
        [1000, 1000],
      );
      expect(
        report.spendingByTag
            .singleWhere((item) => item.tagId == null)
            .amountMinor,
        20000,
      );
    },
  );

  test(
    'tags count full expenses independently without multiplying report totals',
    () async {
      final tags = [EntityId.generate(), EntityId.generate()];
      for (final tag in tags) {
        await database.customStatement(
          'INSERT INTO tags (id, vault_id, name, created_at, updated_at) VALUES (?, ?, ?, 1, 1)',
          [tag.value, fixture.vault.value, tag.value],
        );
        await database.customStatement(
          'INSERT INTO transaction_tags (transaction_id, tag_id) SELECT id, ? FROM transactions',
          [tag.value],
        );
      }
      final report = await service.load(
        vaultId: fixture.vault,
        reportingCurrency: CurrencyCode.brl,
        asOf: LocalDate(2026, 8, 17),
      );
      expect(report.expenseMinor, 20000);
      expect(report.spendingByCategory.single.amountMinor, 20000);
      expect(report.spendingByTag, hasLength(2));
      expect(
        report.spendingByTag.map((item) => item.amountMinor),
        everyElement(20000),
      );
    },
  );

  test(
    'dashboard reconciles ledger, FX, card neutrality, and upcoming rows',
    () async {
      final before = await _transactionFingerprint(database);
      final report = await service.load(
        vaultId: fixture.vault,
        reportingCurrency: CurrencyCode.brl,
        asOf: LocalDate(2026, 8, 17),
      );
      final after = await _transactionFingerprint(database);

      expect(report.availableMoneyMinor, 186000);
      expect(report.incomeMinor, 50000);
      expect(report.expenseMinor, 20000);
      expect(report.spendingByTag.single.tagId, isNull);
      expect(report.spendingByTag.single.amountMinor, 20000);
      expect(report.netCashFlowMinor, 30000);
      expect(report.spendingByCategory.single.amountMinor, 20000);
      expect(report.upcomingCount, 1);
      expect(report.isComplete, isTrue);
      expect(report.usesEstimatedRates, isFalse);
      expect(
        report.accountBalances
            .singleWhere((item) => item.pocketId == fixture.usdWallet.id)
            .reportingMinor,
        50000,
      );
      expect(
        before,
        after,
        reason: 'Read-only reports must not mutate source rows.',
      );
    },
  );

  test('inverse cached rate converts without binary floating point', () async {
    await database.customStatement('DELETE FROM fx_rate_cache');
    await database.customStatement(
      'INSERT INTO fx_rate_cache '
      '(base_currency, quote_currency, rate_date, rate, provider, fetched_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['BRL', 'USD', '2026-08-17', '0.2', 'fixture', 1],
    );
    final fresh = DriftDashboardRepository(database);
    final converted = await fresh.convertMinor(
      vaultId: fixture.vault,
      source: CurrencyCode.usd,
      target: CurrencyCode.brl,
      date: LocalDate(2026, 8, 17),
      amountMinor: 10000,
    );
    expect(converted!.minorUnits, 50000);
    expect(converted.estimated, isFalse);
  });

  test(
    'missing FX is explicit instead of silently changing currency',
    () async {
      await database.customStatement('DELETE FROM fx_rate_cache');
      final freshService = DashboardService(
        repository: DriftDashboardRepository(database),
        recurring: service.recurring,
      );
      final report = await freshService.load(
        vaultId: fixture.vault,
        reportingCurrency: CurrencyCode.brl,
        asOf: LocalDate(2026, 8, 17),
      );
      expect(report.isComplete, isFalse);
      expect(report.missingRates, contains(CurrencyCode.usd));
      expect(report.availableMoneyMinor, 136000);
    },
  );

  test('one thousand local splits aggregate under one second', () async {
    final engine = LedgerEngine();
    for (var index = 0; index < 1000; index++) {
      await ledger.save(
        engine.expense(
          vaultId: fixture.vault,
          pocket: fixture.bank,
          amount: Money(currency: CurrencyCode.brl, minorUnits: 1),
          categoryId: fixture.category,
          date: LocalDate(2026, 8, 17),
          now: UtcInstant.fromEpochMicroseconds(10000 + index),
        ),
      );
    }
    final stopwatch = Stopwatch()..start();
    final report = await service.load(
      vaultId: fixture.vault,
      reportingCurrency: CurrencyCode.brl,
      asOf: LocalDate(2026, 8, 17),
    );
    stopwatch.stop();
    expect(report.expenseMinor, 21000);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}

Future<_Fixture> _seed(
  EquisDatabase database,
  DriftLedgerRepository ledger,
) async {
  final vault = EntityId.generate();
  final bankAccount = EntityId.generate();
  final cashAccount = EntityId.generate();
  final walletAccount = EntityId.generate();
  final cardAccount = EntityId.generate();
  final bankId = EntityId.generate();
  final cashId = EntityId.generate();
  final usdWalletId = EntityId.generate();
  final cardId = EntityId.generate();
  final category = EntityId.generate();
  await database.customStatement(
    'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, 1, 1)',
    [vault.value, 'Local', 'BRL', 'America/Sao_Paulo'],
  );
  await database.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES "
    "('BRL', 'currency.brl', 'R\$', 2), ('USD', 'currency.usd', 'US\$', 2)",
  );
  for (final account in [
    (bankAccount, 'Bank', 'checking', 'asset'),
    (cashAccount, 'Cash', 'cash', 'asset'),
    (walletAccount, 'USD Wallet', 'digital_wallet', 'asset'),
    (cardAccount, 'Card', 'credit_card', 'liability'),
  ]) {
    await database.customStatement(
      'INSERT INTO accounts '
      '(id, vault_id, name, account_type, nature, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 1, 1)',
      [account.$1.value, vault.value, account.$2, account.$3, account.$4],
    );
  }
  for (final pocket in [
    (bankId, bankAccount, 'BRL'),
    (cashId, cashAccount, 'BRL'),
    (usdWalletId, walletAccount, 'USD'),
    (cardId, cardAccount, 'BRL'),
  ]) {
    await database.customStatement(
      'INSERT INTO account_pockets (id, account_id, currency_code, is_default) '
      'VALUES (?, ?, ?, 1)',
      [pocket.$1.value, pocket.$2.value, pocket.$3],
    );
  }
  await database.customStatement(
    'INSERT INTO categories '
    '(id, vault_id, category_type, custom_name, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, 1, 1)',
    [category.value, vault.value, 'expense', 'Daily'],
  );
  await database.customStatement(
    'INSERT INTO fx_rate_cache '
    '(base_currency, quote_currency, rate_date, rate, provider, fetched_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    ['USD', 'BRL', '2026-08-17', '5', 'fixture', 1],
  );
  final bank = LedgerPocket(
    id: bankId,
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  final cash = LedgerPocket(
    id: cashId,
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  final usdWallet = LedgerPocket(
    id: usdWalletId,
    currency: CurrencyCode.usd,
    nature: AccountNature.asset,
  );
  final card = LedgerPocket(
    id: cardId,
    currency: CurrencyCode.brl,
    nature: AccountNature.liability,
  );
  final engine = LedgerEngine();
  const now = UtcInstant.fromEpochMicroseconds(1000);
  final date = LocalDate(2026, 8, 10);
  final prior = LocalDate(2026, 7, 10);
  Money brl(int value) => Money(currency: CurrencyCode.brl, minorUnits: value);
  await ledger.save(
    engine.openingBalance(
      vaultId: vault,
      pocket: bank,
      signedAmount: brl(100000),
      date: prior,
      now: now,
    ),
  );
  await ledger.save(
    engine.openingBalance(
      vaultId: vault,
      pocket: usdWallet,
      signedAmount: Money(currency: CurrencyCode.usd, minorUnits: 10000),
      date: prior,
      now: now,
    ),
  );
  await ledger.save(
    engine.income(
      vaultId: vault,
      pocket: bank,
      amount: brl(50000),
      categoryId: category,
      date: date,
      now: now,
    ),
  );
  await ledger.save(
    engine.expense(
      vaultId: vault,
      pocket: bank,
      amount: brl(10000),
      categoryId: category,
      date: date,
      now: now,
    ),
  );
  final purchase = engine.creditCardPurchase(
    vaultId: vault,
    cardPocket: card,
    amount: brl(12000),
    categoryId: category,
    date: date,
    now: now,
  );
  await ledger.save(purchase);
  await ledger.save(
    engine.refund(
      vaultId: vault,
      pocket: card,
      amount: brl(2000),
      originalCategoryId: category,
      originalTransactionId: purchase.id,
      date: LocalDate(2026, 8, 11),
      now: now,
    ),
  );
  await ledger.save(
    engine.transfer(
      vaultId: vault,
      source: bank,
      destination: cash,
      amount: brl(5000),
      date: date,
      now: now,
    ),
  );
  await ledger.save(
    engine.creditCardPayment(
      vaultId: vault,
      bankPocket: bank,
      cardPocket: card,
      amount: brl(4000),
      date: LocalDate(2026, 8, 12),
      now: now,
    ),
  );
  await ledger.save(
    engine.expense(
      vaultId: vault,
      pocket: bank,
      amount: brl(9999),
      categoryId: category,
      date: LocalDate(2026, 8, 20),
      now: now,
      status: LedgerTransactionStatus.pending,
    ),
  );
  final planId = EntityId.generate();
  await database.customStatement(
    'INSERT INTO installment_plans '
    '(id, vault_id, account_pocket_id, category_id, currency_code, total_minor, '
    'installment_count, first_installment_date, status, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    [
      planId.value,
      vault.value,
      cardId.value,
      category.value,
      'BRL',
      1000,
      2,
      '2026-08-25',
      'active',
    ],
  );
  await database.customStatement(
    'INSERT INTO installments '
    '(id, installment_plan_id, installment_number, amount_minor, expected_date, status) '
    'VALUES (?, ?, 1, 500, ?, ?)',
    [EntityId.generate().value, planId.value, '2026-08-25', 'scheduled'],
  );
  return _Fixture(
    vault: vault,
    bank: bank,
    usdWallet: usdWallet,
    card: card,
    category: category,
  );
}

Future<String> _transactionFingerprint(EquisDatabase database) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS total, COALESCE(SUM(revision), 0) AS revisions, '
        'COALESCE(SUM(updated_at), 0) AS updated FROM transactions',
      )
      .getSingle();
  return '${row.read<int>('total')}|${row.read<int>('revisions')}|'
      '${row.read<int>('updated')}';
}

final class _Fixture {
  const _Fixture({
    required this.vault,
    required this.bank,
    required this.usdWallet,
    required this.card,
    required this.category,
  });

  final EntityId vault;
  final LedgerPocket bank;
  final LedgerPocket usdWallet;
  final LedgerPocket card;
  final EntityId category;
}
