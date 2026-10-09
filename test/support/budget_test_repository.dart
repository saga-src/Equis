import 'dart:async';

import 'package:equis/application/ports/budget_repository.dart';
import 'package:equis/application/ports/dashboard_repository.dart';
import 'package:equis/application/services/budget_service.dart';
import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';

// Records UI requests; persistence/timeline behavior is tested against Drift.
class BudgetTestRepository implements BudgetRepository {
  BudgetTestRepository({bool deleted = false}) {
    final now = UtcInstant.fromDateTime(DateTime.utc(2026, 7, 1));
    budget = BudgetDefinition(
      id: EntityId.generate(),
      vaultId: vault,
      name: 'Monthly plan',
      currency: CurrencyCode.brl,
      limitMinor: 100000,
      periodType: BudgetPeriodType.monthly,
      warningThresholdBps: 8000,
      scope: BudgetScope(),
      createdAt: now,
      updatedAt: now,
      deletedAt: deleted ? now : null,
    );
    configuration = BudgetMonthlyConfiguration(
      amountMinor: 100000,
      warningThresholdBps: 7550,
      scope: BudgetScope(),
    );
  }
  final vault = EntityId.generate();
  late BudgetDefinition budget;
  late BudgetMonthlyConfiguration configuration;
  bool failReads = false;
  bool failWrites = false;
  Completer<BudgetMonthlyHistory>? delayedHistory;
  BudgetMonth? editedMonth;
  BudgetMonthlyEditScope? editScope;
  BudgetMonthlyConfiguration? submitted;
  String? submittedName;
  int writes = 0;
  BudgetService get service =>
      BudgetService(repository: this, reporting: _EmptyReporting());
  BudgetMonthlyHistory get history => BudgetMonthlyHistory([
    BudgetMonthlyEntry(
      id: EntityId.generate(),
      budgetId: budget.id,
      kind: BudgetMonthlyEntryKind.standard,
      month: BudgetMonth(2026, 7),
      configuration: configuration,
    ),
  ]);
  @override
  Future<List<BudgetDefinition>> listForVault(
    EntityId vaultId, {
    bool includeDeleted = false,
  }) async {
    if (failReads) throw StateError('fixture read failure');
    return [if (budget.deletedAt == null || includeDeleted) budget];
  }

  @override
  Future<BudgetMonthlyHistory> loadMonthlyHistory(EntityId budgetId) {
    final pending = delayedHistory;
    delayedHistory = null;
    return pending?.future ?? Future.value(history);
  }

  @override
  Future<List<BudgetUsageRow>> loadUsageRows({
    required EntityId vaultId,
    required LocalDate from,
    required LocalDate through,
  }) async => [];
  @override
  Future<Map<EntityId, EntityId?>> loadCategoryParents(
    EntityId vaultId,
  ) async => {};
  @override
  Future<void> save(
    BudgetDefinition value, {
    BudgetMonthlyConfiguration? initialMonthlyConfiguration,
  }) async {
    if (failWrites) throw StateError('fixture write failure');
    writes++;
    submitted = initialMonthlyConfiguration;
    submittedName = value.name;
    budget = value;
  }

  @override
  Future<BudgetDefinition> saveMonthlyEdit({
    required EntityId budgetId,
    required EntityId vaultId,
    required int expectedRevision,
    required BudgetMonth month,
    required BudgetMonthlyConfiguration configuration,
    required BudgetMonthlyEditScope scope,
    required UtcInstant now,
    String? name,
  }) async {
    if (failWrites || budget.revision != expectedRevision) {
      throw BudgetRevisionConflict(
        id: budgetId,
        expected: expectedRevision,
        actual: budget.revision,
      );
    }
    writes++;
    editedMonth = month;
    editScope = scope;
    submitted = configuration;
    submittedName = name;
    return budget = budget.revise(name: name, at: now);
  }

  @override
  Future<BudgetDefinition?> find(EntityId id) async =>
      id == budget.id ? budget : null;
}

class _EmptyReporting implements DashboardRepository {
  @override
  void beginRead() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
