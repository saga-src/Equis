import 'package:drift/drift.dart';

import '../database/equis_database.dart';

final class TransactionAggregateSnapshot {
  TransactionAggregateSnapshot({
    required Map<String, Object?> transaction,
    required List<Map<String, Object?>> movements,
    required List<Map<String, Object?>> splits,
    required List<Map<String, Object?>> tags,
    required List<Map<String, Object?>> fxConversions,
    required List<Map<String, Object?>> investmentEvents,
    required List<Map<String, Object?>> lotDisposals,
  }) : transaction = Map.unmodifiable(transaction),
       movements = List.unmodifiable(
         movements.map(Map<String, Object?>.unmodifiable),
       ),
       splits = List.unmodifiable(
         splits.map(Map<String, Object?>.unmodifiable),
       ),
       tags = List.unmodifiable(tags.map(Map<String, Object?>.unmodifiable)),
       fxConversions = List.unmodifiable(
         fxConversions.map(Map<String, Object?>.unmodifiable),
       ),
       investmentEvents = List.unmodifiable(
         investmentEvents.map(Map<String, Object?>.unmodifiable),
       ),
       lotDisposals = List.unmodifiable(
         lotDisposals.map(Map<String, Object?>.unmodifiable),
       );

  final Map<String, Object?> transaction;
  final List<Map<String, Object?>> movements;
  final List<Map<String, Object?>> splits;
  final List<Map<String, Object?>> tags;
  final List<Map<String, Object?>> fxConversions;
  final List<Map<String, Object?>> investmentEvents;
  final List<Map<String, Object?>> lotDisposals;
}

final class TransactionAggregateLoader {
  const TransactionAggregateLoader(this.database);
  final EquisDatabase database;

  Future<TransactionAggregateSnapshot?> load(
    String transactionId,
  ) => database.transaction(() async {
    final root = await _rows('SELECT * FROM transactions WHERE id = ?', [
      transactionId,
    ]);
    if (root.isEmpty) return null;
    final events = await _rows(
      'SELECT * FROM investment_events WHERE transaction_id = ? ORDER BY id',
      [transactionId],
    );
    final eventIds = events
        .map((row) => row['id']! as String)
        .toList(growable: false);
    final disposals = eventIds.isEmpty
        ? const <Map<String, Object?>>[]
        : await _rows(
            'SELECT * FROM investment_lot_disposals WHERE disposal_event_id IN (${List.filled(eventIds.length, '?').join(',')}) ORDER BY id',
            eventIds,
          );
    return TransactionAggregateSnapshot(
      transaction: root.single,
      movements: await _rows(
        'SELECT * FROM account_movements WHERE transaction_id = ? ORDER BY sort_order, id',
        [transactionId],
      ),
      splits: await _rows(
        'SELECT * FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order, id',
        [transactionId],
      ),
      tags: await _rows(
        'SELECT * FROM transaction_tags WHERE transaction_id = ? ORDER BY tag_id',
        [transactionId],
      ),
      fxConversions: await _rows(
        'SELECT * FROM fx_conversions WHERE transaction_id = ? ORDER BY id',
        [transactionId],
      ),
      investmentEvents: events,
      lotDisposals: disposals,
    );
  });

  Future<List<Map<String, Object?>>> _rows(String sql, List<Object> values) =>
      database
          .customSelect(
            sql,
            variables: values
                .map((value) => Variable<Object>(value))
                .toList(growable: false),
          )
          .get()
          .then(
            (rows) => rows
                .map((row) => Map<String, Object?>.from(row.data))
                .toList(growable: false),
          );
}
