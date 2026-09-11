import 'dart:io';

import 'package:drift/native.dart';
import 'package:equis/application/services/recurring_transaction_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/recurring/recurrence_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide RecurringRule, RecurringTemplate;
import 'package:equis/infrastructure/persistence/dao/ledger_balance_reader.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_recurring_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftRecurringRepository repository;
  late RecurringTransactionService service;
  late _Fixture fixture;
  Directory? restartDirectory;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    final ledger = DriftLedgerRepository(database);
    repository = DriftRecurringRepository(database: database, ledger: ledger);
    service = RecurringTransactionService(
      repository: repository,
      ledger: ledger,
      unitOfWork: DriftLocalUnitOfWork(database),
    );
    fixture = await _seed(database);
  });

  tearDown(() async {
    await database.close();
    final directory = restartDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'upcoming projection is bounded and creates no transaction rows',
    () async {
      final schedule = _monthlySchedule(fixture);
      await service.create(schedule);
      final upcoming = await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 12, 31),
        limit: 5,
      );
      expect(upcoming, hasLength(5));
      expect(upcoming.first.recurrenceDate, LocalDate(2026, 1, 31));
      expect(upcoming[1].recurrenceDate, LocalDate(2026, 2, 28));
      expect(
        await database.customSelect('SELECT id FROM transactions').get(),
        isEmpty,
      );
      await expectLater(
        service.upcoming(
          vaultId: fixture.vault,
          from: LocalDate(2026, 1, 1),
          through: LocalDate(2028, 1, 2),
        ),
        throwsRangeError,
      );
    },
  );

  test(
    'confirm is idempotent and unique recurrence key blocks duplicates',
    () async {
      final schedule = _monthlySchedule(fixture);
      await service.create(schedule);
      final occurrence = (await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 2, 28),
      )).first;
      final first = await service.confirm(occurrence, now: fixture.now);
      final second = await service.confirm(occurrence, now: fixture.now);
      expect(second.id, first.id);
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS total FROM transactions')
                .getSingle())
            .read<int>('total'),
        1,
      );
      await expectLater(
        database.customStatement(
          'INSERT INTO transactions '
          '(id, vault_id, transaction_type, status, financial_date, recurring_rule_id, '
          'recurrence_date, revision, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 1, 2, 2)',
          [
            EntityId.generate().value,
            fixture.vault.value,
            'expense',
            'pending',
            occurrence.recurrenceDate.toString(),
            schedule.rule.id.value,
            occurrence.recurrenceDate.toString(),
          ],
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'skip, reschedule, and modify one affect only their occurrence',
    () async {
      final schedule = _monthlySchedule(fixture);
      await service.create(schedule);
      final occurrences = await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 3, 31),
      );
      final skipped = await service.skip(occurrences[0], now: fixture.now);
      expect(skipped.status, LedgerTransactionStatus.cancelled);
      final rescheduled = await service.reschedule(
        occurrences[1],
        newDate: LocalDate(2026, 3, 3),
        now: fixture.now,
      );
      expect(rescheduled.financialDate, LocalDate(2026, 3, 3));
      expect(rescheduled.recurrenceDate, LocalDate(2026, 2, 28));
      final replacement = _template(fixture, amount: 9900, title: 'Only once');
      final modified = await service.modifyOne(
        occurrences[2],
        replacement: replacement,
        now: fixture.now,
      );
      expect(modified.title, 'Only once');
      expect(modified.movements.single.amountMinor, -9900);
      expect(rescheduled.affectsBalances, isFalse);
      expect(modified.affectsBalances, isFalse);
      expect(
        await LedgerBalanceReader(database).rebuildAll(),
        isNot(contains(fixture.pocket.value)),
      );
      final reloaded = await repository.find(schedule.rule.id);
      expect(reloaded!.template.title, schedule.template.title);
      expect(reloaded.template.movements.single.amountMinor, -7250);
    },
  );

  test(
    'modify future splits the series and end disables its successor',
    () async {
      final schedule = _monthlySchedule(fixture);
      await service.create(schedule);
      final successor = await service.modifyFuture(
        schedule,
        effectiveFrom: LocalDate(2026, 4, 30),
        pattern: const RecurrencePattern(
          frequency: RecurrenceFrequency.monthly,
          interval: 2,
        ),
        template: _template(fixture, amount: 8000, title: 'Future rent'),
        now: fixture.now,
      );
      final predecessor = await repository.find(schedule.rule.id);
      expect(predecessor!.rule.endsOn, LocalDate(2026, 4, 29));
      expect(successor.rule.id, isNot(schedule.rule.id));
      expect(successor.rule.startsOn, LocalDate(2026, 4, 30));
      expect(successor.template.movements.single.amountMinor, -8000);
      await service.end(
        successor,
        lastDate: LocalDate(2026, 8, 30),
        now: fixture.now,
      );
      expect((await repository.find(successor.rule.id))!.rule.enabled, isFalse);
    },
  );

  test('rules and pending overrides survive a local offline restart', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('equis-recurring-');
    restartDirectory = directory;
    final file = File('${directory.path}${Platform.pathSeparator}vault.sqlite');
    database = EquisDatabase(NativeDatabase(file));
    var ledger = DriftLedgerRepository(database);
    repository = DriftRecurringRepository(database: database, ledger: ledger);
    service = RecurringTransactionService(
      repository: repository,
      ledger: ledger,
      unitOfWork: DriftLocalUnitOfWork(database),
    );
    fixture = await _seed(database);
    final schedule = _monthlySchedule(fixture);
    await service.create(schedule);
    final occurrence = (await service.upcoming(
      vaultId: fixture.vault,
      from: LocalDate(2026, 1, 1),
      through: LocalDate(2026, 1, 31),
    )).single;
    await service.reschedule(
      occurrence,
      newDate: LocalDate(2026, 2, 2),
      now: fixture.now,
    );
    await database.close();

    database = EquisDatabase(NativeDatabase(file));
    ledger = DriftLedgerRepository(database);
    repository = DriftRecurringRepository(database: database, ledger: ledger);
    service = RecurringTransactionService(
      repository: repository,
      ledger: ledger,
      unitOfWork: DriftLocalUnitOfWork(database),
    );
    final restored = await service.upcoming(
      vaultId: fixture.vault,
      from: LocalDate(2026, 1, 1),
      through: LocalDate(2026, 2, 28),
    );
    expect(restored.first.state, ScheduledOccurrenceState.pending);
    expect(restored.first.scheduledDate, LocalDate(2026, 2, 2));
  });
}

