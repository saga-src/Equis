import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/transactions/quick_transaction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'quick path requests amount, type, account, category, then saves',
    (tester) async {
      QuickTransactionDraft? saved;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuickTransactionScreen(
            accounts: _accounts,
            categories: _categories,
            tags: const [],
            onSave: (draft) async => saved = draft,
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).first, '45.90');
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();

      expect(saved?.type, QuickTransactionType.expense);
      expect(saved?.amountText, '45.90');
      expect(saved?.sourcePocketId, _sourceId);
      expect(saved?.categoryId, _expenseCategoryId);
      expect(find.text('Transaction saved locally'), findsOneWidget);
    },
  );

  testWidgets('transfer replaces category with compatible destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuickTransactionScreen(
          accounts: _accounts,
          categories: _categories,
          tags: const [],
          onSave: _discard,
        ),
      ),
    );
    expect(find.text('Category'), findsOneWidget);
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    expect(find.text('Category'), findsNothing);
    expect(find.text('To account'), findsOneWidget);
  });
}

final _sourceId = EntityId.parse('01900000-0000-7000-8000-000000000101');
final _destinationId = EntityId.parse('01900000-0000-7000-8000-000000000102');
final _expenseCategoryId = EntityId.parse(
  '01900000-0000-7000-8000-000000000103',
);

final _accounts = [
  QuickAccountOption(
    label: 'Checking · BRL',
    pocket: LedgerPocket(
      id: _sourceId,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    ),
  ),
  QuickAccountOption(
    label: 'Wallet · BRL',
    pocket: LedgerPocket(
      id: _destinationId,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    ),
  ),
];

final _categories = [
  QuickCategoryOption(
    id: _expenseCategoryId,
    label: 'Groceries',
    type: CategoryType.expense,
  ),
  QuickCategoryOption(
    id: EntityId.parse('01900000-0000-7000-8000-000000000104'),
    label: 'Salary',
    type: CategoryType.income,
  ),
];

Future<void> _discard(QuickTransactionDraft _) async {}
