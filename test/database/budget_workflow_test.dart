import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:equis/application/ports/budget_repository.dart';
import 'package:equis/application/services/budget_service.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide BudgetMonthlyConfiguration;
import 'package:equis/infrastructure/repositories/drift_budget_repository.dart';
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/presentation/budgets/budget_controller.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_mutation_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftBudgetRepository repository;
  late BudgetService service;
  late _Fixture fixture;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    final ledger = DriftLedgerRepository(database);
    final metadata = DriftSyncMetadataStore(database);
    repository = DriftBudgetRepository(
      database,
      syncRecorder: DriftSyncMutationRecorder(
        database: database,
        metadata: metadata,
        aggregates: DriftSyncAggregateStore(
          database: database,
          metadata: metadata,
        ),
      ),
    );
    service = BudgetService(
      repository: repository,
      reporting: DriftDashboardRepository(database),
    );
    fixture = await _seed(database, ledger);
  });

  tearDown(() => database.close());

  test(
    'historical category ancestors survive archive and soft deletion',
    () async {
      final budget = await _create(
        service,
        fixture,
        name: 'Past taxonomy',
        limit: 20000,
        scope: BudgetScope(
          categories: [BudgetCategoryScope(categoryId: fixture.parentCategory)],
        ),
      );
      await database.customStatement(
        'UPDATE categories SET archived = 1, deleted_at = 2 WHERE id = ?',
        [fixture.parentCategory.value],
      );
      final progress = (await service.loadProgress(
        vaultId: fixture.vault,
        asOf: LocalDate(2026, 9, 15),
        month: BudgetMonth(2026, 8),
      )).single;
      expect(progress.budget.id, budget.id);
      expect(progress.usedMinor, 13000);
    },
  );

  test(
    'monthly service edits preserve earlier months and future overrides including filters',
    () async {
      var budget = await _create(
        service,
        fixture,
        name: 'Plan',
        limit: 100000,
        scope: BudgetScope(),
      );
      final original = budget;
      Future<void> edit(
        int month,
        int amount,
        BudgetMonthlyEditScope editScope,
        BudgetScope scope,
        int threshold,
      ) async {
        budget = await service.editMonthly(
          existing: budget,
          month: BudgetMonth(2026, month),
          name: 'Shared name',
          scope: editScope,
          configuration: BudgetMonthlyConfiguration(
            amountMinor: amount,
            warningThresholdBps: threshold,
            scope: scope,
          ),
          now: UtcInstant.fromDateTime(DateTime.utc(2026, 8, 17)),
        );
      }

      await edit(
        8,
        120000,
        BudgetMonthlyEditScope.onlyMonth,
        BudgetScope(accountIds: {fixture.bankAccount}),
        7500,
      );
      await edit(
        9,
        150000,
        BudgetMonthlyEditScope.onlyMonth,
        BudgetScope(tagIds: {fixture.plannedTag}),
        6000,
      );
      await edit(
        8,
        120000,
        BudgetMonthlyEditScope.fromMonth,
        BudgetScope(
          categories: [BudgetCategoryScope(categoryId: fixture.parentCategory)],
        ),
        7000,
      );
      final history = await repository.loadMonthlyHistory(budget.id);
      expect(history.resolve(BudgetMonth(2026, 7))!.amountMinor, 100000);
      expect(history.resolve(BudgetMonth(2026, 8))!.amountMinor, 120000);
      expect(history.resolve(BudgetMonth(2026, 9))!.amountMinor, 150000);
      expect(history.resolve(BudgetMonth(2026, 10))!.amountMinor, 120000);
      expect(history.resolve(BudgetMonth(2026, 9))!.scope.tagIds, {
        fixture.plannedTag,
      });
      expect(history.resolve(BudgetMonth(2026, 9))!.warningThresholdBps, 6000);
      expect(history.resolve(BudgetMonth(2026, 10))!.warningThresholdBps, 7000);
      expect((await repository.find(budget.id))!.name, 'Shared name');
      await expectLater(
        service.editMonthly(
          existing: original,
          month: BudgetMonth(2026, 8),
          name: 'Stale name',
          scope: BudgetMonthlyEditScope.onlyMonth,
          configuration: BudgetMonthlyConfiguration(
            amountMinor: 1,
            warningThresholdBps: 1,
            scope: BudgetScope(),
          ),
          now: UtcInstant.fromDateTime(DateTime.utc(2026, 8, 17)),
        ),
        throwsA(isA<BudgetRevisionConflict>()),
      );
      expect((await repository.find(budget.id))!.name, 'Shared name');
    },
  );

  test(
    'selected competence cuts actual usage inclusively and retains deleted history',
    () async {
      final budget = await _create(
        service,
        fixture,
        name: 'History',
        limit: 20000,
        scope: BudgetScope(accountIds: {fixture.bankAccount}),
      );
      final pocket =
          (await database
                  .customSelect(
                    'SELECT id FROM account_pockets WHERE account_id = ?',
                    variables: [Variable(fixture.bankAccount.value)],
                  )
                  .getSingle())
              .read<String>('id');
      final ledger = DriftLedgerRepository(database);
      for (final entry in [
        (LocalDate(2026, 8, 17), 2000),
        (LocalDate(2026, 8, 18), 3000),
        (LocalDate(2026, 8, 31), 4000),
        (LocalDate(2026, 9, 1), 5000),
      ]) {
        await ledger.save(
          LedgerEngine().expense(
            vaultId: fixture.vault,
            pocket: LedgerPocket(
              id: EntityId.parse(pocket),
              currency: CurrencyCode.brl,
              nature: AccountNature.asset,
            ),
            amount: Money(currency: CurrencyCode.brl, minorUnits: entry.$2),
            categoryId: fixture.parentCategory,
            date: entry.$1,
            now: UtcInstant.fromDateTime(DateTime.utc(2026, 8, 17)),
          ),
        );
      }
      Future<BudgetProgress> load(
        LocalDate asOf,
        int month, {
        bool deleted = false,
      }) async => (await service.loadProgress(
        vaultId: fixture.vault,
        asOf: asOf,
        month: BudgetMonth(2026, month),
        includeDeleted: deleted,
      )).single;
      final current = await load(LocalDate(2026, 8, 17), 8);
      expect(
        current.usedMinor,
        8000,
      ); // Existing 7000 expense - 1000 refund + 2000.
      final future = await load(LocalDate(2026, 8, 17), 9);
      expect(future.usedMinor, 0);
      expect(future.projectedMinor, 0);
      expect(future.effectiveLimitMinor, 20000);
      final past = await load(LocalDate(2026, 9, 15), 8);
      expect(past.usedMinor, 15000);
      expect(past.projectedMinor, 15000);
      await database.customStatement(
        'UPDATE transaction_splits SET amount_minor = amount_minor + 1000 '
        "WHERE category_id = ? AND transaction_id IN (SELECT id FROM transactions WHERE financial_date = '2026-08-31')",
        [fixture.parentCategory.value],
      );
      final corrected = await load(LocalDate(2026, 9, 15), 8);
      expect(corrected.usedMinor, 16000);
      expect(corrected.effectiveLimitMinor, 20000);
      await service.delete(
        budget,
        now: UtcInstant.fromDateTime(DateTime.utc(2026, 9, 15)),
      );
      expect(
        await service.loadProgress(
          vaultId: fixture.vault,
          asOf: LocalDate(2026, 9, 15),
          month: BudgetMonth(2026, 8),
        ),
        isEmpty,
      );
      expect(
        (await load(LocalDate(2026, 9, 15), 8, deleted: true)).usedMinor,
        16000,
      );
    },
  );

  test(
    'controller creates daily base atomically in vault month and home stays current',
    () async {
      await database.customStatement(
        "INSERT INTO vault_cloud_bindings "
        "(vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, 'fixture', 1, 1)",
        [fixture.vault.value],
      );
      final controller = BudgetController(
        service: service,
        vaultId: fixture.vault,
        timezone: 'America/Sao_Paulo',
        clock: () => DateTime.utc(2024, 3, 1, 1),
      );
      addTearDown(controller.dispose);
      expect(controller.today, LocalDate(2024, 2, 29));
      expect(
        await controller.create(
          name: 'Daily',
          currency: CurrencyCode.brl,
          limitText: '10,00',
          periodType: BudgetPeriodType.monthly,
          warningThresholdBps: 7550,
          scope: BudgetScope(),
          limitMethod: BudgetLimitMethod.weekday,
        ),
        isTrue,
      );
      final budget = controller.state.items.single;
      expect(budget.effectiveLimitMinor, 21000);
      expect(budget.effectiveConfiguration!.amountMinor, 1000);
      expect(budget.budget.revision, 1);
      expect(budget.budget.monthlyHistoryEdited, isTrue);
      final pending = (await DriftSyncMetadataStore(database).pendingFor(
        vaultId: fixture.vault.value,
        entityType: SyncEntityType.budget,
        recordId: budget.budget.id.value,
      ))!;
      expect(pending.baseRevision, isNull);
      expect(pending.newRevision, 1);
      final aggregate =
          (await DriftSyncAggregateStore(
            database: database,
            metadata: DriftSyncMetadataStore(database),
          ).loadPayload(
            vaultId: fixture.vault.value,
            entityType: SyncEntityType.budget,
            recordId: budget.budget.id.value,
          ))!;
      expect(aggregate['format_version'], 2);
      expect(
        (await repository.loadMonthlyHistory(
          budget.budget.id,
        )).entries.single.month,
        BudgetMonth(2024, 2),
      );
      await controller.selectMonth(BudgetMonth(2024, 1));
      expect(controller.state.items, isEmpty);
      expect(controller.state.currentItems.single.effectiveLimitMinor, 21000);
      await controller.selectMonth(BudgetMonth(2024, 3));
      expect(
        controller.state.items.single.effectiveLimitMinor,
        21000,
      ); // March also 21 weekdays.
      expect(controller.state.items.single.usedMinor, 0);
      expect(
        controller.state.currentItems.single.period.start,
        LocalDate(2024, 2, 1),
      );
    },
  );

  test('failed daily creation rolls back root, base, filters and outbox', () async {
    await database.customStatement(
      "INSERT INTO vault_cloud_bindings "
      "(vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, 'fixture', 1, 1)",
      [fixture.vault.value],
    );
    await database.customStatement(
      "CREATE TRIGGER reject_daily BEFORE INSERT ON budget_monthly_configurations "
      "WHEN NEW.limit_method = 'calendar_day' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    final controller = BudgetController(
      service: service,
      vaultId: fixture.vault,
      timezone: 'America/Sao_Paulo',
      clock: () => DateTime.utc(2026, 8, 17, 12),
    );
    addTearDown(controller.dispose);
    expect(
      await controller.create(
        name: 'Daily',
        currency: CurrencyCode.brl,
        limitText: '10',
        periodType: BudgetPeriodType.monthly,
        warningThresholdBps: 8000,
        scope: BudgetScope(),
        limitMethod: BudgetLimitMethod.calendarDay,
      ),
      isFalse,
    );
    for (final table in [
      'budgets',
      'budget_monthly_configurations',
      'sync_outbox',
    ]) {
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM $table')
                .getSingle())
            .read<int>('n'),
        0,
      );
    }
  });

  test(
    'hierarchy, overlap, refunds, card neutrality, and FX reconcile exactly',
    () async {
      final categoryBudget = await _create(
        service,
        fixture,
        name: 'Food',
        limit: 13000,
        threshold: 8000,
        scope: BudgetScope(
          categories: [BudgetCategoryScope(categoryId: fixture.parentCategory)],
        ),
      );
      final overallBudget = await _create(
        service,
        fixture,
        name: 'Overall',
        limit: 20000,
        scope: BudgetScope(),
      );
      final exactParent = await _create(
        service,
        fixture,
        name: 'Parent only',
        limit: 1000,
        scope: BudgetScope(
          categories: [
            BudgetCategoryScope(
              categoryId: fixture.parentCategory,
              includeDescendants: false,
            ),
          ],
        ),
      );
      final bankAndTag = await _create(
        service,
        fixture,
        name: 'Planned bank',
        limit: 10000,
        threshold: 7000,
        scope: BudgetScope(
          accountIds: {fixture.bankAccount},
          tagIds: {fixture.plannedTag},
        ),
      );
      final before = await _fingerprint(database);

      final progress = await service.loadProgress(
        vaultId: fixture.vault,
        asOf: LocalDate(2026, 8, 17),
      );
      final after = await _fingerprint(database);
      BudgetProgress value(EntityId id) =>
          progress.singleWhere((item) => item.budget.id == id);

      expect(value(categoryBudget.id).usedMinor, 13000);
      expect(
        value(categoryBudget.id).warningState,
        BudgetWarningState.limitReached,
      );
      expect(value(categoryBudget.id).usageBps, 10000);
      expect(value(categoryBudget.id).projectedMinor, 23706);
      expect(value(categoryBudget.id).likelyToExceed, isTrue);
      expect(value(overallBudget.id).usedMinor, 13000);
      expect(value(exactParent.id).usedMinor, 0);
      expect(value(bankAndTag.id).usedMinor, 7000);
      expect(
        value(bankAndTag.id).warningState,
        BudgetWarningState.approachingLimit,
      );
      expect(value(categoryBudget.id).isComplete, isTrue);
      expect(value(categoryBudget.id).usesEstimatedRates, isFalse);
      expect(
        after,
        before,
        reason: 'Budget reads must never mutate the ledger.',
      );
    },
  );

  test(
    'missing FX is explicit and never assumes currency equivalence',
    () async {
      final budget = await _create(
        service,
        fixture,
        name: 'Food',
        limit: 20000,
        scope: BudgetScope(
          categories: [BudgetCategoryScope(categoryId: fixture.parentCategory)],
        ),
      );
      await database.customStatement('DELETE FROM fx_rate_cache');

      final value = (await service.loadProgress(
        vaultId: fixture.vault,
        asOf: LocalDate(2026, 8, 17),
      )).singleWhere((item) => item.budget.id == budget.id);

      expect(value.usedMinor, 8000);
      expect(value.isComplete, isFalse);
      expect(value.missingRates, contains(CurrencyCode.usd));
    },
  );

  test('scope updates are atomic and stale revisions are rejected', () async {
    final original = await _create(
      service,
      fixture,
      name: 'Food',
      limit: 10000,
      scope: BudgetScope(
        categories: [BudgetCategoryScope(categoryId: fixture.parentCategory)],
      ),
    );
    final updated = await service.editMonthly(
      existing: original,
      month: BudgetMonth(2026, 8),
      scope: BudgetMonthlyEditScope.onlyMonth,
      configuration: BudgetMonthlyConfiguration(
        amountMinor: 12000,
        warningThresholdBps: 7500,
        scope: BudgetScope(
          accountIds: {fixture.bankAccount},
          tagIds: {fixture.plannedTag},
        ),
      ),
      now: const UtcInstant.fromEpochMicroseconds(9000),
    );
    final loaded = await repository.find(original.id);
    expect(loaded!.name, 'Food');
    expect(loaded.limitMinor, 10000); // Legacy projection is not the timeline.
    final configuration = (await repository.loadMonthlyHistory(
      original.id,
    )).resolve(BudgetMonth(2026, 8))!;
    expect(configuration.amountMinor, 12000);
    expect(configuration.scope.categories, isEmpty);
    expect(configuration.scope.accountIds, {fixture.bankAccount});
    expect(configuration.scope.tagIds, {fixture.plannedTag});

    await expectLater(
      service.update(
        existing: original,
        name: 'Stale',
        limitMinor: 9999,
        periodType: BudgetPeriodType.monthly,
        warningThresholdBps: 8000,
        scope: BudgetScope(),
        enabled: true,
        now: const UtcInstant.fromEpochMicroseconds(10000),
      ),
      throwsA(isA<BudgetRevisionConflict>()),
    );

    await service.delete(
      updated,
      now: const UtcInstant.fromEpochMicroseconds(11000),
    );
    expect((await repository.find(updated.id))!.deletedAt, isNotNull);
    expect(await repository.listForVault(updated.vaultId), isEmpty);
  });

  test('weekly, monthly, yearly, and custom boundaries are inclusive', () {
    BudgetDefinition budget(
      BudgetPeriodType type, {
      LocalDate? from,
      LocalDate? to,
    }) => BudgetDefinition(
      id: EntityId.generate(),
      vaultId: fixture.vault,
      name: 'Period',
      currency: CurrencyCode.brl,
      limitMinor: 1,
      periodType: type,
      startsOn: from,
      endsOn: to,
      warningThresholdBps: 8000,
      scope: BudgetScope(),
      createdAt: const UtcInstant.fromEpochMicroseconds(1),
      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
    );

    final weekly = BudgetPeriod.forDate(
      budget(BudgetPeriodType.weekly),
      LocalDate(2026, 8, 18),
    );
    expect(weekly.start, LocalDate(2026, 8, 17));
    expect(weekly.end, LocalDate(2026, 8, 23));
    final monthly = BudgetPeriod.forDate(
      budget(BudgetPeriodType.monthly),
      LocalDate(2026, 2, 10),
    );
    expect(monthly.end, LocalDate(2026, 2, 28));
    final yearly = BudgetPeriod.forDate(
      budget(BudgetPeriodType.yearly),
      LocalDate(2028, 2, 29),
    );
    expect(yearly.start, LocalDate(2028, 1, 1));
    expect(yearly.end, LocalDate(2028, 12, 31));
    final custom = BudgetPeriod.forDate(
      budget(
        BudgetPeriodType.custom,
        from: LocalDate(2026, 8, 3),
        to: LocalDate(2026, 8, 9),
      ),
      LocalDate(2026, 8, 5),
    );
    expect(custom.totalDays, 7);
    expect(custom.contains(LocalDate(2026, 8, 3)), isTrue);
    expect(custom.contains(LocalDate(2026, 8, 9)), isTrue);
  });
}

