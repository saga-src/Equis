import 'package:drift/drift.dart';

import '../../core/serialization/canonical_json.dart';
import '../persistence/database/equis_database.dart';

final class VaultLogicalSnapshot {
  VaultLogicalSnapshot({
    this.portableKeys,
    this.vaultIdentity,
    required this.schemaVersion,
    required this.createdAtMicros,
    required Map<String, List<Map<String, Object?>>> tables,
  }) : tables = Map<String, List<Map<String, Object?>>>.unmodifiable({
         for (final entry in tables.entries)
           entry.key: List<Map<String, Object?>>.unmodifiable(
             entry.value.map((row) => Map<String, Object?>.unmodifiable(row)),
           ),
       });

  static const format = 'equis-logical-vault';
  static const formatVersion = 1;

  final Object? portableKeys;
  final Map<String, Object?>? vaultIdentity;
  final int schemaVersion;
  final int createdAtMicros;
  final Map<String, List<Map<String, Object?>>> tables;

  Map<String, Object?> toJson() => {
    'created_at_micros': createdAtMicros,
    'format': format,
    'format_version': formatVersion,
    'schema_version': schemaVersion,
    'tables': tables,
    if (portableKeys != null) 'portable_keys': portableKeys,
    if (vaultIdentity != null) 'vault_identity': vaultIdentity,
  };

  List<int> encode() => CanonicalJson.encodeUtf8(toJson());

  factory VaultLogicalSnapshot.fromJson(Map<String, Object?> json) {
    if (json['format'] != format ||
        json['format_version'] != formatVersion ||
        json['schema_version'] is! int ||
        json['created_at_micros'] is! int ||
        json['tables'] is! Map) {
      throw const VaultSnapshotFormatException();
    }
    final rawTables = json['tables']! as Map;
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in rawTables.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const VaultSnapshotFormatException();
      }
      final rows = <Map<String, Object?>>[];
      for (final rawRow in entry.value! as List) {
        if (rawRow is! Map) throw const VaultSnapshotFormatException();
        final row = <String, Object?>{};
        for (final field in rawRow.entries) {
          if (field.key is! String || !_isJsonScalar(field.value)) {
            throw const VaultSnapshotFormatException();
          }
          row[field.key! as String] = field.value;
        }
        rows.add(row);
      }
      tables[entry.key! as String] = rows;
    }
    if (!tables.keys.toSet().containsAll(_tableOrder)) {
      throw const VaultSnapshotFormatException();
    }
    return VaultLogicalSnapshot(
      portableKeys: json['portable_keys'],
      vaultIdentity: json['vault_identity'] == null
          ? null
          : Map<String, Object?>.from(json['vault_identity']! as Map),
      schemaVersion: json['schema_version']! as int,
      createdAtMicros: json['created_at_micros']! as int,
      tables: tables,
    );
  }
}

final class VaultLogicalSnapshotStore {
  const VaultLogicalSnapshotStore(this.database);

  final EquisDatabase database;

