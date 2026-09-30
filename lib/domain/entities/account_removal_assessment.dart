import '../shared/currency.dart';
import '../shared/uuid_v7.dart';
import 'account_aggregate.dart';

enum AccountRemovalDisposition { blocked, archive, delete }

enum AccountRemovalBlocker {
  pocketBalance,
  openStatement,
  scheduledInstallment,
  activeRecurrence,
  pendingTransaction,
  activeGoal,
  enabledBudget,
}

enum AccountReferenceKind {
  movements,
  statements,
  installmentPlans,
  recurrenceTemplates,
  transactions,
  goals,
  budgets,
  attachments,
}

final class AccountPocketBalance {
  const AccountPocketBalance({
    required this.pocketId,
    required this.currency,
    required this.minorUnits,
  });

  final EntityId pocketId;
  final CurrencyCode currency;
  final int minorUnits;
}

final class AccountRemovalAssessment {
  AccountRemovalAssessment({
    required this.aggregate,
    required List<AccountPocketBalance> balances,
    required Set<AccountRemovalBlocker> blockers,
    required Map<AccountReferenceKind, int> references,
  }) : balances = List.unmodifiable(balances),
       blockers = Set.unmodifiable(blockers),
       references = Map.unmodifiable(references);

  final AccountAggregate aggregate;
  final List<AccountPocketBalance> balances;
  final Set<AccountRemovalBlocker> blockers;
  final Map<AccountReferenceKind, int> references;

  bool get hasReferences => references.values.any((count) => count > 0);

  AccountRemovalDisposition get disposition => blockers.isNotEmpty
      ? AccountRemovalDisposition.blocked
      : hasReferences
      ? AccountRemovalDisposition.archive
      : AccountRemovalDisposition.delete;
}

final class AccountLifecycleResult {
  const AccountLifecycleResult({
    required this.aggregate,
    required this.assessment,
  });

  final AccountAggregate aggregate;
  final AccountRemovalAssessment assessment;
  AccountRemovalDisposition get disposition => assessment.disposition;
}

final class AccountRemovalBlocked implements Exception {
  const AccountRemovalBlocked(this.assessment);
  final AccountRemovalAssessment assessment;
}

final class AccountLifecycleConflict implements Exception {
  const AccountLifecycleConflict();
}
