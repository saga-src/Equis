import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:equis/infrastructure/portability/vault_plaintext_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const account = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  const pocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
  const transaction = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
  late EquisDatabase database;
  late Directory temporary;
  late VaultPlaintextExporter exporter;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    temporary = await Directory.systemTemp.createTemp('equis-export-');
    exporter = VaultPlaintextExporter(VaultLogicalSnapshotStore(database));
    await database.customStatement(
      "INSERT INTO currencies VALUES ('BRL', '986', 'currency.brl', 'R\$', 2)",
    );
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
      [vault],
    );
    await database.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Checking', 'checking', 'asset', 1, 1)",
      [account, vault],
    );
    await database.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'BRL', 1)",
      [pocket, account],
    );
    await database.customStatement(
      "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, title, notes, created_at, updated_at) VALUES (?, ?, 'expense', '2026-08-22', 'Lunch, team', 'line 1\nline 2', 1, 1)",
      [transaction, vault],
    );
    await database.customStatement(
      "INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) VALUES ('018f47c2-9b72-7cc1-8b83-5d0fead0a005', ?, ?, -2590)",
      [transaction, pocket],
    );
  });

  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test(
    'exports complete logical JSON without local-only cloud state',
    () async {
      final destination = File(
        '${temporary.path}${Platform.pathSeparator}vault.json',
      );
      final result = await exporter.exportJson(
        vaultId: vault,
        destination: destination,
      );
      final decoded = jsonDecode(await destination.readAsString()) as Map;

      expect(result.format, PlaintextExportFormat.json);
      expect(decoded['format'], VaultLogicalSnapshot.format);
      expect((decoded['tables'] as Map), isNot(contains('sync_outbox')));
      expect(
        (decoded['tables'] as Map),
        isNot(contains('vault_cloud_bindings')),
      );
    },
  );

  test(
    'exports RFC-style CSV with exact minor values and relationships',
    () async {
      final destination = File(
        '${temporary.path}${Platform.pathSeparator}transactions.csv',
      );
      final result = await exporter.exportTransactionsCsv(
        vaultId: vault,
        destination: destination,
      );
      expect((await destination.readAsBytes()).take(3), [0xef, 0xbb, 0xbf]);
      final csv = await destination.readAsString();

      expect(result.recordCount, 1);
      expect(csv, startsWith('transaction_id,'));
      expect(csv, contains(transaction));
      expect(csv, contains('-2590'));
      expect(csv, contains(pocket));
      expect(csv, contains('"Lunch, team"'));
      expect(
        VaultPlaintextExporter.privacyWarningPtBr,
        contains('não é criptografada'),
      );
    },
  );

  test('does not create plaintext files during unresolved sync replay', () async {
    await database.customStatement(
      "INSERT INTO sync_quarantine (event_id, vault_id, server_version, entity_type, entity_id, entity_revision, authenticated_envelope, reason, detected_at) VALUES ('event-1', ?, 1, 'transaction', ?, 2, 'ciphertext', 'dependency', 1)",
      [vault, transaction],
    );
    final jsonFile = File('${temporary.path}/blocked.json');
    final csvFile = File('${temporary.path}/blocked.csv');
    await expectLater(
      exporter.exportJson(vaultId: vault, destination: jsonFile),
      throwsA(isA<VaultSnapshotUnresolvedSyncConflict>()),
    );
    await expectLater(
      exporter.exportTransactionsCsv(vaultId: vault, destination: csvFile),
      throwsA(isA<VaultSnapshotUnresolvedSyncConflict>()),
    );
    expect(await jsonFile.exists(), isFalse);
    expect(await csvFile.exists(), isFalse);
  });

  test('exports local edits while sync write and review are pending', () async {
    await database.customStatement(
      "INSERT INTO sync_outbox (operation_id, vault_id, entity_type, record_id, new_revision, operation, created_at) VALUES ('pending', ?, 'transaction', ?, 2, 'upsert', 1)",
      [vault, transaction],
    );
    await database.customStatement(
      "INSERT INTO sync_conflicts (id, vault_id, entity_type, record_id, base_revision, local_revision, remote_revision, local_snapshot, remote_snapshot, detected_at) VALUES ('review', ?, 'transaction', ?, 1, 2, 2, '{}', '{}', 1)",
      [vault, transaction],
    );
    final jsonFile = File('${temporary.path}/offline.json');
    final csvFile = File('${temporary.path}/offline.csv');
    await exporter.exportJson(vaultId: vault, destination: jsonFile);
    await exporter.exportTransactionsCsv(vaultId: vault, destination: csvFile);
    final decoded = jsonDecode(await jsonFile.readAsString()) as Map;
    expect((decoded['tables'] as Map), isNot(contains('sync_outbox')));
    expect((decoded['tables'] as Map), isNot(contains('sync_conflicts')));
    expect(await csvFile.readAsString(), contains('Lunch, team'));
  });
}
