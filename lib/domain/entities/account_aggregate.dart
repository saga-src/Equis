import '../shared/currency.dart';
import '../shared/uuid_v7.dart';
import 'account_profile.dart';

final class AccountPocketProfile {
  const AccountPocketProfile({
    required this.id,
    required this.accountId,
    required this.currency,
    this.name,
    this.isDefault = false,
    this.archived = false,
  });

  final EntityId id;
  final EntityId accountId;
  final CurrencyCode currency;
  final String? name;
  final bool isDefault;
  final bool archived;
}

final class AccountAggregate {
  AccountAggregate({
    required this.account,
    required List<AccountPocketProfile> pockets,
  }) : pockets = List.unmodifiable(pockets) {
    if (pockets.isEmpty) {
      throw ArgumentError('An account needs at least one currency pocket.');
    }
    if (pockets.any((pocket) => pocket.accountId != account.id)) {
      throw ArgumentError('Every pocket must belong to the aggregate account.');
    }
    final currencies = pockets.map((pocket) => pocket.currency).toSet();
    if (currencies.length != pockets.length) {
      throw ArgumentError('An account cannot repeat a currency pocket.');
    }
    if (pockets.where((pocket) => pocket.isDefault).length != 1) {
      throw ArgumentError('An account needs exactly one default pocket.');
    }
  }

  final AccountProfile account;
  final List<AccountPocketProfile> pockets;

  AccountAggregate addPocket(AccountPocketProfile pocket) =>
      AccountAggregate(account: account, pockets: [...pockets, pocket]);

  AccountAggregate withAccount(AccountProfile value) =>
      AccountAggregate(account: value, pockets: pockets);
}