RecurringSchedule _monthlySchedule(_Fixture fixture) => RecurringSchedule(
  rule: RecurringRule(
    id: EntityId.generate(),
    vaultId: fixture.vault,
    name: 'Rent',
    pattern: const RecurrencePattern(frequency: RecurrenceFrequency.monthly),
    timezone: 'America/Sao_Paulo',
    startsOn: LocalDate(2026, 1, 31),
    nextOccurrence: LocalDate(2026, 1, 31),
    createdAt: fixture.now,
    updatedAt: fixture.now,
  ),
  template: _template(fixture, amount: 7250, title: 'Rent'),
);

RecurringTemplate _template(
  _Fixture fixture, {
  required int amount,
  required String title,
}) => RecurringTemplate(
  transactionType: LedgerTransactionType.expense,
  title: title,
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
      categoryId: fixture.category,
      money: Money(currency: CurrencyCode.brl, minorUnits: amount),
      sortOrder: 0,
    ),
  ],
);

Future<_Fixture> _seed(EquisDatabase database) async {
  final vault = EntityId.generate();
  final account = EntityId.generate();
  final pocket = EntityId.generate();
  final category = EntityId.generate();
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
  await database.customStatement(
    'INSERT INTO categories '
    '(id, vault_id, category_type, custom_name, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, 1, 1)',
    [category.value, vault.value, 'expense', 'Housing'],
  );
  return _Fixture(
    vault: vault,
    pocket: pocket,
    category: category,
    now: UtcInstant.fromEpochMicroseconds(1000),
  );
}

final class _Fixture {
  const _Fixture({
    required this.vault,
    required this.pocket,
    required this.category,
    required this.now,
  });
  final EntityId vault;
  final EntityId pocket;
  final EntityId category;
  final UtcInstant now;
}
