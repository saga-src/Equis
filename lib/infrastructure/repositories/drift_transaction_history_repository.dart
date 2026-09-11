import 'package:drift/drift.dart';

import '../../application/ports/ledger_repository.dart';
import '../../application/ports/transaction_history_repository.dart';
import '../../domain/ledger/transaction_search.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';

final class DriftTransactionHistoryRepository
    implements TransactionHistoryRepository {
  const DriftTransactionHistoryRepository({
    required this.database,
    required this.ledger,
  });

  final EquisDatabase database;
  final LedgerRepository ledger;

  @override
  Future<TransactionSearchPage> search(TransactionSearchFilter filter) async {
    final sql = StringBuffer();
    final values = <Object?>[];
    final descendantCategory =
        filter.categoryId != null && filter.includeDescendantCategories;
    if (descendantCategory) {
      sql.write(
        'WITH RECURSIVE descendant_categories(id) AS ('
        'SELECT ? UNION ALL '
        'SELECT c.id FROM categories c '
        'INNER JOIN descendant_categories d ON c.parent_id = d.id '
        'WHERE c.vault_id = ? AND c.deleted_at IS NULL) ',
      );
      values.addAll([filter.categoryId!.value, filter.vaultId.value]);
    }
    sql.write(
      'SELECT t.id, t.financial_date, t.created_at '
      'FROM transactions t '
      'LEFT JOIN counterparties cp ON cp.id = t.counterparty_id '
      'WHERE t.vault_id = ? AND t.deleted_at IS NULL',
    );
    values.add(filter.vaultId.value);

    final merchant = _containsPattern(filter.merchantQuery);
    if (merchant != null) {
      sql.write(
        " AND (t.title LIKE ? ESCAPE '\\' COLLATE NOCASE "
        "OR cp.name LIKE ? ESCAPE '\\' COLLATE NOCASE)",
      );
      values.addAll([merchant, merchant]);
    }
    final notes = _containsPattern(filter.notesQuery);
    if (notes != null) {
      sql.write(" AND COALESCE(t.notes, '') LIKE ? ESCAPE '\\' COLLATE NOCASE");
      values.add(notes);
    }
    _appendAmount(sql, values, filter);
    if (filter.fromDate != null) {
      sql.write(' AND t.financial_date >= ?');
      values.add(filter.fromDate.toString());
    }
    if (filter.toDate != null) {
      sql.write(' AND t.financial_date <= ?');
      values.add(filter.toDate.toString());
    }
    if (filter.accountId != null) {
      sql.write(
        ' AND EXISTS (SELECT 1 FROM account_movements am '
        'INNER JOIN account_pockets ap ON ap.id = am.account_pocket_id '
        'WHERE am.transaction_id = t.id AND ap.account_id = ?)',
      );
      values.add(filter.accountId!.value);
    }
    if (filter.categoryId != null) {
      sql.write(
        ' AND EXISTS (SELECT 1 FROM transaction_splits ts '
        'WHERE ts.transaction_id = t.id AND ts.category_id ',
      );
      if (descendantCategory) {
        sql.write('IN (SELECT id FROM descendant_categories))');
      } else {
        sql.write('= ?)');
        values.add(filter.categoryId!.value);
      }
    }
    if (filter.withoutTags) {
      sql.write(
        ' AND NOT EXISTS (SELECT 1 FROM transaction_tags tt WHERE tt.transaction_id = t.id)',
      );
    }
    if (filter.reportingExpensesOnly) {
      sql.write(
        " AND t.status != 'cancelled' AND NOT (t.status = 'pending' AND t.recurring_rule_id IS NOT NULL)"
        " AND t.transaction_type IN ('expense', 'credit_card_purchase', 'fee', 'refund')"
        ' AND EXISTS (SELECT 1 FROM transaction_splits ts WHERE ts.transaction_id = t.id)',
      );
    }
    if (filter.tagId != null) {
      sql.write(
        ' AND EXISTS (SELECT 1 FROM transaction_tags tt '
        'WHERE tt.transaction_id = t.id AND tt.tag_id = ?)',
      );
      values.add(filter.tagId!.value);
    }
    if (filter.currency != null) {
      sql.write(
        ' AND EXISTS (SELECT 1 FROM account_movements cm '
        'INNER JOIN account_pockets cpocket ON cpocket.id = cm.account_pocket_id '
        'WHERE cm.transaction_id = t.id AND cpocket.currency_code = ?)',
      );
      values.add(filter.currency!.value);
    }
    _appendSet(
      sql,
      values,
      't.transaction_type',
      filter.types.map((value) => value.stored),
    );
    _appendSet(
      sql,
      values,
      't.status',
      filter.statuses.map((value) => value.name),
    );
    final cursor = filter.cursor;
    if (cursor != null) {
      sql.write(
        ' AND (t.financial_date < ? '
        'OR (t.financial_date = ? AND t.created_at < ?) '
        'OR (t.financial_date = ? AND t.created_at = ? AND t.id < ?))',
      );
      values.addAll([
        cursor.financialDate.toString(),
        cursor.financialDate.toString(),
        cursor.createdAt.epochMicroseconds,
        cursor.financialDate.toString(),
        cursor.createdAt.epochMicroseconds,
        cursor.id.value,
      ]);
    }
    sql.write(
      ' ORDER BY t.financial_date DESC, t.created_at DESC, t.id DESC LIMIT ?',
    );
    values.add(filter.pageSize + 1);

    final roots = await database
        .customSelect(
          sql.toString(),
          variables: values.map(Variable<Object>.new).toList(growable: false),
          readsFrom: {
            database.transactions,
            database.counterparties,
            database.categories,
            database.accountMovements,
            database.accountPockets,
            database.transactionSplits,
            database.transactionTags,
          },
        )
        .get();
    final hasMore = roots.length > filter.pageSize;
    final visible = roots.take(filter.pageSize).toList(growable: false);
    final items = <LedgerTransaction>[];
    for (final root in visible) {
      final item = await ledger.find(EntityId.parse(root.read<String>('id')));
      if (item != null) items.add(item);
    }
    final last = visible.isEmpty ? null : visible.last;
    return TransactionSearchPage(
      items: items,
      hasMore: hasMore,
      nextCursor: last == null
          ? null
          : TransactionSearchCursor(
              financialDate: LocalDate.parse(
                last.read<String>('financial_date'),
              ),
              createdAt: UtcInstant.fromEpochMicroseconds(
                last.read<int>('created_at'),
              ),
              id: EntityId.parse(last.read<String>('id')),
            ),
    );
  }
}

