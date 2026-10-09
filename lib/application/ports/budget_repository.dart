import '../../domain/budgeting/budget_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/shared/utc_instant.dart';

abstract interface class BudgetRepository {
  Future<void> save(
    BudgetDefinition budget, {
    BudgetMonthlyConfiguration? initialMonthlyConfiguration,
  });
  Future<BudgetDefinition?> find(EntityId id);
  Future<List<BudgetDefinition>> listForVault(
    EntityId vaultId, {
    bool includeDeleted = false,
  });
  Future<BudgetMonthlyHistory> loadMonthlyHistory(EntityId budgetId);
  Future<BudgetDefinition> saveMonthlyEdit({
    required EntityId budgetId,
    required EntityId vaultId,
    required int expectedRevision,
    required BudgetMonth month,
    required BudgetMonthlyConfiguration configuration,
    required BudgetMonthlyEditScope scope,
    required UtcInstant now,
    String? name,
  });

  Future<List<BudgetUsageRow>> loadUsageRows({
    required EntityId vaultId,
    required LocalDate from,
    required LocalDate through,
  });

  Future<Map<EntityId, EntityId?>> loadCategoryParents(EntityId vaultId);
}

final class BudgetRevisionConflict implements Exception {
  const BudgetRevisionConflict({
    required this.id,
    required this.expected,
    required this.actual,
  });

  final EntityId id;
  final int expected;
  final int? actual;
}
