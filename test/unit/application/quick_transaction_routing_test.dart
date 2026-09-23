import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/quick_transaction_routing.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card expense routes to credit-card purchase lifecycle', () {
    expect(
      quickTransactionRoute(
        type: EverydayTransactionType.expense,
        accountType: AccountType.creditCard,
      ),
      QuickTransactionRoute.creditCardPurchase,
    );
  });

  test('ordinary expense remains an everyday transaction', () {
    expect(
      quickTransactionRoute(
        type: EverydayTransactionType.expense,
        accountType: AccountType.checking,
      ),
      QuickTransactionRoute.everyday,
    );
  });

  test('card accounts are rejected for quick income and transfer', () {
    for (final type in [
      EverydayTransactionType.income,
      EverydayTransactionType.transfer,
    ]) {
      expect(
        () => quickTransactionRoute(
          type: type,
          accountType: AccountType.creditCard,
        ),
        throwsArgumentError,
      );
    }
  });
}
