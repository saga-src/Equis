import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
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
  const instrument = '018f47c2-9b72-7cc1-8b83-5d0fead0a007';
  const event = '018f47c2-9b72-7cc1-8b83-5d0fead0a008';
  const lot = '018f47c2-9b72-7cc1-8b83-5d0fead0a009';
  const manualValue = '018f47c2-9b72-7cc1-8b83-5d0fead0a00a';
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

  test('round trips lot terms and manual values without sync metadata', () async {
    const fingerprint =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    await source.customStatement(
      "INSERT INTO investment_instruments (id, vault_id, name, asset_class, currency_code, created_at, updated_at) VALUES (?, ?, 'CDB', 'fixed_income', 'BRL', 1, 1)",
      [instrument, vault],
    );
    await source.customStatement(
      "INSERT INTO investment_events (id, transaction_id, instrument_id, event_type) VALUES (?, ?, ?, 'buy')",
      [event, transaction, instrument],
    );
    await source.customStatement(
      "INSERT INTO investment_lots (id, acquisition_event_id, instrument_id, acquired_on, original_quantity, cost_basis_minor, cost_currency_code) VALUES (?, ?, ?, '2026-08-22', '1', 10000, 'BRL')",
      [lot, event, instrument],
    );
    await source.customStatement(
      "INSERT INTO fixed_income_contracts (lot_id, principal, currency_code, product_name, issuer_name, accrual_start, remuneration_mode, annual_rate, day_count_basis, update_rule) VALUES (?, '100', 'BRL', 'CDB', 'Issuer', '2026-08-22', 'fixedAnnual', '0.12', 365, 'annualCompound')",
      [lot],
    );
    await source.customStatement(
      "INSERT INTO fixed_income_manual_values (id, lot_id, value_date, amount_minor, currency_code, recorded_at, disposal_fingerprint) VALUES (?, ?, '2026-09-01', 10150, 'BRL', 42, ?)",
      [manualValue, lot, fingerprint],
    );

    final snapshot = await VaultLogicalSnapshotStore(source).capture(vault);
    expect(snapshot.tables['fixed_income_contracts'], hasLength(1));
    expect(snapshot.tables['fixed_income_manual_values'], hasLength(1));
    expect(
      snapshot
          .tables['fixed_income_manual_values']!
          .single['disposal_fingerprint'],
      fingerprint,
    );
    expect(snapshot.tables, isNot(contains('sync_quarantine')));
    expect(snapshot.tables, isNot(contains('economic_series_cache')));
    await VaultLogicalSnapshotStore(target).restore(snapshot);
    final contract = await target
        .customSelect(
          'SELECT principal, annual_rate FROM fixed_income_contracts WHERE lot_id = ?',
          variables: [Variable(lot)],
        )
        .getSingle();
    expect(contract.read<String>('principal'), '100');
    expect(contract.read<String>('annual_rate'), '0.12');
    final manual = await target
        .customSelect(
          'SELECT amount_minor, disposal_fingerprint FROM fixed_income_manual_values WHERE id = ?',
          variables: [Variable(manualValue)],
        )
        .getSingle();
    expect(manual.read<int>('amount_minor'), 10150);
    expect(manual.read<String>('disposal_fingerprint'), fingerprint);
    expect(
      await target.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
  });

  test('accepts missing private tables only in a v6 snapshot', () async {
    final snapshot = await VaultLogicalSnapshotStore(source).capture(vault);
    final json = Map<String, Object?>.from(snapshot.toJson())
      ..['schema_version'] = 6;
    final tables = Map<String, Object?>.from(json['tables']! as Map)
      ..remove('fixed_income_contracts')
      ..remove('fixed_income_manual_values');
    json['tables'] = tables;
    final legacy = VaultLogicalSnapshot.fromJson(json);
    expect(legacy.tables['fixed_income_contracts'], isEmpty);
    expect(legacy.tables['fixed_income_manual_values'], isEmpty);
    await VaultLogicalSnapshotStore(target).restore(legacy);
    expect(
      await target.customSelect('SELECT * FROM fixed_income_contracts').get(),
      isEmpty,
    );

    json['schema_version'] = 7;
    expect(
      () => VaultLogicalSnapshot.fromJson(json),
      throwsA(isA<VaultSnapshotFormatException>()),
    );
    json['schema_version'] = 6;
    tables.remove('investment_lots');
    expect(
      () => VaultLogicalSnapshot.fromJson(json),
      throwsA(isA<VaultSnapshotFormatException>()),
    );
  });

  test('blocks capture while a cloud envelope awaits replay', () async {
    await source.customStatement(
      "INSERT INTO sync_quarantine (event_id, vault_id, server_version, entity_type, entity_id, entity_revision, authenticated_envelope, reason, detected_at) VALUES ('other-event', 'other-vault', 1, 'transaction', 'other-transaction', 2, 'ciphertext', 'dependency', 1)",
    );
    await VaultLogicalSnapshotStore(source).capture(vault);
    await source.customStatement(
      "INSERT INTO sync_quarantine (event_id, vault_id, server_version, entity_type, entity_id, entity_revision, authenticated_envelope, reason, detected_at) VALUES ('event-1', ?, 1, 'transaction', ?, 2, 'ciphertext', 'dependency', 1)",
      [vault, transaction],
    );
    await expectLater(
      VaultLogicalSnapshotStore(source).capture(vault),
      throwsA(isA<VaultSnapshotUnresolvedSyncConflict>()),
    );
    await source.customStatement(
      "UPDATE sync_quarantine SET replay_state = 'replayed', replayed_at = 2 WHERE event_id = 'event-1'",
    );
    final snapshot = await VaultLogicalSnapshotStore(source).capture(vault);
    expect(snapshot.tables, isNot(contains('sync_quarantine')));
  });

  test('blocks capture until pending writes and conflicts are resolved', () async {
    await source.customStatement(
      "INSERT INTO sync_outbox (operation_id, vault_id, entity_type, record_id, new_revision, operation, created_at) VALUES ('other', 'other-vault', 'transaction', ?, 2, 'upsert', 1)",
      [transaction],
    );
    await VaultLogicalSnapshotStore(source).capture(vault);
    await source.customStatement(
      "INSERT INTO sync_outbox (operation_id, vault_id, entity_type, record_id, new_revision, operation, created_at) VALUES ('pending', ?, 'transaction', ?, 2, 'upsert', 1)",
      [vault, transaction],
    );
    await expectLater(
      VaultLogicalSnapshotStore(source).capture(vault),
      throwsA(isA<VaultSnapshotUnresolvedSyncConflict>()),
    );
    await source.customStatement(
      "DELETE FROM sync_outbox WHERE operation_id = 'pending'",
    );
    await source.customStatement(
      "INSERT INTO sync_conflicts (id, vault_id, entity_type, record_id, base_revision, local_revision, remote_revision, local_snapshot, remote_snapshot, detected_at) VALUES ('review', ?, 'transaction', ?, 1, 2, 2, '{}', '{}', 1)",
      [vault, transaction],
    );
    await expectLater(
      VaultLogicalSnapshotStore(source).capture(vault),
      throwsA(isA<VaultSnapshotUnresolvedSyncConflict>()),
    );
    await source.customStatement(
      "UPDATE sync_conflicts SET resolved_at = 2 WHERE id = 'review'",
    );
    final snapshot = await VaultLogicalSnapshotStore(source).capture(vault);
    expect(snapshot.tables, isNot(contains('sync_outbox')));
    expect(snapshot.tables, isNot(contains('sync_conflicts')));
  });
}