  Future<VaultLogicalSnapshot> capture(
    String vaultId, {
    int? createdAtMicros,
  }) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _tableOrder) {
      final query = _captureSql(table);
      final rows = await database
          .customSelect(
            query.sql,
            variables: query.usesVault ? [Variable(vaultId)] : const [],
          )
          .get();
      tables[table] = [for (final row in rows) _portableRow(table, row.data)];
    }
    final vaultRows = tables['vaults']!;
    if (vaultRows.length != 1 || vaultRows.single['id'] != vaultId) {
      throw const VaultSnapshotSourceNotFound();
    }
    return VaultLogicalSnapshot(
      schemaVersion: database.schemaVersion,
      createdAtMicros:
          createdAtMicros ?? DateTime.now().toUtc().microsecondsSinceEpoch,
      tables: tables,
    );
  }

  Future<void> restore(
    VaultLogicalSnapshot snapshot, {
    Map<String, String> attachmentLocalPaths = const {},
  }) async {
    if (snapshot.schemaVersion > database.schemaVersion) {
      throw VaultSnapshotIncompatibleVersion(
        backup: snapshot.schemaVersion,
        supported: database.schemaVersion,
      );
    }
    final vaultRows = snapshot.tables['vaults'];
    if (vaultRows == null || vaultRows.length != 1) {
      throw const VaultSnapshotFormatException();
    }
    await database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys = ON');
      final existing = await database
          .customSelect('SELECT COUNT(*) AS count FROM vaults')
          .getSingle();
      if (existing.read<int>('count') != 0) {
        throw const VaultRestoreRequiresCleanProfile();
      }
      for (final table in _tableOrder) {
        final rows = snapshot.tables[table];
        if (rows == null) throw const VaultSnapshotFormatException();
        final actualColumns = await _columns(table);
        for (final sourceRow in rows) {
          final row = _restoreRow(table, sourceRow, attachmentLocalPaths);
          if (row.isEmpty || !actualColumns.containsAll(row.keys)) {
            throw const VaultSnapshotFormatException();
          }
          final columns = row.keys.toList(growable: false);
          final placeholders = List.filled(columns.length, '?').join(', ');
          final verb = table == 'currencies' ? 'INSERT OR IGNORE' : 'INSERT';
          await database.customStatement(
            '$verb INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
            [for (final column in columns) row[column]],
          );
        }
      }
    });
  }

  Future<Set<String>> _columns(String table) async {
    final rows = await database.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }
}

Map<String, Object?> _portableRow(String table, Map<String, Object?> source) {
  final row = Map<String, Object?>.from(source);
  if (table == 'attachments') {
    row['local_path'] = null;
    row['upload_state'] = 'local';
  }
  for (final value in row.values) {
    if (!_isJsonScalar(value)) throw const VaultSnapshotFormatException();
  }
  return row;
}

Map<String, Object?> _restoreRow(
  String table,
  Map<String, Object?> source,
  Map<String, String> attachmentLocalPaths,
) {
  final row = Map<String, Object?>.from(source);
  if (table == 'attachments') {
    final id = row['id'];
    row['local_path'] = id is String ? attachmentLocalPaths[id] : null;
    row['upload_state'] = 'local';
  }
  return row;
}

bool _isJsonScalar(Object? value) =>
    value == null || value is String || value is num || value is bool;

({String sql, bool usesVault}) _captureSql(String table) {
  final filter = _filters[table];
  if (filter == null) throw const VaultSnapshotFormatException();
  return (
    sql:
        'SELECT * FROM $table${filter.isEmpty ? '' : ' WHERE $filter'} '
        'ORDER BY 1',
    usesVault: filter.contains('?'),
  );
}

const _tableOrder = <String>[
  'currencies',
  'vaults',
  'accounts',
  'account_pockets',
  'categories',
  'tags',
  'counterparties',
  'counterparty_aliases',
  'transactions',
  'account_movements',
  'transaction_splits',
  'transaction_tags',
  'fx_conversions',
  'recurring_rules',
  'recurring_templates',
  'recurring_template_movements',
  'recurring_template_splits',
  'credit_card_profiles',
  'credit_card_limits',
  'credit_card_statements',
  'installment_plans',
  'installments',
  'budgets',
  'budget_categories',
  'budget_accounts',
  'budget_tags',
  'goals',
  'goal_accounts',
  'goal_contributions',
  'assets',
  'asset_valuations',
  'investment_instruments',
  'investment_events',
  'investment_lots',
  'investment_lot_disposals',
  'manual_fx_rates',
  'manual_market_prices',
  'attachments',
  'attachment_links',
  'vault_preferences',
];

