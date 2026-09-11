import '../../domain/goals/cash_flow_projection.dart';
import '../../domain/goals/goal_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class GoalRepository {
  Future<void> save(GoalDefinition goal);
  Future<GoalDefinition?> find(EntityId id);
  Future<List<GoalDefinition>> listForVault(EntityId vaultId);
  Future<void> addContribution(GoalContribution contribution);
  Future<List<GoalContribution>> contributions(
    EntityId goalId, {
    required LocalDate through,
  });
  Future<List<GoalAccountBalance>> linkedBalances(
    GoalDefinition goal, {
    required LocalDate asOf,
  });
  Future<List<CashFlowSourceRow>> cashFlowSources({
    required EntityId vaultId,
    required LocalDate after,
    required LocalDate through,
  });
}

final class GoalRevisionConflict implements Exception {
  const GoalRevisionConflict({
    required this.id,
    required this.expected,
    required this.actual,
  });

  final EntityId id;
  final int expected;
  final int? actual;
}
