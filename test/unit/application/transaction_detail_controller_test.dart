import 'dart:async';

import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/presentation/transactions/transaction_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail distinguishes loading, absence, error, and data', () async {
    final transaction = _transaction();
    var calls = 0;
    final pending = Completer<TransactionDetailData?>();
    final controller = TransactionDetailController(() {
      calls++;
      return switch (calls) {
        1 => pending.future,
        2 => Future.error(StateError('disk read failed')),
        _ => Future.value(_detail(transaction)),
      };
    });
    addTearDown(controller.dispose);

    final first = controller.reload();
    expect(controller.state.status, TransactionDetailStatus.loading);
    pending.complete(null);
    await first;
    expect(controller.state.status, TransactionDetailStatus.missing);

    await controller.reload();
    expect(controller.state.status, TransactionDetailStatus.error);
    expect(controller.state.error, isA<StateError>());

    await controller.reload();
    expect(controller.state.status, TransactionDetailStatus.ready);
    expect(controller.state.transaction, same(transaction));
  });

  test('older load cannot replace the result of a newer reload', () async {
    final stale = Completer<TransactionDetailData?>();
    final current = Completer<TransactionDetailData?>();
    var calls = 0;
    final controller = TransactionDetailController(
      () => ++calls == 1 ? stale.future : current.future,
    );
    addTearDown(controller.dispose);

    final first = controller.reload();
    final second = controller.reload();
    current.complete(null);
    await second;
    stale.complete(_detail(_transaction()));
    await first;
    expect(controller.state.status, TransactionDetailStatus.missing);
  });
}

TransactionDetailData _detail(LedgerTransaction transaction) =>
    TransactionDetailData(
      transaction: transaction,
      accounts: const [],
      categories: const [],
      tags: const [],
    );

LedgerTransaction _transaction() {
  const now = UtcInstant.fromEpochMicroseconds(1);
  return LedgerTransaction(
    id: EntityId.generate(),
    vaultId: EntityId.generate(),
    type: LedgerTransactionType.openingBalance,
    status: LedgerTransactionStatus.cleared,
    financialDate: LocalDate(2026, 8, 1),
    movements: [
      LedgerMovement(
        id: EntityId.generate(),
        pocket: LedgerPocket(
          id: EntityId.generate(),
          currency: CurrencyCode.brl,
          nature: AccountNature.asset,
        ),
        amountMinor: 100,
        sortOrder: 0,
      ),
    ],
    splits: const [],
    createdAt: now,
    updatedAt: now,
  );
}
