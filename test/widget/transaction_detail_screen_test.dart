import 'package:equis/app/router/app_router.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/transactions/transaction_detail_screen.dart';
import 'package:equis/presentation/transactions/local_transaction_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('details and editor remain separate routes', (tester) async {
    final router = createAppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    final id = EntityId.generate();
    router.go('/transactions/${id.value}/details');
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.byType(LocalTransactionPage), findsNothing);
    router.go('/transactions/${id.value}');
    await tester.pumpAndSettle();
    expect(find.byType(LocalTransactionPage), findsOneWidget);
  });

  testWidgets('all movements retain the archived account name', (tester) async {
    final first = _account('Everyday', archived: true);
    final second = _account('Savings', pocketArchived: true);
    final transaction = _transaction(
      type: LedgerTransactionType.transfer,
      movements: [_movement(first, -2500, 0), _movement(second, 2500, 1)],
    );
    await _show(
      tester,
      TransactionDetailData(
        transaction: transaction,
        accounts: [first, second],
        categories: const [],
        tags: const [],
      ),
    );
    expect(
      find.textContaining('Everyday · BRL (Archived account)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Savings · BRL (Archived pocket)'),
      findsOneWidget,
    );
    expect(find.text('Account movements'), findsOneWidget);
  });

  testWidgets('split memo, archived category, tag and notes are visible', (
    tester,
  ) async {
    final account = _account('Everyday');
    final category = CategoryNode(
      id: EntityId.generate(),
      vaultId: _vaultId,
      type: CategoryType.expense,
      customName: 'Old groceries',
      archived: true,
      createdAt: _now,
      updatedAt: _now,
    );
    final tag = Tag(
      id: EntityId.generate(),
      vaultId: _vaultId,
      name: 'Trip',
      createdAt: _now,
      updatedAt: _now,
    );
    final transaction = _transaction(
      type: LedgerTransactionType.expense,
      movements: [_movement(account, -500, 0)],
      splits: [
        LedgerSplit(
          id: EntityId.generate(),
          categoryId: category.id,
          money: Money(currency: CurrencyCode.brl, minorUnits: 500),
          sortOrder: 0,
          memo: 'Lunch',
        ),
      ],
      tagIds: [tag.id],
      notes: 'Receipt saved',
    );
    await _show(
      tester,
      TransactionDetailData(
        transaction: transaction,
        accounts: [account],
        categories: [category],
        tags: [tag],
      ),
    );
    expect(find.text('Old groceries'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Receipt saved'), findsOneWidget);
  });

  testWidgets('FX and investment children expose their stored terms', (
    tester,
  ) async {
    final brl = _account('BRL');
    final usd = _account('USD', currency: CurrencyCode.usd);
    final from = _movement(brl, -500, 0);
    final to = _movement(usd, 100, 1);
    final fx = _transaction(
      type: LedgerTransactionType.currencyExchange,
      movements: [from, to],
      fxConversion: LedgerFxConversion(
        id: EntityId.generate(),
        fromMovementId: from.id,
        toMovementId: to.id,
        exchangeRate: '5',
        rateSource: 'manual',
        provider: 'Bank',
      ),
    );
    await _show(
      tester,
      TransactionDetailData(
        transaction: fx,
        accounts: [brl, usd],
        categories: const [],
        tags: const [],
      ),
    );
    expect(find.text('Currency conversion'), findsOneWidget);
    expect(find.text('Exchange rate: 5'), findsOneWidget);
    expect(find.text('Rate source: manual'), findsOneWidget);

    final instrument = EntityId.generate();
    final buy = _transaction(
      type: LedgerTransactionType.investmentBuy,
      movements: [_movement(brl, -3000, 0)],
      investmentEvents: [
        LedgerInvestmentEvent(
          id: EntityId.generate(),
          instrumentId: instrument,
          eventType: 'buy',
          quantity: '3',
          unitPrice: '10',
          priceCurrency: CurrencyCode.brl,
          grossMinor: 3000,
        ),
      ],
    );
    await _show(
      tester,
      TransactionDetailData(
        transaction: buy,
        accounts: [brl],
        categories: const [],
        tags: const [],
      ),
    );
    expect(find.text('Investment events'), findsOneWidget);
    expect(find.text('Instrument ID: ${instrument.value}'), findsOneWidget);
    expect(find.text('Quantity: 3'), findsOneWidget);
  });

  testWidgets('recurrence and reversal references are shown when present', (
    tester,
  ) async {
    final account = _account('Everyday');
    final ruleId = EntityId.generate();
    final previousId = EntityId.generate();
    final transaction = LedgerTransaction(
      id: EntityId.generate(),
      vaultId: _vaultId,
      type: LedgerTransactionType.adjustment,
      status: LedgerTransactionStatus.cleared,
      financialDate: LocalDate(2026, 9, 1),
      movements: [_movement(account, 100, 0)],
      splits: const [],
      recurringRuleId: ruleId,
      recurrenceDate: LocalDate(2026, 9, 1),
      reversalOfId: previousId,
      createdAt: _now,
      updatedAt: _now,
    );
    await _show(
      tester,
      TransactionDetailData(
        transaction: transaction,
        accounts: [account],
        categories: const [],
        tags: const [],
      ),
    );
    expect(find.text('Recurrence'), findsOneWidget);
    expect(find.text('Rule ID: ${ruleId.value}'), findsOneWidget);
    expect(find.text('Reversal'), findsOneWidget);
    expect(find.text('Reversal of: ${previousId.value}'), findsOneWidget);
  });
}

final _vaultId = EntityId.generate();
const _now = UtcInstant.fromEpochMicroseconds(1);

AccountAggregate _account(
  String name, {
  bool archived = false,
  CurrencyCode? currency,
  bool pocketArchived = false,
}) {
  final accountId = EntityId.generate();
  return AccountAggregate(
    account: AccountProfile(
      id: accountId,
      vaultId: _vaultId,
      name: name,
      type: AccountType.checking,
      nature: AccountNature.asset,
      archived: archived,
      createdAt: _now,
      updatedAt: _now,
    ),
    pockets: [
      AccountPocketProfile(
        id: EntityId.generate(),
        accountId: accountId,
        currency: currency ?? CurrencyCode.brl,
        isDefault: true,
        archived: pocketArchived,
      ),
    ],
  );
}

LedgerMovement _movement(AccountAggregate account, int amount, int order) =>
    LedgerMovement(
      id: EntityId.generate(),
      pocket: LedgerPocket(
        id: account.pockets.single.id,
        currency: account.pockets.single.currency,
        nature: AccountNature.asset,
      ),
      amountMinor: amount,
      sortOrder: order,
    );

LedgerTransaction _transaction({
  required LedgerTransactionType type,
  required List<LedgerMovement> movements,
  List<LedgerSplit> splits = const [],
  LedgerFxConversion? fxConversion,
  List<LedgerInvestmentEvent> investmentEvents = const [],
  List<EntityId> tagIds = const [],
  String? notes,
}) => LedgerTransaction(
  id: EntityId.generate(),
  vaultId: _vaultId,
  type: type,
  status: LedgerTransactionStatus.cleared,
  financialDate: LocalDate(2026, 9, 1),
  movements: movements,
  splits: splits,
  fxConversion: fxConversion,
  investmentEvents: investmentEvents,
  tagIds: tagIds,
  notes: notes,
  createdAt: _now,
  updatedAt: _now,
);

Future<void> _show(WidgetTester tester, TransactionDetailData data) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TransactionDetailContent(data: data)),
    ),
  );
  await tester.pumpAndSettle();
}
