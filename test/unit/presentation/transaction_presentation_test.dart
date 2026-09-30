import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
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

  test('quick edit rejects multi-split and hidden children', () {
    final expense = _transaction(
      type: LedgerTransactionType.expense,
      status: LedgerTransactionStatus.cleared,
    );
    expect(transactionIsEditable(expense), isTrue);
    final multiSplit = expense.revise(
      movements: expense.movements,
      splits: [
        LedgerSplit(
          id: EntityId.generate(),
          categoryId: expense.splits.single.categoryId,
          money: Money(currency: CurrencyCode.brl, minorUnits: 500),
          sortOrder: 0,
        ),
        LedgerSplit(
          id: EntityId.generate(),
          categoryId: expense.splits.single.categoryId,
          money: Money(currency: CurrencyCode.brl, minorUnits: 500),
          sortOrder: 1,
        ),
      ],
      at: const UtcInstant.fromEpochMicroseconds(2),
    );
    expect(transactionIsEditable(multiSplit), isFalse);
    expect(transactionActions(multiSplit), isNot(contains(TransactionAction.edit)));
    final statement = LedgerTransaction(
      id: EntityId.generate(),
      vaultId: expense.vaultId,
      type: expense.type,
      status: expense.status,
      financialDate: expense.financialDate,
      movements: [
        LedgerMovement(
          id: EntityId.generate(),
          pocket: expense.movements.single.pocket,
          amountMinor: -1000,
          sortOrder: 0,
          statementId: EntityId.generate(),
        ),
      ],
      splits: expense.splits,
      createdAt: expense.createdAt,
      updatedAt: expense.updatedAt,
    );
    expect(transactionIsEditable(statement), isFalse);
  });

  test('quick edit needs current active account, pocket and category', () {
    final expense = _transaction(
      type: LedgerTransactionType.expense,
      status: LedgerTransactionStatus.cleared,
    );
    final accountId = EntityId.generate();
    AccountAggregate account({bool archived = false, bool pocketArchived = false}) =>
        AccountAggregate(
          account: AccountProfile(
            id: accountId,
            vaultId: expense.vaultId,
            name: 'Checking',
            type: AccountType.checking,
            nature: AccountNature.asset,
            archived: archived,
            createdAt: expense.createdAt,
            updatedAt: expense.updatedAt,
          ),
          pockets: [
            AccountPocketProfile(
              id: expense.movements.single.pocket.id,
              accountId: accountId,
              currency: CurrencyCode.brl,
              isDefault: true,
              archived: pocketArchived,
            ),
          ],
        );
    CategoryNode category({bool archived = false}) => CategoryNode(
      id: expense.splits.single.categoryId,
      vaultId: expense.vaultId,
      type: CategoryType.expense,
      customName: 'Food',
      archived: archived,
      createdAt: expense.createdAt,
      updatedAt: expense.updatedAt,
    );
    bool allowed(AccountAggregate accountRow, CategoryNode categoryRow) =>
        everydayTransactionCanEdit(
          expense,
          accounts: [accountRow],
          categories: [categoryRow],
        );
    expect(allowed(account(), category()), isTrue);
    expect(allowed(account(archived: true), category()), isFalse);
    expect(allowed(account(pocketArchived: true), category()), isFalse);
    expect(allowed(account(), category(archived: true)), isFalse);
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
