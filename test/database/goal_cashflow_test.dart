import 'package:drift/native.dart';
import 'package:equis/application/ports/goal_repository.dart';
import 'package:equis/application/services/cash_flow_projection_service.dart';
import 'package:equis/application/services/dashboard_service.dart';
import 'package:equis/application/services/goal_service.dart';
import 'package:equis/application/services/recurring_transaction_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/goals/cash_flow_projection.dart';
import 'package:equis/domain/goals/goal_models.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/recurring/recurrence_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_goal_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_recurring_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftGoalRepository repository;
  late GoalService goals;
  late CashFlowProjectionService cashFlow;
  late _Fixture fixture;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    final ledger = DriftLedgerRepository(database);
    final reporting = DriftDashboardRepository(database);
    repository = DriftGoalRepository(database);
    final recurringRepository = DriftRecurringRepository(
      database: database,
      ledger: ledger,
    );
    final recurring = RecurringTransactionService(
      repository: recurringRepository,
      ledger: ledger,
      unitOfWork: DriftLocalUnitOfWork(database),
    );
    final dashboard = DashboardService(
      repository: reporting,
      recurring: recurring,
    );
    goals = GoalService(repository: repository, reporting: reporting);
    cashFlow = CashFlowProjectionService(
      repository: repository,
      reporting: reporting,
      dashboard: dashboard,
      recurring: recurring,
    );
    fixture = await _seed(database, ledger, recurring, goals);
  });

  tearDown(() => database.close());

  test('manual and linked goals derive exact progress and dates', () async {
    final progress = await goals.loadProgress(
      vaultId: fixture.vault,
      asOf: LocalDate(2026, 8, 18),
    );
    final manual = progress.singleWhere(
      (item) => item.goal.id == fixture.manualGoal.id,
    );
    final linked = progress.singleWhere(
      (item) => item.goal.id == fixture.linkedGoal.id,
    );

    expect(manual.currentMinor, 3000);
    expect(manual.remainingMinor, 9000);
    expect(manual.progressBps, 2500);
    expect(manual.requiredMonthlyMinor, 3000);
    expect(manual.expectedCompletionDate, LocalDate(2026, 12, 31));
    expect(
      goals.expectedCompletionFor(
        progress: manual,
        asOf: LocalDate(2026, 8, 18),
        monthlyMinor: 3000,
      ),
      LocalDate(2026, 10, 31),
    );
    expect(linked.currentMinor, 10000);
    expect(linked.progressBps, 5000);
    expect(linked.isComplete, isTrue);
    expect(linked.usesEstimatedRates, isFalse);
  });

  test(
    'cash-flow estimate includes every bounded future source once',
    () async {
      final projection = await cashFlow.load(
        vaultId: fixture.vault,
        reportingCurrency: CurrencyCode.brl,
        asOf: LocalDate(2026, 8, 18),
        through: LocalDate(2026, 9, 30),
      );

      expect(projection.isEstimate, isTrue);
      expect(projection.isComplete, isTrue);
      expect(projection.openingAvailableMinor, 110000);
      expect(projection.closingProjectedMinor, 107000);
      expect(
        projection.events.map((event) => event.type),
        containsAll(<CashFlowEventType>[
          CashFlowEventType.recurringIncome,
          CashFlowEventType.recurringExpense,
          CashFlowEventType.installment,
          CashFlowEventType.cardStatement,
          CashFlowEventType.goalContribution,
        ]),
      );
      expect(
        projection.events.where(
          (event) => event.type == CashFlowEventType.goalContribution,
        ),
        hasLength(2),
      );
      expect(
        projection.events
            .where((event) => event.type == CashFlowEventType.installment)
            .single
            .amountMinor,
        -3000,
      );
      expect(
        projection.events
            .where((event) => event.type == CashFlowEventType.cardStatement)
            .single
            .amountMinor,
        -4000,
      );
    },
  );

  test('linked goal reports missing FX instead of assuming parity', () async {
    await database.customStatement('DELETE FROM fx_rate_cache');
    final progress = await goals.loadProgress(
      vaultId: fixture.vault,
      asOf: LocalDate(2026, 8, 18),
    );
    final linked = progress.singleWhere(
      (item) => item.goal.id == fixture.linkedGoal.id,
    );
    expect(linked.currentMinor, 5000);
    expect(linked.isComplete, isFalse);
    expect(linked.missingRates, contains(CurrencyCode.usd));
  });

  test(
    'goal revisions, account scopes, and transaction links persist',
    () async {
      final loaded = await repository.find(fixture.linkedGoal.id);
      expect(loaded!.accountPocketIds, {
        fixture.brlSavings.id,
        fixture.usdSavings.id,
      });
      final updated = await goals.update(
        existing: loaded,
        name: 'Reserve',
        type: loaded.type,
        targetMinor: 25000,
        targetDate: LocalDate(2027, 1, 31),
        plannedMonthlyMinor: 3000,
        trackingMode: loaded.trackingMode,
        priority: 9,
        accountPocketIds: {fixture.brlSavings.id},
        status: GoalStatus.active,
        now: const UtcInstant.fromEpochMicroseconds(9000),
      );
      expect((await repository.find(updated.id))!.accountPocketIds, {
        fixture.brlSavings.id,
      });
      await expectLater(
        goals.update(
          existing: loaded,
          name: 'Stale',
          type: loaded.type,
          targetMinor: 1,
          trackingMode: loaded.trackingMode,
          priority: 0,
          accountPocketIds: loaded.accountPocketIds,
          status: GoalStatus.active,
          now: const UtcInstant.fromEpochMicroseconds(10000),
        ),
        throwsA(isA<GoalRevisionConflict>()),
      );
      final contributions = await repository.contributions(
        fixture.manualGoal.id,
        through: LocalDate(2026, 8, 18),
      );
      expect(contributions, hasLength(2));
      expect(
        contributions.where((item) => item.transactionId != null),
        hasLength(1),
      );
    },
  );
}

