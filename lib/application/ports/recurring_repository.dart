import '../../domain/ledger/ledger_models.dart';
import '../../domain/recurring/recurrence_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class RecurringRepository {
  Future<void> save(RecurringSchedule schedule);
  Future<RecurringSchedule?> find(EntityId ruleId);
  Future<List<RecurringSchedule>> listForVault(EntityId vaultId);
  Future<Map<String, LedgerTransaction>> materializedOccurrences({
    required Set<EntityId> ruleIds,
    required LocalDate from,
    required LocalDate through,
  });
}

String occurrenceKey(EntityId ruleId, LocalDate recurrenceDate) =>
    '${ruleId.value}|$recurrenceDate';

final class RecurringRevisionConflict implements Exception {
  const RecurringRevisionConflict(this.ruleId);
  final EntityId ruleId;
}
