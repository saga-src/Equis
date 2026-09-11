import 'package:drift/native.dart';
import 'package:equis/application/services/credit_card_service.dart';
import 'package:equis/domain/credit_cards/credit_card_models.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide
        CreditCardLimit,
        CreditCardProfile,
        CreditCardStatement,
        InstallmentPlan;
import 'package:equis/infrastructure/repositories/drift_credit_card_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftCreditCardRepository repository;
  late DriftLedgerRepository ledger;
  late CreditCardService service;
  late _Fixture fixture;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    ledger = DriftLedgerRepository(database);
    repository = DriftCreditCardRepository(database);
    service = CreditCardService(
      repository: repository,
      ledger: ledger,
      unitOfWork: DriftLocalUnitOfWork(database),
    );
    fixture = await _seed(database);
    await service.configure(
      card: fixture.brlCard,
      closingDay: 20,
      dueDay: 5,
      limitMinor: 500000,
    );
  });

  tearDown(() => database.close());

  test(
    'purchases cross closing boundary and due boundary is deterministic',
    () async {
      final before = await service.purchase(
        card: fixture.brlCard,
        amount: fixture.brl(10000),
        categoryId: fixture.category,
        date: LocalDate(2026, 8, 20),
        now: fixture.now,
      );
      final after = await service.purchase(
        card: fixture.brlCard,
        amount: fixture.brl(2500),
        categoryId: fixture.category,
        date: LocalDate(2026, 8, 21),
        now: fixture.now,
      );
      expect(before.movements.single.statementId, isNotNull);
      expect(
        before.movements.single.statementId,
        isNot(after.movements.single.statementId),
      );
      var views = await service.statementsAround(
        card: fixture.brlCard,
        around: LocalDate(2026, 9, 5),
        now: fixture.now,
      );
      var august = views.singleWhere(
        (view) => view.statement.closingDate == LocalDate(2026, 8, 20),
      );
      expect(august.statement.status, CreditCardStatementStatus.closed);
      expect(august.amounts.dueMinor, 10000);
      views = await service.statementsAround(
        card: fixture.brlCard,
        around: LocalDate(2026, 9, 6),
        now: fixture.later,
      );
      august = views.singleWhere(
        (view) => view.statement.closingDate == LocalDate(2026, 8, 20),
      );
      expect(august.statement.status, CreditCardStatementStatus.overdue);
    },
  );

  test(
    'partial bank payment reduces statement and is never spending',
    () async {
      final purchase = await service.purchase(
        card: fixture.brlCard,
        amount: fixture.brl(10000),
        categoryId: fixture.category,
        date: LocalDate(2026, 8, 10),
        now: fixture.now,
      );
      final statement = (await repository.listStatements(
        fixture.brlCard.pocketId,
      )).single;
      final payment = await service.payStatement(
        card: fixture.brlCard,
        statement: statement,
        bankPocket: fixture.brlBank,
        amount: fixture.brl(4000),
        date: LocalDate(2026, 9, 1),
        now: fixture.later,
      );
      final amounts = await repository.statementAmounts(statement.id);
      expect(amounts.chargesMinor, 10000);
      expect(amounts.paymentsMinor, 4000);
      expect(amounts.dueMinor, 6000);
      expect(payment.splits, isEmpty);
      expect(payment.netWorthEffectMinor, 0);
      expect(purchase.splits.single.money.minorUnits, 10000);
      expect(await service.availableCredit(fixture.brlCard), 500000 - 6000);
    },
  );

  test(
    'refund before and after close offsets the original expense once',
    () async {
      final purchase = await service.purchase(
        card: fixture.brlCard,
        amount: fixture.brl(10000),
        categoryId: fixture.category,
        date: LocalDate(2026, 8, 10),
        now: fixture.now,
      );
      final beforeClose = await service.refund(
        card: fixture.brlCard,
        original: purchase,
        amount: fixture.brl(3000),
        date: LocalDate(2026, 8, 15),
        now: fixture.later,
      );
      final afterClose = await service.refund(
        card: fixture.brlCard,
        original: purchase,
        amount: fixture.brl(2000),
        date: LocalDate(2026, 8, 21),
        now: fixture.later,
      );
      expect(beforeClose.reversalOfId, purchase.id);
      expect(afterClose.reversalOfId, purchase.id);
      expect(beforeClose.splits.single.money.minorUnits, -3000);
      expect(
        beforeClose.movements.single.statementId,
        isNot(afterClose.movements.single.statementId),
      );
      final first = await repository.statementAmounts(
        beforeClose.movements.single.statementId!,
      );
      expect(first.dueMinor, 7000);
    },
  );

  test(
    '12x interest-bearing purchase projects future statements exactly',
    () async {
      final plan = await service.createInstallmentPlan(
        card: fixture.brlCard,
        originalAmount: fixture.brl(120000),
        financedAmount: fixture.brl(126000),
        installmentCount: 12,
        categoryId: fixture.category,
        firstInstallmentDate: LocalDate(2026, 1, 31),
        asOf: LocalDate(2026, 1, 31),
        now: fixture.now,
        description: 'Notebook',
        interestRate: '5.0',
      );
      expect(plan.items, hasLength(12));
      expect(plan.plan.totalMinor, 120000);
      expect(plan.financedTotalMinor, 126000);
      expect(plan.currentInstallment, 1);
      expect(plan.remainingMinor, 126000);
      expect(plan.items[1].expectedDate, LocalDate(2026, 2, 28));
      expect(plan.items[2].expectedDate, LocalDate(2026, 3, 31));
      expect(plan.items.map((item) => item.statementId).toSet(), hasLength(12));
      expect(await service.availableCredit(fixture.brlCard), 374000);

      await service.cancelInstallmentPlan(
        card: fixture.brlCard,
        value: plan,
        refundDate: LocalDate(2026, 2, 1),
        now: fixture.later,
      );
      final restored = await repository.findInstallmentPlan(plan.plan.id);
      expect(restored!.plan.status, InstallmentPlanStatus.cancelled);
      expect(restored.items.first.status, InstallmentStatus.refunded);
      expect(
        restored.items.skip(1).map((item) => item.status),
        everyElement(InstallmentStatus.cancelled),
      );
      expect(await service.availableCredit(fixture.brlCard), 500000);
    },
  );

  test('multi-currency card pocket preserves original USD amount', () async {
    await service.configure(
      card: fixture.usdCard,
      closingDay: 20,
      dueDay: 5,
      limitMinor: 100000,
    );
    final purchase = await service.purchase(
      card: fixture.usdCard,
      amount: Money(currency: CurrencyCode.usd, minorUnits: 2500),
      categoryId: fixture.category,
      date: LocalDate(2026, 8, 10),
      now: fixture.now,
    );
    expect(purchase.movements.single.pocket.currency, CurrencyCode.usd);
    expect(purchase.splits.single.money.currency, CurrencyCode.usd);
    final statement = (await repository.listStatements(
      fixture.usdCard.pocketId,
    )).single;
    final payment = await service.payStatement(
      card: fixture.usdCard,
      statement: statement,
      bankPocket: fixture.usdBank,
      amount: Money(currency: CurrencyCode.usd, minorUnits: 2500),
      date: LocalDate(2026, 9, 1),
      now: fixture.later,
    );
    expect(
      payment.movements.every(
        (item) => item.pocket.currency == CurrencyCode.usd,
      ),
      isTrue,
    );
  });
}