Future<BudgetDefinition> _create(
  BudgetService service,
  _Fixture fixture, {
  required String name,
  required int limit,
  required BudgetScope scope,
  int threshold = 8000,
}) => service.create(
  vaultId: fixture.vault,
  name: name,
  currency: CurrencyCode.brl,
  limitMinor: limit,
  periodType: BudgetPeriodType.monthly,
  warningThresholdBps: threshold,
  scope: scope,
  now: const UtcInstant.fromEpochMicroseconds(5000),
);

Future<_Fixture> _seed(
  EquisDatabase database,
  DriftLedgerRepository ledger,
) async {
  final vault = EntityId.generate();
  final bankAccount = EntityId.generate();
  final cashAccount = EntityId.generate();
  final usdAccount = EntityId.generate();
  final cardAccount = EntityId.generate();
  final bankId = EntityId.generate();
  final cashId = EntityId.generate();
  final usdId = EntityId.generate();
  final cardId = EntityId.generate();
  final parent = EntityId.generate();
  final child = EntityId.generate();
  final tag = EntityId.generate();
  await database.customStatement(
    'INSERT INTO vaults '
    '(id, name, base_currency_code, timezone, created_at, updated_at) '
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
    (usdAccount, 'USD', 'checking', 'asset'),
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
    (usdId, usdAccount, 'USD'),
    (cardId, cardAccount, 'BRL'),
  ]) {
    await database.customStatement(
      'INSERT INTO account_pockets '
      '(id, account_id, currency_code, is_default) VALUES (?, ?, ?, 1)',
      [pocket.$1.value, pocket.$2.value, pocket.$3],
    );
  }
  await database.customStatement(
    'INSERT INTO categories '
    '(id, vault_id, parent_id, category_type, custom_name, created_at, updated_at) '
    'VALUES (?, ?, NULL, ?, ?, 1, 1), (?, ?, ?, ?, ?, 1, 1)',
    [
      parent.value,
      vault.value,
      'expense',
      'Food',
      child.value,
      vault.value,
      parent.value,
      'expense',
      'Groceries',
    ],
  );
  await database.customStatement(
    'INSERT INTO tags (id, vault_id, name, created_at, updated_at) '
    'VALUES (?, ?, ?, 1, 1)',
    [tag.value, vault.value, 'Planned'],
  );
  await database.customStatement(
    'INSERT INTO fx_rate_cache '
    '(base_currency, quote_currency, rate_date, rate, provider, fetched_at) '
    'VALUES (?, ?, ?, ?, ?, 1)',
    ['USD', 'BRL', '2026-08-08', '5', 'fixture'],
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
  final usd = LedgerPocket(
    id: usdId,
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
  Money brl(int value) => Money(currency: CurrencyCode.brl, minorUnits: value);
  await ledger.save(
    engine
        .expense(
          vaultId: vault,
          pocket: bank,
          amount: brl(7000),
          categoryId: child,
          date: LocalDate(2026, 8, 5),
          now: now,
        )
        .tagged([tag]),
  );
  await ledger.save(
    engine
        .expense(
          vaultId: vault,
          pocket: cash,
          amount: brl(2000),
          categoryId: child,
          date: LocalDate(2026, 8, 6),
          now: now,
        )
        .tagged([tag]),
  );
  await ledger.save(
    engine.refund(
      vaultId: vault,
      pocket: bank,
      amount: brl(1000),
      originalCategoryId: child,
      date: LocalDate(2026, 8, 7),
      now: now,
    ),
  );
  await ledger.save(
    engine.expense(
      vaultId: vault,
      pocket: usd,
      amount: Money(currency: CurrencyCode.usd, minorUnits: 1000),
      categoryId: child,
      date: LocalDate(2026, 8, 8),
      now: now,
    ),
  );
  await ledger.save(
    engine.transfer(
      vaultId: vault,
      source: bank,
      destination: cash,
      amount: brl(500),
      date: LocalDate(2026, 8, 9),
      now: now,
    ),
  );
  await ledger.save(
    engine.creditCardPayment(
      vaultId: vault,
      bankPocket: bank,
      cardPocket: card,
      amount: brl(500),
      date: LocalDate(2026, 8, 10),
      now: now,
    ),
  );
  return _Fixture(
    vault: vault,
    bankAccount: bankAccount,
    parentCategory: parent,
    plannedTag: tag,
  );
}

Future<String> _fingerprint(EquisDatabase database) async {
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
    required this.bankAccount,
    required this.parentCategory,
    required this.plannedTag,
  });

  final EntityId vault;
  final EntityId bankAccount;
  final EntityId parentCategory;
  final EntityId plannedTag;
}
