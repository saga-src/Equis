import '../entities/account_profile.dart';
import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/uuid_v7.dart';
import 'asset_models.dart';

final class NetWorthAccountBalance {
  const NetWorthAccountBalance({
    required this.accountId,
    required this.accountName,
    required this.nature,
    required this.currency,
    required this.balanceMinor,
  });
  final EntityId accountId;
  final String accountName;
  final AccountNature nature;
  final CurrencyCode currency;
  final int balanceMinor;
}

final class NetWorthPoint {
  const NetWorthPoint({
    required this.date,
    required this.assetsMinor,
    required this.liabilitiesMinor,
    required this.missingRates,
    required this.usesEstimatedRates,
  });
  final LocalDate date;
  final int assetsMinor;
  final int liabilitiesMinor;
  final Set<CurrencyCode> missingRates;
  final bool usesEstimatedRates;
  int get netWorthMinor => assetsMinor - liabilitiesMinor;
}

final class NetWorthReport {
  NetWorthReport({
    required this.currency,
    required this.current,
    required List<NetWorthPoint> history,
    required List<AssetValue> physicalAssets,
  }) : history = List.unmodifiable(history),
       physicalAssets = List.unmodifiable(physicalAssets);
  final CurrencyCode currency;
  final NetWorthPoint current;
  final List<NetWorthPoint> history;
  final List<AssetValue> physicalAssets;
}
