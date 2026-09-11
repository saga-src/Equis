import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:equis/application/services/dashboard_service.dart';
import 'package:equis/application/services/recurring_transaction_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/ledger/transaction_search.dart';
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
import 'package:equis/infrastructure/repositories/drift_transaction_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'encrypted database cold reopen and integrity check stay bounded',
    () async {
      final temporary = await Directory.systemTemp.createTemp('equis-startup-');
      addTearDown(() => temporary.delete(recursive: true));
      final file = File(
        '${temporary.path}${Platform.pathSeparator}vault.sqlite',
      );
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      var database = EquisDatabase(openEncryptedDatabase(file, key));
      await database.customSelect('SELECT 1').getSingle();
      await database.close();

      final stopwatch = Stopwatch()..start();
      database = EquisDatabase(openEncryptedDatabase(file, key));
      final result = await database
          .customSelect('PRAGMA integrity_check')
          .getSingle();
      stopwatch.stop();
      addTearDown(database.close);

      expect(result.read<String>('integrity_check'), 'ok');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      // ignore: avoid_print
      print('PHASE22 encrypted_reopen_ms=${stopwatch.elapsedMilliseconds}');
    },
  );

  test(
    'twenty-thousand-row save, search, and report latency stay bounded',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final fixture = await _seedLarge(database, 20000);
      final ledger = DriftLedgerRepository(database);
      final history = DriftTransactionHistoryRepository(
        database: database,
        ledger: ledger,
      );
      final recurring = DriftRecurringRepository(
        database: database,
        ledger: ledger,
      );
      final dashboardRepository = DriftDashboardRepository(database);
      final dashboard = DashboardService(
        repository: dashboardRepository,
        recurring: RecurringTransactionService(
          repository: recurring,
          ledger: ledger,
          unitOfWork: DriftLocalUnitOfWork(database),
        ),
      );

      final saveWatch = Stopwatch()..start();
      await ledger.save(
        LedgerEngine().expense(
          vaultId: fixture.vault,
          pocket: fixture.pocket,
          amount: Money(currency: CurrencyCode.brl, minorUnits: 1234),
          categoryId: fixture.category,
          date: LocalDate(2026, 8, 22),
          now: UtcInstant.fromEpochMicroseconds(30000),
        ),
      );
      saveWatch.stop();

      final searchWatch = Stopwatch()..start();
      final search = await history.search(
        TransactionSearchFilter(
          vaultId: fixture.vault,
          merchantQuery: 'Fixture 199',
          categoryId: fixture.category,
        ),
      );
      searchWatch.stop();

      final splitWatch = Stopwatch()..start();
      final measuredSplits = await dashboardRepository.loadSplits(
        vaultId: fixture.vault,
        from: LocalDate(2026, 8, 1),
        through: LocalDate(2026, 8, 31),
        asOf: LocalDate(2026, 8, 31),
      );
      splitWatch.stop();
      final balanceWatch = Stopwatch()..start();
      await dashboardRepository.loadAccountBalances(
        vaultId: fixture.vault,
        asOf: LocalDate(2026, 8, 31),
      );
      balanceWatch.stop();
      // ignore: avoid_print
      print(
        'PHASE22 split_rows=${measuredSplits.length} '
        'split_query_ms=${splitWatch.elapsedMilliseconds} '
        'balance_query_ms=${balanceWatch.elapsedMilliseconds}',
      );

      final reportWatch = Stopwatch()..start();
      final report = await dashboard.load(
        vaultId: fixture.vault,
        reportingCurrency: CurrencyCode.brl,
        asOf: LocalDate(2026, 8, 31),
      );
      reportWatch.stop();

      final quickCheck = await database
          .customSelect('PRAGMA quick_check')
          .getSingle();
      final foreignKeyFailures = await database
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(search.items, isNotEmpty);
      expect(report.expenseMinor, 20000 * 100 + 1234);
      expect(quickCheck.read<String>('quick_check'), 'ok');
      expect(foreignKeyFailures, isEmpty);
      expect(saveWatch.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(searchWatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(reportWatch.elapsed, lessThan(const Duration(seconds: 3)));
      // ignore: avoid_print
      print(
        'PHASE22 rows=20000 save_ms=${saveWatch.elapsedMilliseconds} '
        'search_ms=${searchWatch.elapsedMilliseconds} '
        'report_ms=${reportWatch.elapsedMilliseconds}',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<_LargeFixture> _seedLarge(EquisDatabase database, int count) async {
  const vaultValue = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const accountValue = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  const pocketValue = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
  const categoryValue = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
  await database.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'currency.brl', 'R\$', 2)",
  );
  await database.customStatement(
    "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Large', 'BRL', 'America/Sao_Paulo', 1, 1)",
    [vaultValue],
  );
  await database.customStatement(
    "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Checking', 'checking', 'asset', 1, 1)",
    [accountValue, vaultValue],
  );
  await database.customStatement(
    "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'BRL', 1)",
    [pocketValue, accountValue],
  );
  await database.customStatement(
    "INSERT INTO categories (id, vault_id, category_type, custom_name, created_at, updated_at) VALUES (?, ?, 'expense', 'Daily', 1, 1)",
    [categoryValue, vaultValue],
  );

  await database.transaction(() async {
    const sequence =
        'WITH RECURSIVE seq(i) AS (VALUES(0) UNION ALL SELECT i + 1 FROM seq WHERE i + 1 < ?) ';
    await database.customStatement(
      '${sequence}INSERT INTO transactions '
      '(id, vault_id, transaction_type, status, title, financial_date, revision, created_at, updated_at) '
      "SELECT printf('018f47c2-9b72-7cc1-8b83-%012x', i * 3 + 100), ?, 'expense', 'cleared', "
      "'Fixture ' || i, printf('2026-08-%02d', i % 28 + 1), 1, i + 1000, i + 1000 FROM seq",
      [count, vaultValue],
    );
    await database.customStatement(
      '${sequence}INSERT INTO account_movements '
      '(id, transaction_id, account_pocket_id, amount_minor, sort_order) '
      "SELECT printf('018f47c2-9b72-7cc1-8b83-%012x', i * 3 + 101), "
      "printf('018f47c2-9b72-7cc1-8b83-%012x', i * 3 + 100), ?, -100, 0 FROM seq",
      [count, pocketValue],
    );
    await database.customStatement(
      '${sequence}INSERT INTO transaction_splits '
      '(id, transaction_id, category_id, currency_code, amount_minor, sort_order) '
      "SELECT printf('018f47c2-9b72-7cc1-8b83-%012x', i * 3 + 102), "
      "printf('018f47c2-9b72-7cc1-8b83-%012x', i * 3 + 100), ?, 'BRL', 100, 0 FROM seq",
      [count, categoryValue],
    );
  });
  return _LargeFixture(
    vault: EntityId.parse(vaultValue),
    pocket: LedgerPocket(
      id: EntityId.parse(pocketValue),
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    ),
    category: EntityId.parse(categoryValue),
  );
}

final class _LargeFixture {
  const _LargeFixture({
    required this.vault,
    required this.pocket,
    required this.category,
  });

  final EntityId vault;
  final LedgerPocket pocket;
  final EntityId category;
}
