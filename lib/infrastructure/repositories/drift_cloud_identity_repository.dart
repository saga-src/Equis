import 'package:drift/drift.dart';

import '../../application/ports/cloud_identity_ports.dart';
import '../../domain/cloud/cloud_identity_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart' hide VaultCloudBinding;

final class DriftCloudIdentityRepository implements CloudIdentityRepository {
  const DriftCloudIdentityRepository(this.database);
  final EquisDatabase database;

  @override
  Future<LocalDeviceIdentity?> findDevice(EntityId vaultId) async {
    final row =
        await (database.select(database.devices)
              ..where((value) => value.vaultId.equals(vaultId.value))
              ..orderBy([(value) => OrderingTerm.asc(value.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return LocalDeviceIdentity(
      id: EntityId.parse(row.id!),
      vaultId: vaultId,
      name: row.name,
      platform: row.platform,
      createdAt: UtcInstant.fromEpochMicroseconds(row.createdAt),
      lastSeenAt: row.lastSeenAt == null
          ? null
          : UtcInstant.fromEpochMicroseconds(row.lastSeenAt!),
    );
  }

  @override
  Future<void> saveDevice(LocalDeviceIdentity device) => database
      .into(database.devices)
      .insertOnConflictUpdate(
        DevicesCompanion.insert(
          id: Value(device.id.value),
          vaultId: device.vaultId.value,
          name: device.name,
          platform: device.platform,
          createdAt: device.createdAt.epochMicroseconds,
          lastSeenAt: Value(device.lastSeenAt?.epochMicroseconds),
        ),
      );

  @override
  Future<VaultCloudBinding?> findBinding(EntityId vaultId) async {
    final row = await (database.select(
      database.vaultCloudBindings,
    )..where((value) => value.vaultId.equals(vaultId.value))).getSingleOrNull();
    return row == null
        ? null
        : VaultCloudBinding(
            vaultId: vaultId,
            authUserId: row.authUserId,
            syncEnabled: row.syncEnabled != 0,
            linkedAt: UtcInstant.fromEpochMicroseconds(row.linkedAt),
          );
  }

  @override
  Future<void> saveBinding(VaultCloudBinding binding) => database
      .into(database.vaultCloudBindings)
      .insertOnConflictUpdate(
        VaultCloudBindingsCompanion.insert(
          vaultId: Value(binding.vaultId.value),
          authUserId: binding.authUserId,
          syncEnabled: Value(binding.syncEnabled ? 1 : 0),
          linkedAt: binding.linkedAt.epochMicroseconds,
        ),
      );
}
