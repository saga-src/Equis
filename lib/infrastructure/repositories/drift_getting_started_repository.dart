import 'package:drift/drift.dart';
import '../../application/services/getting_started_service.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';

final class DriftGettingStartedRepository implements GettingStartedRepository {
  const DriftGettingStartedRepository(this.database);
  final EquisDatabase database;
  @override
  Future<GettingStartedFacts> facts(
    EntityId vaultId,
  ) => database.transaction(() async {
    final row = await database
        .customSelect(
          'SELECT '
          'EXISTS (SELECT 1 FROM accounts WHERE vault_id = ?1 AND deleted_at IS NULL) AS has_account, '
          "EXISTS (SELECT 1 FROM transactions WHERE vault_id = ?1 AND deleted_at IS NULL AND status != 'cancelled' "
          "AND NOT (status = 'pending' AND recurring_rule_id IS NOT NULL)) AS has_transaction, "
          'EXISTS (SELECT 1 FROM budgets WHERE vault_id = ?1 AND deleted_at IS NULL) AS has_budget',
          variables: [Variable(vaultId.value)],
          readsFrom: {
            database.accounts,
            database.transactions,
            database.budgets,
          },
        )
        .getSingle();
    return GettingStartedFacts(
      hasAccount: row.read<int>('has_account') == 1,
      hasTransaction: row.read<int>('has_transaction') == 1,
      hasBudget: row.read<int>('has_budget') == 1,
    );
  });
}
