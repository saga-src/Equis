import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/wealth/asset_models.dart';
import '../../domain/wealth/net_worth_models.dart';

abstract interface class WealthRepository {
  Future<void> saveAsset(PhysicalAsset asset);
  Future<PhysicalAsset?> findAsset(EntityId id);
  Future<List<PhysicalAsset>> listAssets(EntityId vaultId);
  Future<void> addValuation(AssetValuation valuation);
  Future<List<AssetValuation>> valuations(
    EntityId assetId, {
    LocalDate? through,
  });
  Future<List<NetWorthAccountBalance>> accountBalances(
    EntityId vaultId,
    LocalDate asOf,
  );
}

final class AssetRevisionConflict implements Exception {
  const AssetRevisionConflict({
    required this.id,
    required this.expected,
    required this.actual,
  });
  final EntityId id;
  final int expected;
  final int? actual;
}
