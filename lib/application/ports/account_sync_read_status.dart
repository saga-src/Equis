import '../../domain/shared/uuid_v7.dart';

/// Optional read capability for repositories with durable account sync state.
abstract interface class AccountSyncReadStatus {
  /// Pending encrypted events can affect any reporting date until replayed.
  Future<bool> hasIncompleteAccounts(EntityId vaultId);
}
