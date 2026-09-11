import '../../domain/cloud/cloud_identity_models.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class CloudAuthGateway {
  CloudAuthIdentity? get currentIdentity;
  String? get currentAccessToken;
  Stream<CloudAuthIdentity?> get identityChanges;

  Future<CloudAuthIdentity> signUp({
    required String email,
    required String password,
  });
  Future<CloudAuthIdentity> signIn({
    required String email,
    required String password,
  });
  Future<void> resendVerification(String email);
  Future<void> signOut();
}

abstract interface class CloudIdentityRepository {
  Future<LocalDeviceIdentity?> findDevice(EntityId vaultId);
  Future<void> saveDevice(LocalDeviceIdentity device);
  Future<VaultCloudBinding?> findBinding(EntityId vaultId);
  Future<void> saveBinding(VaultCloudBinding binding);
}
