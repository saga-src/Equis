import '../database/equis_database.dart';

/// Rebuilds pocket balances exclusively from ledger source rows.
final class LedgerBalanceReader {
  const LedgerBalanceReader(this.database);
  final EquisDatabase database;

  Future<Map<String, int>> rebuildAll() async {
    final rows = await database
        .customSelect(
          'SELECT account_pocket_id, COALESCE(SUM(amount_minor), 0) AS balance_minor '
          'FROM account_movements AS movement '
          'INNER JOIN transactions AS parent ON parent.id = movement.transaction_id '
          "WHERE parent.status != 'cancelled' "
          "AND NOT (parent.status = 'pending' AND parent.recurring_rule_id IS NOT NULL) "
          'AND parent.deleted_at IS NULL '
          'GROUP BY account_pocket_id',
          readsFrom: {database.accountMovements, database.transactions},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('account_pocket_id'): row.read<int>('balance_minor'),
    };
  }
}
