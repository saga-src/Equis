import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/transactions/transaction_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('colors icon and amount and renders the shared eligible menu', (
    tester,
  ) async {
    final transactions = [
      _transaction(LedgerTransactionType.expense),
      _transaction(LedgerTransactionType.income),
      _transaction(LedgerTransactionType.transfer),
      _transaction(LedgerTransactionType.adjustment),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: EquisTheme.trueLight,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              for (final transaction in transactions)
                Row(
                  children: [
                    TransactionSemanticIcon(transaction: transaction),
                    TransactionAmountText(transaction: transaction),
                    TransactionActionMenu(
                      transaction: transaction,
                      onSelected: (_) {},
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

    const expected = [
      Color(0xFFB91C1C),
      Color(0xFF047857),
      Color(0xFF1D4ED8),
      Color(0xFF334155),
    ];
    for (var index = 0; index < transactions.length; index++) {
      final id = transactions[index].id.value;
      expect(
        tester.widget<Icon>(find.byKey(ValueKey('transaction-icon-$id'))).color,
        expected[index],
      );
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('transaction-amount-$id')))
            .style!
            .color,
        expected[index],
      );
    }

    final expense = transactions.first;
    await tester.tap(
      find.byKey(ValueKey('transaction-actions-${expense.id.value}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.text('Reconcile transaction'), findsOneWidget);
    expect(find.text('Delete transaction'), findsOneWidget);
  });
}

LedgerTransaction _transaction(LedgerTransactionType type) {
  final amount = type == LedgerTransactionType.income ? 1000 : -1000;
  final pocket = LedgerPocket(
    id: EntityId.generate(),
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  return LedgerTransaction(
    id: EntityId.generate(),
    vaultId: EntityId.generate(),
    type: type,
    status: LedgerTransactionStatus.cleared,
    financialDate: LocalDate(2026, 9, 21),
    movements: [
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
    ],
    splits: switch (type) {
      LedgerTransactionType.expense || LedgerTransactionType.income => [
        LedgerSplit(
          id: EntityId.generate(),
          categoryId: EntityId.generate(),
          money: Money(currency: CurrencyCode.brl, minorUnits: 1000),
          sortOrder: 0,
        ),
      ],
      _ => const [],
    },
    createdAt: const UtcInstant.fromEpochMicroseconds(1),
    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
  );
}