const _filters = <String, String>{
  'currencies': '',
  'vaults': 'id = ?',
  'accounts': 'vault_id = ?',
  'account_pockets':
      'account_id IN (SELECT id FROM accounts WHERE vault_id = ?)',
  'categories': 'vault_id = ?',
  'tags': 'vault_id = ?',
  'counterparties': 'vault_id = ?',
  'counterparty_aliases':
      'counterparty_id IN (SELECT id FROM counterparties WHERE vault_id = ?)',
  'transactions': 'vault_id = ?',
  'account_movements':
      'transaction_id IN (SELECT id FROM transactions WHERE vault_id = ?)',
  'transaction_splits':
      'transaction_id IN (SELECT id FROM transactions WHERE vault_id = ?)',
  'transaction_tags':
      'transaction_id IN (SELECT id FROM transactions WHERE vault_id = ?)',
  'fx_conversions':
      'transaction_id IN (SELECT id FROM transactions WHERE vault_id = ?)',
  'recurring_rules': 'vault_id = ?',
  'recurring_templates':
      'recurring_rule_id IN (SELECT id FROM recurring_rules WHERE vault_id = ?)',
  'recurring_template_movements':
      'recurring_rule_id IN (SELECT id FROM recurring_rules WHERE vault_id = ?)',
  'recurring_template_splits':
      'recurring_rule_id IN (SELECT id FROM recurring_rules WHERE vault_id = ?)',
  'credit_card_profiles':
      'account_id IN (SELECT id FROM accounts WHERE vault_id = ?)',
  'credit_card_limits':
      'account_pocket_id IN (SELECT pocket.id FROM account_pockets pocket '
      'INNER JOIN accounts account ON account.id = pocket.account_id '
      'WHERE account.vault_id = ?)',
  'credit_card_statements': 'vault_id = ?',
  'installment_plans': 'vault_id = ?',
  'installments':
      'installment_plan_id IN (SELECT id FROM installment_plans WHERE vault_id = ?)',
  'budgets': 'vault_id = ?',
  'budget_categories':
      'budget_id IN (SELECT id FROM budgets WHERE vault_id = ?)',
  'budget_accounts': 'budget_id IN (SELECT id FROM budgets WHERE vault_id = ?)',
  'budget_tags': 'budget_id IN (SELECT id FROM budgets WHERE vault_id = ?)',
  'goals': 'vault_id = ?',
  'goal_accounts': 'goal_id IN (SELECT id FROM goals WHERE vault_id = ?)',
  'goal_contributions': 'goal_id IN (SELECT id FROM goals WHERE vault_id = ?)',
  'assets': 'vault_id = ?',
  'asset_valuations': 'asset_id IN (SELECT id FROM assets WHERE vault_id = ?)',
  'investment_instruments': 'vault_id = ?',
  'investment_events':
      'instrument_id IN (SELECT id FROM investment_instruments WHERE vault_id = ?)',
  'investment_lots':
      'instrument_id IN (SELECT id FROM investment_instruments WHERE vault_id = ?)',
  'investment_lot_disposals':
      'lot_id IN (SELECT lot.id FROM investment_lots lot '
      'INNER JOIN investment_instruments instrument '
      'ON instrument.id = lot.instrument_id WHERE instrument.vault_id = ?)',
  'manual_fx_rates': 'vault_id = ?',
  'manual_market_prices': 'vault_id = ?',
  'attachments': 'vault_id = ?',
  'attachment_links':
      'attachment_id IN (SELECT id FROM attachments WHERE vault_id = ?)',
  'vault_preferences': 'vault_id = ?',
};

final class VaultSnapshotFormatException implements Exception {
  const VaultSnapshotFormatException();
}

final class VaultSnapshotSourceNotFound implements Exception {
  const VaultSnapshotSourceNotFound();
}

final class VaultRestoreRequiresCleanProfile implements Exception {
  const VaultRestoreRequiresCleanProfile();
}

final class VaultSnapshotIncompatibleVersion implements Exception {
  const VaultSnapshotIncompatibleVersion({
    required this.backup,
    required this.supported,
  });

  final int backup;
  final int supported;
}