Future<_Fixture> _seed(
  EquisDatabase database,
  DriftLedgerRepository ledger,
  RecurringTransactionService recurring,
  GoalService goals,
) async {
  final vault = EntityId.generate();
  final bankAccount = EntityId.generate();
  final savingsAccount = EntityId.generate();
  final usdAccount = EntityId.generate();
  final cardAccount = EntityId.generate();
  final bankId = EntityId.generate();
  final savingsId = EntityId.generate();
  final usdId = EntityId.generate();
  final cardId = EntityId.generate();
  final category = EntityId.generate();
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
    (savingsAccount, 'Savings', 'savings', 'asset'),
    (usdAccount, 'USD Savings', 'savings', 'asset'),
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
    (savingsId, savingsAccount, 'BRL'),
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
    '(id, vault_id, category_type, custom_name, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, 1, 1)',
    [category.value, vault.value, 'expense', 'Planning'],
  );
  await database.customStatement(
    'INSERT INTO fx_rate_cache '
    '(base_currency, quote_currency, rate_date, rate, provider, fetched_at) '
    'VALUES (?, ?, ?, ?, ?, 1)',
    ['USD', 'BRL', '2026-08-18', '5', 'fixture'],
  );
  final bank = LedgerPocket(
    id: bankId,
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  final brlSavings = LedgerPocket(
    id: savingsId,
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  final usdSavings = LedgerPocket(
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
  final openingDate = LocalDate(2026, 8, 1);
  Money brl(int value) => Money(currency: CurrencyCode.brl, minorUnits: value);
  final bankOpening = engine.openingBalance(
    vaultId: vault,
    pocket: bank,
    signedAmount: brl(100000),
    date: openingDate,
    now: now,
  );
  await ledger.save(bankOpening);
  await ledger.save(
    engine.openingBalance(
      vaultId: vault,
      pocket: brlSavings,
      signedAmount: brl(5000),
      date: openingDate,
      now: now,
    ),
  );
  await ledger.save(
    engine.openingBalance(
      vaultId: vault,
      pocket: usdSavings,
      signedAmount: Money(currency: CurrencyCode.usd, minorUnits: 1000),
      date: openingDate,
      now: now,
    ),
  );
  final statementId = EntityId.generate();
  await database.customStatement(
    'INSERT INTO credit_card_statements '
    '(id, vault_id, account_pocket_id, period_start, period_end, closing_date, '
    'due_date, status, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    [
      statementId.value,
      vault.value,
      cardId.value,
      '2026-07-21',
      '2026-08-20',
      '2026-08-20',
      '2026-09-05',
      'open',
    ],
  );
  await ledger.save(
    engine.creditCardPurchase(
      vaultId: vault,
      cardPocket: card,
      amount: brl(4000),
      categoryId: category,
      date: LocalDate(2026, 8, 10),
      now: now,
      statementId: statementId,
    ),
  );
  final planId = EntityId.generate();
  await database.customStatement(
    'INSERT INTO installment_plans '
    '(id, vault_id, account_pocket_id, category_id, description, currency_code, '
    'total_minor, installment_count, first_installment_date, status, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    [
      planId.value,
      vault.value,
      cardId.value,
      category.value,
      'Course',
      'BRL',
      3000,
      1,
      '2026-09-03',
      'active',
    ],
  );
  await database.customStatement(
    'INSERT INTO installments '
    '(id, installment_plan_id, installment_number, amount_minor, expected_date, status) '
    'VALUES (?, ?, 1, 3000, ?, ?)',
    [EntityId.generate().value, planId.value, '2026-09-03', 'scheduled'],
  );
  await recurring.createEverydaySchedule(
    vaultId: vault,
    name: 'Salary',
    type: LedgerTransactionType.income,
    source: bank,
    amount: brl(10000),
    categoryId: category,
    startsOn: LocalDate(2026, 9, 1),
    endsOn: LocalDate(2026, 9, 1),
    pattern: const RecurrencePattern(frequency: RecurrenceFrequency.monthly),
    timezone: 'America/Sao_Paulo',
    now: now,
  );
  await recurring.createEverydaySchedule(
    vaultId: vault,
    name: 'Rent',
    type: LedgerTransactionType.expense,
    source: bank,
    amount: brl(2000),
    categoryId: category,
    startsOn: LocalDate(2026, 9, 2),
    endsOn: LocalDate(2026, 9, 2),
    pattern: const RecurrencePattern(frequency: RecurrenceFrequency.monthly),
    timezone: 'America/Sao_Paulo',
    now: now,
  );
  final manualGoal = await goals.create(
    vaultId: vault,
    name: 'Vacation',
    type: GoalType.vacation,
    currency: CurrencyCode.brl,
    targetMinor: 12000,
    targetDate: LocalDate(2026, 10, 31),
    plannedMonthlyMinor: 2000,
    trackingMode: GoalTrackingMode.manual,
    priority: 5,
    accountPocketIds: const {},
    now: now,
  );
  await goals.contribute(
    goal: manualGoal,
    amountMinor: 2000,
    date: LocalDate(2026, 8, 5),
  );
  await goals.contribute(
    goal: manualGoal,
    amountMinor: 1000,
    date: LocalDate(2026, 8, 6),
    transactionId: bankOpening.id,
  );
  final linkedGoal = await goals.create(
    vaultId: vault,
    name: 'Emergency fund',
    type: GoalType.emergencyFund,
    currency: CurrencyCode.brl,
    targetMinor: 20000,
    targetDate: LocalDate(2027, 1, 31),
    plannedMonthlyMinor: 1000,
    trackingMode: GoalTrackingMode.linkedAccounts,
    priority: 10,
    accountPocketIds: {brlSavings.id, usdSavings.id},
    now: now,
  );
  return _Fixture(
    vault: vault,
    brlSavings: brlSavings,
    usdSavings: usdSavings,
    manualGoal: manualGoal,
    linkedGoal: linkedGoal,
  );
}

final class _Fixture {
  const _Fixture({
    required this.vault,
    required this.brlSavings,
    required this.usdSavings,
    required this.manualGoal,
    required this.linkedGoal,
  });

  final EntityId vault;
  final LedgerPocket brlSavings;
  final LedgerPocket usdSavings;
  final GoalDefinition manualGoal;
  final GoalDefinition linkedGoal;
}
