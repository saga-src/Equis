import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/application/ports/sync_aggregate_store.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/account_removal_assessment.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/accounts/account_management_screen.dart';
import 'package:equis/presentation/credit_cards/credit_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blocked account shows reasons and cannot be removed', (
    tester,
  ) async {
    final account = _account('Checking');
    var removed = false;
    await _show(
      tester,
      AccountManagementScreen(
        accounts: [account],
        assessRemoval: (_) async => _assessment(
          account,
          blockers: {AccountRemovalBlocker.pocketBalance},
          balance: 1500,
        ),
        removeAccount: (_) async => removed = true,
        restoreAccount: (_) async {},
      ),
    );
    await tester.tap(find.byTooltip('Review removal'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A pocket has a nonzero balance.'),
      findsOneWidget,
    );
    expect(find.textContaining('15.00'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
    expect(find.text('Archive account'), findsNothing);
    expect(removed, isFalse);
  });

  testWidgets('account with history can be archived and restored', (
    tester,
  ) async {
    final account = _account('Credit card', type: AccountType.creditCard);
    var accounts = [account];
    var removed = 0;
    var restored = 0;
    late StateSetter refresh;
    await _show(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return AccountManagementScreen(
            accounts: accounts,
            assessRemoval: (_) async => _assessment(
              account,
              references: {AccountReferenceKind.movements: 2},
            ),
            removeAccount: (_) async {
              removed++;
              refresh(() => accounts = [_archived(account)]);
            },
            restoreAccount: (_) async {
              restored++;
              refresh(() => accounts = [account]);
            },
          );
        },
      ),
    );
    await tester.tap(find.byTooltip('Review removal'));
    await tester.pumpAndSettle();
    expect(find.text('Movements: 2'), findsOneWidget);
    expect(find.text('Archive account'), findsOneWidget);
    await tester.tap(find.text('Archive account'));
    await tester.pumpAndSettle();
    expect(removed, 1);
    expect(find.text('No active accounts or cards.'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore account').last);
    await tester.pumpAndSettle();
    expect(restored, 1);
    expect(find.text('No archived accounts or cards.'), findsOneWidget);
  });

  testWidgets('empty account can be deleted and last card has empty state', (
    tester,
  ) async {
    final card = _account('Only card', type: AccountType.creditCard);
    var accounts = [card];
    late StateSetter refresh;
    await _show(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return AccountManagementScreen(
            accounts: accounts,
            assessRemoval: (_) async => _assessment(card),
            removeAccount: (_) async => refresh(() => accounts = []),
            restoreAccount: (_) async {},
          );
        },
      ),
    );
    await tester.tap(find.byTooltip('Review removal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('No active accounts or cards.'), findsOneWidget);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [creditCardContextsProvider.overrideWithValue(const [])],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CreditCardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Create a credit-card account on Home to get started.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets(
    'deleted recovery root needs confirmation and pending disables repeat',
    (tester) async {
      final original = _account('Recovered card', type: AccountType.creditCard);
      final deleted = original.withAccount(
        original.account.revise(deletedAt: _now, at: _now),
      );
      var requests = 0;
      var recovery = AccountSyncRecoveryState(
        accountId: deleted.account.id.value,
        revision: deleted.account.revision,
        restorationPending: false,
      );
      late StateSetter refresh;
      await _show(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            return AccountManagementScreen(
              accounts: [deleted],
              recoveryStates: [recovery],
              assessRemoval: (_) async => _assessment(deleted),
              removeAccount: (_) async {},
              restoreAccount: (_) async {},
              requestRecovery: (state) async {
                expect(state.revision, deleted.account.revision);
                requests++;
                refresh(
                  () => recovery = AccountSyncRecoveryState(
                    accountId: state.accountId,
                    revision: state.revision + 1,
                    restorationPending: true,
                  ),
                );
              },
            );
          },
        ),
      );
      expect(find.text('Recovered card'), findsOneWidget);
      expect(requests, 0);
      await tester.tap(find.byTooltip('Restore account'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.tap(find.text('Restore account').last);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(
        find.text('Restoration requested. Waiting for synchronization.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Restore account'), findsNothing);
    },
  );

  testWidgets('revision change during confirmation prevents stale removal', (
    tester,
  ) async {
    final original = _account('Checking');
    var account = original;
    var removed = 0;
    var refreshes = 0;
    late StateSetter update;
    await _show(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return AccountManagementScreen(
            accounts: [account],
            assessRemoval: (_) async => _assessment(account),
            removeAccount: (_) async => removed++,
            restoreAccount: (_) async {},
            refreshAccounts: () => refreshes++,
          );
        },
      ),
    );
    await tester.tap(find.byTooltip('Review removal'));
    await tester.pumpAndSettle();
    update(
      () => account = original.withAccount(
        original.account.revise(name: 'Changed', at: _now),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(removed, 0);
    expect(refreshes, 1);
    expect(
      find.text(
        'This account changed. Review its current state and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Portuguese narrow screen shows actionable blockers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _account('Conta com nome comprido para conferir a leitura');
    await _show(
      tester,
      AccountManagementScreen(
        accounts: [account],
        assessRemoval: (_) async => _assessment(
          account,
          blockers: {AccountRemovalBlocker.activeRecurrence},
        ),
        removeAccount: (_) async {},
        restoreAccount: (_) async {},
      ),
      locale: const Locale('pt', 'BR'),
    );
    await tester.tap(find.byTooltip('Revisar remoção'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Uma recorrência ativa usa esta conta.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

final _vaultId = EntityId.generate();
const _now = UtcInstant.fromEpochMicroseconds(1);

AccountAggregate _account(
  String name, {
  AccountType type = AccountType.checking,
}) {
  final accountId = EntityId.generate();
  return AccountAggregate(
    account: AccountProfile(
      id: accountId,
      vaultId: _vaultId,
      name: name,
      type: type,
      nature: type == AccountType.creditCard
          ? AccountNature.liability
          : AccountNature.asset,
      createdAt: _now,
      updatedAt: _now,
    ),
    pockets: [
      AccountPocketProfile(
        id: EntityId.generate(),
        accountId: accountId,
        currency: CurrencyCode.brl,
        isDefault: true,
      ),
    ],
  );
}

AccountAggregate _archived(AccountAggregate account) =>
    account.withAccount(account.account.revise(archived: true, at: _now));

AccountRemovalAssessment _assessment(
  AccountAggregate account, {
  Set<AccountRemovalBlocker> blockers = const {},
  Map<AccountReferenceKind, int> references = const {},
  int balance = 0,
}) => AccountRemovalAssessment(
  aggregate: account,
  balances: [
    AccountPocketBalance(
      pocketId: account.pockets.single.id,
      currency: CurrencyCode.brl,
      minorUnits: balance,
    ),
  ],
  blockers: blockers,
  references: references,
);

Future<void> _show(WidgetTester tester, Widget home, {Locale? locale}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}
