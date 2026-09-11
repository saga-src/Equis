import '../../domain/cloud/cloud_identity_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../ports/cloud_identity_ports.dart';

final class CloudAccountService {
  const CloudAccountService({
    required this.repository,
    required this.deviceName,
    required this.platform,
    this.auth,
  });

  final CloudIdentityRepository repository;
  final CloudAuthGateway? auth;
  final String deviceName;
  final String platform;

  bool get configured => auth != null;
  String? get currentAccessToken => auth?.currentAccessToken;
  Stream<CloudAuthIdentity?> get identityChanges =>
      auth?.identityChanges ?? const Stream.empty();

  Future<CloudAccountSnapshot> load({
    required EntityId vaultId,
    required UtcInstant now,
  }) async {
    final device = await _ensureDevice(vaultId, now);
    final binding = await repository.findBinding(vaultId);
    final gateway = auth;
    if (gateway == null) {
      return CloudAccountSnapshot(
        status: CloudAccountStatus.localOnly,
        device: device,
        binding: binding,
      );
    }
    final identity = gateway.currentIdentity;
    return CloudAccountSnapshot(
      status: _status(identity, binding),
      device: device,
      identity: identity,
      binding: binding,
    );
  }

  Future<CloudAccountSnapshot> createAccount({
    required EntityId vaultId,
    required String email,
    required String password,
    required UtcInstant now,
  }) async {
    final gateway = _requiredAuth;
    final identity = await gateway.signUp(
      email: email.trim(),
      password: password,
    );
    if (identity.emailVerified && identity.hasActiveSession) {
      await _bind(vaultId, identity, now);
    }
    return load(vaultId: vaultId, now: now);
  }

  Future<CloudAccountSnapshot> signIn({
    required EntityId vaultId,
    required String email,
    required String password,
    required UtcInstant now,
  }) async {
    final identity = await _requiredAuth.signIn(
      email: email.trim(),
      password: password,
    );
    if (!identity.emailVerified || !identity.hasActiveSession) {
      throw const CloudAuthFailure(CloudAuthFailureCode.emailNotVerified);
    }
    await _bind(vaultId, identity, now);
    return load(vaultId: vaultId, now: now);
  }

  Future<CloudAuthIdentity> authenticateExisting({
    required String email,
    required String password,
  }) async {
    final identity = await _requiredAuth.signIn(
      email: email.trim(),
      password: password,
    );
    if (!identity.emailVerified || !identity.hasActiveSession) {
      throw const CloudAuthFailure(CloudAuthFailureCode.emailNotVerified);
    }
    return identity;
  }

  Future<void> resendVerification(String email) =>
      _requiredAuth.resendVerification(email.trim());

  Future<CloudAccountSnapshot> signOut({
    required EntityId vaultId,
    required UtcInstant now,
  }) async {
    await _requiredAuth.signOut();
    return load(vaultId: vaultId, now: now);
  }

  Future<LocalDeviceIdentity> _ensureDevice(
    EntityId vaultId,
    UtcInstant now,
  ) async {
    final existing = await repository.findDevice(vaultId);
    final device = existing == null
        ? LocalDeviceIdentity(
            id: EntityId.generate(),
            vaultId: vaultId,
            name: deviceName,
            platform: platform,
            createdAt: now,
            lastSeenAt: now,
          )
        : existing.seen(now);
    await repository.saveDevice(device);
    return device;
  }

  Future<void> _bind(
    EntityId vaultId,
    CloudAuthIdentity identity,
    UtcInstant now,
  ) async {
    final existing = await repository.findBinding(vaultId);
    if (existing != null && existing.authUserId != identity.authUserId) {
      throw const CloudAuthFailure(CloudAuthFailureCode.vaultUserMismatch);
    }
    await repository.saveBinding(
      existing ??
          VaultCloudBinding(
            vaultId: vaultId,
            authUserId: identity.authUserId,
            syncEnabled: false,
            linkedAt: now,
          ),
    );
  }

  CloudAuthGateway get _requiredAuth =>
      auth ?? (throw const CloudAuthFailure(CloudAuthFailureCode.unavailable));
}

CloudAccountStatus _status(
  CloudAuthIdentity? identity,
  VaultCloudBinding? binding,
) {
  if (identity == null) {
    return binding == null
        ? CloudAccountStatus.signedOut
        : CloudAccountStatus.sessionExpired;
  }
  if (!identity.emailVerified || !identity.hasActiveSession) {
    return CloudAccountStatus.awaitingEmailVerification;
  }
  return CloudAccountStatus.signedIn;
}