void _appendAmount(
  StringBuffer sql,
  List<Object?> values,
  TransactionSearchFilter filter,
) {
  final minimum = filter.minimumAmountMinor;
  final maximum = filter.maximumAmountMinor;
  if (minimum == null && maximum == null) return;
  sql.write(
    ' AND EXISTS (SELECT 1 FROM account_movements amount_movement '
    'WHERE amount_movement.transaction_id = t.id AND ',
  );
  if (minimum != null && maximum != null) {
    sql.write(
      '((amount_movement.amount_minor BETWEEN ? AND ?) OR '
      '(amount_movement.amount_minor BETWEEN ? AND ?)))',
    );
    values.addAll([minimum, maximum, -maximum, -minimum]);
  } else if (minimum != null) {
    sql.write(
      '(amount_movement.amount_minor >= ? OR amount_movement.amount_minor <= ?))',
    );
    values.addAll([minimum, -minimum]);
  } else {
    sql.write('amount_movement.amount_minor BETWEEN ? AND ?)');
    values.addAll([-maximum!, maximum]);
  }
}

void _appendSet(
  StringBuffer sql,
  List<Object?> values,
  String column,
  Iterable<String> rawValues,
) {
  final selected = rawValues.toList(growable: false);
  if (selected.isEmpty) return;
  sql.write(' AND $column IN (${List.filled(selected.length, '?').join(',')})');
  values.addAll(selected);
}

String? _containsPattern(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}
