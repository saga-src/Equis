import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class StartupRefreshGate {
  Future<UtcInstant?> lastAttempt(EntityId vaultId);
  Future<void> recordAttempt(EntityId vaultId, UtcInstant at);
}
