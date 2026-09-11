import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final engine = LedgerEngine();
  final vault = EntityId.generate();
  final expenseCategory = EntityId.generate();
  final incomeCategory = EntityId.generate();
  final instrument = EntityId.generate();
  final bank = _pocket(CurrencyCode.brl, AccountNature.asset);
  final savings = _pocket(CurrencyCode.brl, AccountNature.asset);
  final investmentCash = _pocket(CurrencyCode.brl, AccountNature.asset);
  final physicalAsset = _pocket(CurrencyCode.brl, AccountNature.asset);
  final card = _pocket(CurrencyCode.brl, AccountNature.liability);
  final loan = _pocket(CurrencyCode.brl, AccountNature.liability);
  final usd = _pocket(CurrencyCode.usd, AccountNature.asset);
  final date = LocalDate.parse('2026-08-13');
  const now = UtcInstant.fromEpochMicroseconds(1786636800123456);

  Money brl(int minor) => Money(currency: CurrencyCode.brl, minorUnits: minor);

  test(
    'income and expense use nature-aware signs and exact classification',
    () {
      final income = engine.income(
        vaultId: vault,
        pocket: bank,
        amount: brl(500000),
        categoryId: incomeCategory,
        date: date,
        now: now,
      );
      final expense = engine.expense(
        vaultId: vault,
        pocket: bank,
        amount: brl(7250),
        categoryId: expenseCategory,
        date: date,
        now: now,
      );
      expect(income.movements.single.amountMinor, 500000);
      expect(income.splits.single.money.minorUnits, 500000);
      expect(expense.movements.single.amountMinor, -7250);
      expect(expense.splits.single.money.minorUnits, 7250);
    },
  );

  test(
    'transfer and asset/investment cash transfers never create spending',
    () {
      final cases = [
        engine.transfer(
          vaultId: vault,
          source: bank,
          destination: savings,
          amount: brl(50000),
          date: date,
          now: now,
        ),
        engine.assetPurchase(
          vaultId: vault,
          cashPocket: bank,
          assetPocket: physicalAsset,
          amount: brl(100000),
          date: date,
          now: now,
        ),
        engine.assetSale(
          vaultId: vault,
          assetPocket: physicalAsset,
          cashPocket: bank,
          amount: brl(90000),
          date: date,
          now: now,
        ),
        engine.investmentContribution(
          vaultId: vault,
          cashPocket: bank,
          investmentCashPocket: investmentCash,
          amount: brl(25000),
          date: date,
          now: now,
        ),
        engine.investmentWithdrawal(
          vaultId: vault,
          investmentCashPocket: investmentCash,
          cashPocket: bank,
          amount: brl(12000),
          date: date,
          now: now,
        ),
      ];
      for (final transaction in cases) {
        expect(transaction.type, LedgerTransactionType.transfer);
        expect(
          transaction.movements
              .map((movement) => movement.amountMinor)
              .reduce((a, b) => a + b),
          0,
        );
        expect(transaction.splits, isEmpty);
      }
    },
  );

  test(
    'currency exchange preserves both original currencies and explicit rate',
    () {
      final transaction = engine.currencyExchange(
        vaultId: vault,
        source: bank,
        sourceAmount: brl(500000),
        destination: usd,
        destinationAmount: Money(currency: CurrencyCode.usd, minorUnits: 91000),
        exchangeRate: '5.4945054900',
        rateSource: 'manual',
        date: date,
        now: now,
      );
      expect(transaction.movements[0].amountMinor, -500000);
      expect(transaction.movements[0].pocket.currency, CurrencyCode.brl);
      expect(transaction.movements[1].amountMinor, 91000);
      expect(transaction.movements[1].pocket.currency, CurrencyCode.usd);
      expect(transaction.fxConversion?.exchangeRate, '5.49450549');
      expect(transaction.splits, isEmpty);
    },
  );

  test(
    'credit-card purchase records expense once and payment records none',
    () {
      final purchase = engine.creditCardPurchase(
        vaultId: vault,
        cardPocket: card,
        amount: brl(12000),
        categoryId: expenseCategory,
        date: date,
        now: now,
      );
      final payment = engine.creditCardPayment(
        vaultId: vault,
        bankPocket: bank,
        cardPocket: card,
        amount: brl(12000),
        date: date,
        now: now,
      );
      expect(purchase.movements.single.amountMinor, 12000);
      expect(purchase.splits.single.money.minorUnits, 12000);
      expect(payment.movements.map((movement) => movement.amountMinor), [
        -12000,
        -12000,
      ]);
      expect(payment.netWorthEffectMinor, 0);
      expect(payment.splits, isEmpty);
    },
  );

  test('refund offsets the original expense classification', () {
    final refund = engine.refund(
      vaultId: vault,
      pocket: bank,
      amount: brl(3000),
      originalCategoryId: expenseCategory,
      date: date,
      now: now,
    );
    expect(refund.movements.single.amountMinor, 3000);
    expect(refund.splits.single.money.minorUnits, -3000);
  });

  test(
    'loan payment reduces both the bank asset and debt without expense split',
    () {
      final payment = engine.loanPayment(
        vaultId: vault,
        bankPocket: bank,
        loanPocket: loan,
        principal: brl(20000),
        date: date,
        now: now,
      );
      expect(payment.movements.map((movement) => movement.amountMinor), [
        -20000,
        -20000,
      ]);
      expect(payment.netWorthEffectMinor, 0);
      expect(payment.splits, isEmpty);
    },
  );

  test(
    'investment buy and sell preserve event precision without consumption splits',
    () {
      final buyEvent = _event(
        instrument,
        'buy',
        quantity: '10.000',
        unitPrice: '32.00',
      );
      final sellEvent = _event(
        instrument,
        'sell',
        quantity: '1.5',
        unitPrice: '35.25',
      );
      final buy = engine.investmentBuy(
        vaultId: vault,
        cashPocket: investmentCash,
        totalCash: brl(32100),
        event: buyEvent,
        date: date,
        now: now,
      );
      final sell = engine.investmentSell(
        vaultId: vault,
        cashPocket: investmentCash,
        netCash: brl(5275),
        event: sellEvent,
        date: date,
        now: now,
      );
      expect(buy.movements.single.amountMinor, -32100);
      expect(buy.investmentEvents.single.quantity, '10');
      expect(buy.investmentEvents.single.unitPrice, '32');
      expect(sell.movements.single.amountMinor, 5275);
      expect(buy.splits, isEmpty);
      expect(sell.splits, isEmpty);
    },
  );

  test('dividend, interest, and fee have correct economic direction', () {
    final dividend = engine.dividend(
      vaultId: vault,
      cashPocket: investmentCash,
      amount: brl(800),
      categoryId: incomeCategory,
      event: _event(instrument, 'dividend'),
      date: date,
      now: now,
    );
    final interest = engine.interest(
      vaultId: vault,
      cashPocket: investmentCash,
      amount: brl(250),
      categoryId: incomeCategory,
      event: _event(instrument, 'interest'),
      date: date,
      now: now,
    );
    final fee = engine.fee(
      vaultId: vault,
      pocket: bank,
      amount: brl(100),
      categoryId: expenseCategory,
      date: date,
      now: now,
    );
    expect(dividend.netWorthEffectMinor, 800);
    expect(interest.netWorthEffectMinor, 250);
    expect(fee.netWorthEffectMinor, -100);
  });

  test('opening balance and adjustment remain explicit ledger movements', () {
    final opening = engine.openingBalance(
      vaultId: vault,
      pocket: bank,
      signedAmount: brl(10000),
      date: date,
      now: now,
    );
    final adjustment = engine.adjustment(
      vaultId: vault,
      pocket: bank,
      signedAmount: brl(-50),
      date: date,
      now: now,
    );
    expect(opening.type, LedgerTransactionType.openingBalance);
    expect(opening.movements.single.amountMinor, 10000);
    expect(adjustment.type, LedgerTransactionType.adjustment);
    expect(adjustment.movements.single.amountMinor, -50);
  });

  test(
    'status transitions, edits, cancellation, and reversal preserve revision rules',
    () {
      final pending = engine.expense(
        vaultId: vault,
        pocket: bank,
        amount: brl(100),
        categoryId: expenseCategory,
        date: date,
        now: now,
        status: LedgerTransactionStatus.pending,
      );
      final cleared = pending.transitionTo(
        LedgerTransactionStatus.cleared,
        at: now,
      );
      final reconciled = cleared.transitionTo(
        LedgerTransactionStatus.reconciled,
        at: now,
      );
      expect(cleared.revision, 2);
      expect(reconciled.revision, 3);
      expect(
        () =>
            reconciled.transitionTo(LedgerTransactionStatus.cancelled, at: now),
        throwsStateError,
      );

      final edited = pending.revise(
        movements: pending.movements,
        splits: pending.splits,
        at: now,
        title: 'Edited',
      );
      expect(edited.revision, 2);
      expect(edited.title, 'Edited');

      final cancelled = pending.transitionTo(
        LedgerTransactionStatus.cancelled,
        at: now,
      );
      expect(cancelled.affectsBalances, isFalse);
      expect(
        () => cancelled.revise(
          movements: cancelled.movements,
          splits: cancelled.splits,
          at: now,
        ),
        throwsStateError,
      );

      final reversal = cleared.reversed(
        id: EntityId.generate(),
        nextId: EntityId.generate,
        at: now,
      );
      expect(reversal.reversalOfId, cleared.id);
      expect(
        reversal.movements.single.amountMinor,
        -cleared.movements.single.amountMinor,
      );
      expect(
        reversal.splits.single.money.minorUnits,
        -cleared.splits.single.money.minorUnits,
      );
    },
  );

  test('invalid currencies, signs, and posting shapes are rejected', () {
    expect(
      () => engine.expense(
        vaultId: vault,
        pocket: bank,
        amount: Money(currency: CurrencyCode.usd, minorUnits: 100),
        categoryId: expenseCategory,
        date: date,
        now: now,
      ),
      throwsArgumentError,
    );
    expect(
      () => LedgerTransaction(
        id: EntityId.generate(),
        vaultId: vault,
        type: LedgerTransactionType.transfer,
        status: LedgerTransactionStatus.cleared,
        financialDate: date,
        movements: [
          LedgerMovement(
            id: EntityId.generate(),
            pocket: bank,
            amountMinor: -100,
            sortOrder: 0,
          ),
          LedgerMovement(
            id: EntityId.generate(),
            pocket: savings,
            amountMinor: 99,
            sortOrder: 1,
          ),
        ],
        splits: const [],
        createdAt: now,
        updatedAt: now,
      ),
      throwsStateError,
    );
  });
}

LedgerPocket _pocket(CurrencyCode currency, AccountNature nature) =>
    LedgerPocket(id: EntityId.generate(), currency: currency, nature: nature);

LedgerInvestmentEvent _event(
  EntityId instrument,
  String type, {
  String? quantity,
  String? unitPrice,
}) => LedgerInvestmentEvent(
  id: EntityId.generate(),
  instrumentId: instrument,
  eventType: type,
  quantity: quantity,
  unitPrice: unitPrice,
  priceCurrency: CurrencyCode.brl,
);
