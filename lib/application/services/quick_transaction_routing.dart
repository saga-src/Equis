import '../../domain/entities/account_profile.dart';
import 'everyday_transaction_service.dart';

enum QuickTransactionRoute { everyday, creditCardPurchase }

QuickTransactionRoute quickTransactionRoute({
  required EverydayTransactionType type,
  required AccountType accountType,
}) {
  if (accountType != AccountType.creditCard) {
    return QuickTransactionRoute.everyday;
  }
  if (type != EverydayTransactionType.expense) {
    throw ArgumentError(
      'Credit-card accounts are only valid for new quick expenses.',
    );
  }
  return QuickTransactionRoute.creditCardPurchase;
}