Future<_Fixture> _seed(EquisDatabase database) async {
  final vault = EntityId.generate();
  final bank = EntityId.generate();
  final card = EntityId.generate();
  final brlBank = EntityId.generate();
  final usdBank = EntityId.generate();
  final brlCard = EntityId.generate();
  final usdCard = EntityId.generate();
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
  await database.customStatement(
    'INSERT INTO accounts '
    '(id, vault_id, name, account_type, nature, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, 1, 1), (?, ?, ?, ?, ?, 1, 1)',
    [
      bank.value,
      vault.value,
      'Bank',
      'checking',
      'asset',
      card.value,
      vault.value,
      'Card',
      'credit_card',
      'liability',
    ],
  );
  await database.customStatement(
    'INSERT INTO account_pockets (id, account_id, currency_code, is_default) '
    'VALUES (?, ?, ?, 1), (?, ?, ?, 0), (?, ?, ?, 1), (?, ?, ?, 0)',
    [
      brlBank.value,
      bank.value,
      'BRL',
      usdBank.value,
      bank.value,
      'USD',
      brlCard.value,
      card.value,
      'BRL',
      usdCard.value,
      card.value,
      'USD',
    ],
  );
  await database.customStatement(
    'INSERT INTO categories '
    '(id, vault_id, category_type, custom_name, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, 1, 1)',
    [category.value, vault.value, 'expense', 'Purchases'],
  );
  return _Fixture(
    brlCard: CreditCardContext(
      vaultId: vault,
      accountId: card,
      pocketId: brlCard,
      currency: CurrencyCode.brl,
    ),
    usdCard: CreditCardContext(
      vaultId: vault,
      accountId: card,
      pocketId: usdCard,
      currency: CurrencyCode.usd,
    ),
    brlBank: LedgerPocket(
      id: brlBank,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    ),
    usdBank: LedgerPocket(
      id: usdBank,
      currency: CurrencyCode.usd,
      nature: AccountNature.asset,
    ),
    category: category,
  );
}

final class _Fixture {
  const _Fixture({
    required this.brlCard,
    required this.usdCard,
    required this.brlBank,
    required this.usdBank,
    required this.category,
  });

  final CreditCardContext brlCard;
  final CreditCardContext usdCard;
  final LedgerPocket brlBank;
  final LedgerPocket usdBank;
  final EntityId category;
  UtcInstant get now => const UtcInstant.fromEpochMicroseconds(1000);
  UtcInstant get later => const UtcInstant.fromEpochMicroseconds(2000);
  Money brl(int minor) => Money(currency: CurrencyCode.brl, minorUnits: minor);
}
