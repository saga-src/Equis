import 'dart:convert';
import 'dart:io';

import 'vault_logical_snapshot_store.dart';

final class VaultPlaintextExporter {
  const VaultPlaintextExporter(this.snapshots);

  static const privacyWarningPtBr =
      'A exportação não é criptografada. Ela pode conter valores, descrições, '
      'contas e outros dados financeiros privados. Guarde-a em local seguro.';

  final VaultLogicalSnapshotStore snapshots;

  Future<PlaintextExportResult> exportJson({
    required String vaultId,
    required File destination,
  }) async {
    final snapshot = await snapshots.capture(vaultId);
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );
    await _writeNew(destination, bytes);
    return PlaintextExportResult(
      file: destination,
      format: PlaintextExportFormat.json,
      recordCount: snapshot.tables.values.fold(
        0,
        (count, rows) => count + rows.length,
      ),
    );
  }

  Future<PlaintextExportResult> exportTransactionsCsv({
    required String vaultId,
    required File destination,
  }) async {
    final snapshot = await snapshots.capture(vaultId);
    final transactions = snapshot.tables['transactions']!;
    const columns = [
      'transaction_id',
      'transaction_type',
      'status',
      'financial_date',
      'occurred_at_micros',
      'title',
      'description',
      'notes',
      'counterparty_id',
      'payment_method',
      'source',
      'recurring_rule_id',
      'recurrence_date',
      'reversal_of_id',
      'revision',
      'movements_json',
      'splits_json',
      'tag_ids_json',
      'fx_conversions_json',
    ];
    final buffer = StringBuffer()..writeln(columns.map(_csvCell).join(','));
    for (final transaction in transactions) {
      final id = transaction['id'];
      final movements = _children(
        snapshot,
        'account_movements',
        'transaction_id',
        id,
      );
      final splits = _children(
        snapshot,
        'transaction_splits',
        'transaction_id',
        id,
      );
      final tags = _children(
        snapshot,
        'transaction_tags',
        'transaction_id',
        id,
      ).map((row) => row['tag_id']).toList(growable: false);
      final conversions = _children(
        snapshot,
        'fx_conversions',
        'transaction_id',
        id,
      );
      final values = <Object?>[
        id,
        transaction['transaction_type'],
        transaction['status'],
        transaction['financial_date'],
        transaction['occurred_at'],
        transaction['title'],
        transaction['description'],
        transaction['notes'],
        transaction['counterparty_id'],
        transaction['payment_method'],
        transaction['source'],
        transaction['recurring_rule_id'],
        transaction['recurrence_date'],
        transaction['reversal_of_id'],
        transaction['revision'],
        jsonEncode(movements),
        jsonEncode(splits),
        jsonEncode(tags),
        jsonEncode(conversions),
      ];
      buffer.writeln(values.map(_csvCell).join(','));
    }
    await _writeNew(destination, utf8.encode('\ufeff$buffer'));
    return PlaintextExportResult(
      file: destination,
      format: PlaintextExportFormat.csv,
      recordCount: transactions.length,
    );
  }
}

List<Map<String, Object?>> _children(
  VaultLogicalSnapshot snapshot,
  String table,
  String parentColumn,
  Object? parentId,
) => [
  for (final row in snapshot.tables[table]!)
    if (row[parentColumn] == parentId) row,
];

String _csvCell(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  if (!text.contains(RegExp('[,"\\r\\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

Future<void> _writeNew(File destination, List<int> bytes) async {
  if (await destination.exists()) throw const ExportFileAlreadyExists();
  await destination.parent.create(recursive: true);
  final temporary = File('${destination.path}.part');
  if (await temporary.exists()) await temporary.delete();
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

enum PlaintextExportFormat { json, csv }

final class PlaintextExportResult {
  const PlaintextExportResult({
    required this.file,
    required this.format,
    required this.recordCount,
  });

  final File file;
  final PlaintextExportFormat format;
  final int recordCount;
}

final class ExportFileAlreadyExists implements Exception {
  const ExportFileAlreadyExists();
}
