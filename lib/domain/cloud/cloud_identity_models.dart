import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum CloudAccountStatus {
  localOnly,
  signedOut,
  awaitingEmailVerification,
  signedIn,
  sessionExpired,
}

enum CloudAuthFailureCode {
  unavailable,
  invalidCredentials,
  emailNotVerified,
  weakPassword,
  accountAlreadyExists,
  rateLimited,
  network,
  vaultUserMismatch,
  unknown,
}

final class CloudAuthIdentity {
  const CloudAuthIdentity({
    required this.authUserId,
    required this.email,
    required this.emailVerified,
    required this.hasActiveSession,
  });

  final String authUserId;
  final String email;
  final bool emailVerified;
  final bool hasActiveSession;
}

final class LocalDeviceIdentity {
  LocalDeviceIdentity({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.platform,
    required this.createdAt,
    this.lastSeenAt,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (platform != 'android' && platform != 'windows') {
      throw ArgumentError.value(platform, 'platform');
    }
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final String platform;
  final UtcInstant createdAt;
  final UtcInstant? lastSeenAt;

  LocalDeviceIdentity seen(UtcInstant at) => LocalDeviceIdentity(
    id: id,
    vaultId: vaultId,
    name: name,
    platform: platform,
    createdAt: createdAt,
    lastSeenAt: at,
  );
}

final class VaultCloudBinding {
  const VaultCloudBinding({
    required this.vaultId,
    required this.authUserId,
    required this.syncEnabled,
    required this.linkedAt,
  });

  final EntityId vaultId;
  final String authUserId;
  final bool syncEnabled;
  final UtcInstant linkedAt;
}

final class CloudAccountSnapshot {
  const CloudAccountSnapshot({
    required this.status,
    required this.device,
    this.identity,
    this.binding,
  });

  final CloudAccountStatus status;
  final LocalDeviceIdentity device;
  final CloudAuthIdentity? identity;
  final VaultCloudBinding? binding;

  bool get localAccessAvailable => true;
  bool get cloudConfigured => status != CloudAccountStatus.localOnly;
}

final class CloudAuthFailure implements Exception {
  const CloudAuthFailure(this.code);
  final CloudAuthFailureCode code;
}
