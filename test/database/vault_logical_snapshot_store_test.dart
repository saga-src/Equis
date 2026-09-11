import 'dart:convert';

import 'package:drift/native.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const account = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  const pocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
  const transaction = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
  const movement = '018f47c2-9b72-7cc1-8b83-5d0fead0a005';
  const attachment = '018f47c2-9b72-7cc1-8b83-5d0fead0a006';
  late EquisDatabase source;
  late EquisDatabase target;

  setUp(() async {
    source = EquisDatabase(NativeDatabase.memory());
    target = EquisDatabase(NativeDatabase.memory());
    await source.customStatement(
      "INSERT INTO currencies VALUES ('BRL', '986', 'currency.brl', 'R\$', 2)",
    );
    await source.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Private vault', 'BRL', 'America/Sao_Paulo', 1, 1)",
      [vault],
    );
    await source.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Checking', 'checking', 'asset', 1, 1)",
      [account, vault],
    );
    await source.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'BRL', 1)",
      [pocket, account],
    );
    await source.customStatement(
      "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, title, created_at, updated_at) VALUES (?, ?, 'expense', '2026-08-22', 'Lunch', 1, 1)",
      [transaction, vault],
    );
    await source.customStatement(
      'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) VALUES (?, ?, ?, -2590)',
      [movement, transaction, pocket],
    );
    await source.customStatement(
      "INSERT INTO attachments (id, vault_id, original_filename, mime_type, byte_size, local_path, sha256, upload_state, created_at, updated_at) VALUES (?, ?, 'receipt.pdf', 'application/pdf', 10, 'F:/secret/path', ?, 'uploaded', 1, 1)",
      [
        attachment,
        vault,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ],
    );
    await source.customStatement(
      "INSERT INTO attachment_links VALUES (?, 'transaction', ?)",
      [attachment, transaction],
    );
    await source.customStatement(
      "INSERT INTO vault_cloud_bindings VALUES (?, 'user-id', 1, 1)",
      [vault],
    );
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  test(
    'captures and reconstructs logical relationships and original minor units',
    () async {
      final snapshot = await VaultLogicalSnapshotStore(
        source,
      ).capture(vault, createdAtMicros: 42);
      final decoded = VaultLogicalSnapshot.fromJson(
        Map<String, Object?>.from(
          jsonDecode(utf8.decode(snapshot.encode())) as Map,
        ),
      );

      expect(decoded.tables, isNot(contains('vault_cloud_bindings')));
      expect(
        decoded.tables['account_movements']!.single['amount_minor'],
        -2590,
      );
      expect(decoded.tables['attachments']!.single['local_path'], isNull);
      expect(decoded.tables['attachments']!.single['upload_state'], 'local');

      await VaultLogicalSnapshotStore(target).restore(decoded);
      final restoredMovement = await target
          .customSelect('SELECT * FROM account_movements')
          .getSingle();
      expect(restoredMovement.read<String>('id'), movement);
      expect(restoredMovement.read<int>('amount_minor'), -2590);
      final restoredLink = await target
          .customSelect('SELECT * FROM attachment_links')
          .getSingle();
      expect(restoredLink.read<String>('entity_id'), transaction);
      final restoredAttachment = await target
          .customSelect('SELECT local_path, upload_state FROM attachments')
          .getSingle();
      expect(restoredAttachment.readNullable<String>('local_path'), isNull);
      expect(restoredAttachment.read<String>('upload_state'), 'local');
    },
  );

  test('refuses dirty profiles and backups from newer schemas', () async {
    final snapshot = await VaultLogicalSnapshotStore(source).capture(vault);
    await target.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('018f47c2-9b72-7cc1-8b83-5d0fead0afff', 'Existing', 'BRL', 'UTC', 1, 1)",
    );
    await expectLater(
      VaultLogicalSnapshotStore(target).restore(snapshot),
      throwsA(isA<VaultRestoreRequiresCleanProfile>()),
    );

    final newer = VaultLogicalSnapshot(
      schemaVersion: target.schemaVersion + 1,
      createdAtMicros: snapshot.createdAtMicros,
      tables: snapshot.tables,
    );
    await expectLater(
      VaultLogicalSnapshotStore(target).restore(newer),
      throwsA(isA<VaultSnapshotIncompatibleVersion>()),
    );
  });
}
