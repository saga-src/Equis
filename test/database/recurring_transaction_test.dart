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
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_mutation_recorder.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
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
    'archived account rejects stale recurring materialization and new rule',
    () async {
      final schedule = _monthlySchedule(fixture);
      await service.create(schedule);
      final occurrence = (await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 1, 31),
      )).single;
      await database.customStatement(
        "UPDATE accounts SET archived = 1, closed_on = '2026-01-01' "
        'WHERE id = (SELECT account_id FROM account_pockets WHERE id = ?)',
        [fixture.pocket.value],
      );
      await expectLater(
        service.confirm(occurrence, now: fixture.now),
        throwsStateError,
      );
      await expectLater(
        service.create(_monthlySchedule(fixture)),
        throwsStateError,
      );
      await service.end(
        schedule,
        lastDate: LocalDate(2026, 1, 31),
        now: fixture.now,
      );
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS total FROM transactions')
                .getSingle())
            .read<int>('total'),
        0,
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
    'modify future preserves identity and end disables the same series',
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
      expect(predecessor!.versions, hasLength(2));
      expect(successor.rule.id, schedule.rule.id);
      expect(successor.rule.startsOn, LocalDate(2026, 1, 31));
      expect(
        successor
            .configurationAt(LocalDate(2026, 4, 30))
            .template
            .movements
            .single
            .amountMinor,
        -8000,
      );
      await service.end(
        successor,
        lastDate: LocalDate(2026, 8, 30),
        now: fixture.now,
      );
      expect((await repository.find(successor.rule.id))!.rule.enabled, isFalse);
    },
  );

  test('edit and delete enqueue the same identity atomically', () async {
    await database.customStatement(
      'INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, ?, 1, 1)',
      [fixture.vault.value, '11111111-1111-4111-8111-111111111111'],
    );
    final metadata = DriftSyncMetadataStore(database);
    final store = DriftSyncAggregateStore(
      database: database,
      metadata: metadata,
    );
    repository = DriftRecurringRepository(
      database: database,
      ledger: service.ledger,
      syncRecorder: DriftSyncMutationRecorder(
        database: database,
        aggregates: store,
        metadata: metadata,
      ),
    );
    service = RecurringTransactionService(
      repository: repository,
      ledger: service.ledger,
      unitOfWork: service.unitOfWork,
    );
    final original = _monthlySchedule(fixture);
    await service.create(original);
    final edited = await service.modifyFuture(
      original,
      effectiveFrom: LocalDate(2026, 4, 30),
      now: fixture.now,
    );
    await service.delete(edited, now: fixture.now);
    final pending = await metadata.pendingFor(
      vaultId: fixture.vault.value,
      entityType: SyncEntityType.recurringRule,
      recordId: original.rule.id.value,
    );
    expect(pending!.operation, SyncOperation.delete);
    expect(pending.newRevision, 3);
    expect((await repository.find(original.rule.id))!.versions, hasLength(2));
    expect(
      (await database
              .customSelect('SELECT COUNT(*) AS total FROM transactions')
              .getSingle())
          .read<int>('total'),
      0,
    );
    expect(
      await database
          .customSelect('SELECT * FROM sync_outbox_dependencies')
          .get(),
      isNotEmpty,
    );
  });

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

  test(
    'RC10–11 stable edit preserves snapshots, occupied keys and day-31 anchor',
    () async {
      final original = _monthlySchedule(fixture);
      await service.create(original);
      final occurrences = await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 8, 31),
      );
      await service.confirm(occurrences[0], now: fixture.now);
      await service.skip(occurrences[1], now: fixture.now);
      await service.modifyOne(
        occurrences[3],
        replacement: _template(fixture, amount: 9900, title: 'Custom'),
        now: fixture.now,
      );
      await service.reschedule(
        occurrences[2],
        newDate: LocalDate(2026, 5, 2),
        now: fixture.now,
      );
      final before = await database
          .customSelect('SELECT * FROM transactions ORDER BY id')
          .get();
      final latest = (await repository.find(original.rule.id))!;
      final edited = await service.modifyFuture(
        latest,
        effectiveFrom: LocalDate(2026, 4, 30),
        template: _template(fixture, amount: 8000, title: 'New'),
        now: fixture.now,
      );
      expect(edited.rule.id, original.rule.id);
      expect(
        edited.configurationAt(LocalDate(2026, 4, 30)).anchorOn,
        LocalDate(2026, 1, 31),
      );
      expect(
        (await database
                .customSelect('SELECT * FROM transactions ORDER BY id')
                .get())
            .map((r) => r.data),
        before.map((r) => r.data),
      );
      final may = await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 5, 1),
        through: LocalDate(2026, 5, 31),
      );
      expect(may.map((o) => o.scheduledDate), [
        LocalDate(2026, 5, 2),
        LocalDate(2026, 5, 31),
      ]);
      expect(may.first.transaction!.title, 'Rent');
      final stale = occurrences[4];
      final confirmed = await service.confirm(stale, now: fixture.now);
      expect(confirmed.movements.single.amountMinor, -8000);
      final custom = await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 4, 1),
        through: LocalDate(2026, 4, 30),
      );
      expect(custom.single.transaction!.title, 'Custom');
      expect(custom.single.template.title, 'Custom');
      expect(custom.single.template.movements.single.amountMinor, -9900);
      final after = (await repository.find(original.rule.id))!;
      await service.modifyFuture(
        after,
        effectiveFrom: LocalDate(2026, 4, 30),
        pattern: const RecurrencePattern(frequency: RecurrenceFrequency.weekly),
        now: fixture.now,
      );
      final changed = await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 4, 1),
        through: LocalDate(2026, 5, 31),
      );
      expect(
        changed.where((o) => o.transaction?.title == 'Custom'),
        hasLength(1),
      );
      expect(
        changed.where((o) => o.recurrenceDate == LocalDate(2026, 5, 31)),
        hasLength(1),
      );
      await expectLater(
        service.modifyOne(
          occurrences[5],
          replacement: _template(fixture, amount: 5555, title: 'Stale'),
          now: fixture.now,
        ),
        throwsStateError,
      );
    },
  );

  test('repository rejects erasure of edited history atomically', () async {
    final original = _monthlySchedule(fixture);
    await service.create(original);
    final edited = await service.modifyFuture(
      original,
      effectiveFrom: LocalDate(2026, 4, 30),
      template: _template(fixture, amount: 8000, title: 'Future'),
      now: fixture.now,
    );
    await expectLater(
      repository.save(
        RecurringSchedule(
          rule: edited.rule.revise(at: fixture.now),
          template: edited.template,
        ),
      ),
      throwsStateError,
    );
    final saved = (await repository.find(original.rule.id))!;
    expect(saved.rule.revision, edited.rule.revision);
    expect(saved.versions, hasLength(2));
  });

  test('concurrent confirmations preserve a single occurrence', () async {
    final original = _monthlySchedule(fixture);
    await service.create(original);
    final occurrence = (await service.upcoming(
      vaultId: fixture.vault,
      from: LocalDate(2026, 1, 1),
      through: LocalDate(2026, 1, 31),
    )).single;
    final confirmed = await Future.wait([
      service.confirm(occurrence, now: fixture.now),
      service.confirm(occurrence, now: fixture.now),
    ]);
    expect(confirmed.first.id, confirmed.last.id);
    expect(
      await database.customSelect('SELECT id FROM transactions').get(),
      hasLength(1),
    );
  });

  test(
    'RC12 delete retains financial rows and rejects stale/fabricated resurrection',
    () async {
      final schedule = _monthlySchedule(fixture);
      await service.create(schedule);
      final occurrence = (await service.upcoming(
        vaultId: fixture.vault,
        from: LocalDate(2026, 1, 1),
        through: LocalDate(2026, 1, 31),
      )).single;
      await service.confirm(occurrence, now: fixture.now);
      final latest = (await repository.find(schedule.rule.id))!;
      await service.delete(latest, now: fixture.now);
      expect(await service.listRules(fixture.vault), isEmpty);
      final transactionId = EntityId.parse(
        (await database.customSelect('SELECT id FROM transactions').getSingle())
            .read<String>('id'),
      );
      expect(await service.ledger.find(transactionId), isNotNull);
      await expectLater(
        service.modifyFuture(
          latest,
          effectiveFrom: LocalDate(2026, 4, 30),
          now: fixture.now,
        ),
        throwsA(anything),
      );
      final tombstone = (await repository.find(schedule.rule.id))!;
      await expectLater(
        repository.save(
          RecurringSchedule(
            rule: tombstone.rule.revise(enabled: true, at: fixture.now),
            template: tombstone.template,
          ),
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'recurring format 2 round-trips backup and guards higher-revision legacy payload',
    () async {
      final original = _monthlySchedule(fixture);
      await service.create(original);
      final store = DriftSyncAggregateStore(
        database: database,
        metadata: DriftSyncMetadataStore(database),
      );
      final legacy = (await store.loadPayload(
        vaultId: fixture.vault.value,
        entityType: SyncEntityType.recurringRule,
        recordId: original.rule.id.value,
      ))!;
      final edited = await service.modifyFuture(
        original,
        effectiveFrom: LocalDate(2026, 4, 30),
        template: _template(fixture, amount: 8000, title: 'Future'),
        now: fixture.now,
      );
      final payload = (await store.loadPayload(
        vaultId: fixture.vault.value,
        entityType: SyncEntityType.recurringRule,
        recordId: original.rule.id.value,
      ))!;
      expect(payload['format_version'], 2);
      final snapshot = await VaultLogicalSnapshotStore(
        database,
      ).capture(fixture.vault.value);
      final destination = EquisDatabase(NativeDatabase.memory());
      addTearDown(destination.close);
      await VaultLogicalSnapshotStore(destination).restore(snapshot);
      final restoredRepository = DriftRecurringRepository(
        database: destination,
        ledger: DriftLedgerRepository(destination),
      );
      expect(
        (await restoredRepository.find(original.rule.id))!.versions,
        hasLength(2),
      );
      await DriftSyncAggregateStore(
        database: destination,
        metadata: DriftSyncMetadataStore(destination),
      ).applyRemote(
        vaultId: fixture.vault.value,
        entityType: SyncEntityType.recurringRule,
        recordId: original.rule.id.value,
        revision: edited.rule.revision,
        serverVersion: 1,
        isDeleted: false,
        payload: payload,
      );
      final synchronized = (await restoredRepository.find(original.rule.id))!;
      expect(synchronized.versions, hasLength(2));
      expect(
        synchronized.configurationAt(LocalDate(2026, 5, 31)).template.title,
        'Future',
      );
      (legacy['root'] as Map)['revision'] = 99;
      final reconciliation = await store.reconcileRemote(
        vaultId: fixture.vault.value,
        entityType: SyncEntityType.recurringRule,
        recordId: original.rule.id.value,
        revision: 99,
        serverVersion: 9,
        isDeleted: false,
        payload: legacy,
      );
      expect(reconciliation.conflictDetected, isTrue);
      expect(
        (await repository.find(original.rule.id))!.rule.revision,
        edited.rule.revision,
      );
    },
  );
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
