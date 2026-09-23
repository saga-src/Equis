import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/presentation/transactions/transaction_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps only expense, income, and transfer to semantic classes', () {
    expect(
      transactionSemantic(LedgerTransactionType.expense),
      TransactionSemantic.expense,
    );
    expect(
      transactionSemantic(LedgerTransactionType.income),
      TransactionSemantic.income,
    );
    expect(
      transactionSemantic(LedgerTransactionType.transfer),
      TransactionSemantic.transfer,
    );
    expect(
      transactionSemantic(LedgerTransactionType.creditCardPurchase),
      TransactionSemantic.neutral,
    );
  });

  test('shares edit, reconcile, and delete eligibility', () {
    expect(
      transactionActions(
        _transaction(
          type: LedgerTransactionType.expense,
          status: LedgerTransactionStatus.cleared,
        ),
      ),
      const [
        TransactionAction.edit,
        TransactionAction.reconcile,
        TransactionAction.delete,
      ],
    );
    expect(
      transactionActions(
        _transaction(
          type: LedgerTransactionType.expense,
          status: LedgerTransactionStatus.reconciled,
        ),
      ),
      const [TransactionAction.delete],
    );
    expect(
      transactionActions(
        _transaction(
          type: LedgerTransactionType.adjustment,
          status: LedgerTransactionStatus.cleared,
        ),
      ),
      const [TransactionAction.reconcile, TransactionAction.delete],
    );
  });
}

LedgerTransaction _transaction({
  required LedgerTransactionType type,
  required LedgerTransactionStatus status,
}) {
  final amount = type == LedgerTransactionType.income ? 1000 : -1000;
  final pocket = LedgerPocket(
    id: EntityId.generate(),
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  final movements = [
    LedgerMovement(
      id: EntityId.generate(),
      pocket: pocket,
      amountMinor: amount,
      sortOrder: 0,
    ),
    if (type == LedgerTransactionType.transfer)
      LedgerMovement(
        id: EntityId.generate(),
        pocket: LedgerPocket(
          id: EntityId.generate(),
          currency: CurrencyCode.brl,
          nature: AccountNature.asset,
        ),
        amountMinor: -amount,
        sortOrder: 1,
      ),
  ];
  final splits = switch (type) {
    LedgerTransactionType.expense || LedgerTransactionType.income => [
      LedgerSplit(
        id: EntityId.generate(),
        categoryId: EntityId.generate(),
        money: Money(currency: CurrencyCode.brl, minorUnits: 1000),
        sortOrder: 0,
      ),
    ],
    _ => <LedgerSplit>[],
  };
  return LedgerTransaction(
    id: EntityId.generate(),
    vaultId: EntityId.generate(),
    type: type,
    status: status,
    financialDate: LocalDate(2026, 9, 21),
    movements: movements,
    splits: splits,
    createdAt: const UtcInstant.fromEpochMicroseconds(1),
    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
  );
}
