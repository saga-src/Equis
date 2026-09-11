import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class LedgerRepository {
  Future<void> save(LedgerTransaction transaction);
  Future<LedgerTransaction?> find(EntityId id);
  Future<List<LedgerTransaction>> listRecentForVault(
    EntityId vaultId, {
    int limit = 20,
  });
}

final class LedgerRevisionConflict implements Exception {
  const LedgerRevisionConflict({
    required this.transactionId,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final EntityId transactionId;
  final int expectedRevision;
  final int? actualRevision;

  @override
  String toString() =>
      'LedgerRevisionConflict(transactionId: $transactionId, '
      'expectedRevision: $expectedRevision, actualRevision: $actualRevision)';
}
