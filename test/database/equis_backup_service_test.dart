import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:equis/infrastructure/files/encrypted_attachment_file_codec.dart';
import 'package:equis/infrastructure/files/equis_file_layout.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/portability/equis_backup_service.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:equis/infrastructure/security/attachment_cipher.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/security/vault_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const account = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  const pocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
  const transaction = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
  const attachment = '018f47c2-9b72-7cc1-8b83-5d0fead0a005';
  const password = 'correct horse battery staple';
  final receipt = utf8.encode('private receipt: R\$ 25,90');
  late EquisDatabase sourceDatabase;
  late EquisDatabase targetDatabase;
  late Directory temporary;
  late EquisFileLayout sourceLayout;
  late EquisFileLayout targetLayout;
  late EncryptedAttachmentFileCodec sourceCodec;
  late EncryptedAttachmentFileCodec targetCodec;
  late EquisBackupService sourceService;
  late EquisBackupService targetService;

  setUp(() async {
    sourceDatabase = EquisDatabase(NativeDatabase.memory());
    targetDatabase = EquisDatabase(NativeDatabase.memory());
    temporary = await Directory.systemTemp.createTemp('equis-backup-');
    sourceLayout = EquisFileLayout(
      Directory('${temporary.path}${Platform.pathSeparator}source'),
    );
    targetLayout = EquisFileLayout(
      Directory('${temporary.path}${Platform.pathSeparator}target'),
    );
    await sourceLayout.ensureCreated();
    await targetLayout.ensureCreated();
    sourceCodec = EncryptedAttachmentFileCodec(
      cipher: _cipher(1),
      chunkSize: 8,
    );
    targetCodec = EncryptedAttachmentFileCodec(
      cipher: _cipher(91),
      chunkSize: 8,
    );
    sourceService = _service(
      database: sourceDatabase,
      codec: sourceCodec,
      layout: sourceLayout,
      seed: 7,
    );
    targetService = _service(
      database: targetDatabase,
      codec: targetCodec,
      layout: targetLayout,
      seed: 11,
    );
    await sourceDatabase.customStatement(
      "INSERT INTO currencies VALUES ('BRL', '986', 'currency.brl', 'R\$', 2)",
    );
    await sourceDatabase.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
      [vault],
    );
    await sourceDatabase.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Checking', 'checking', 'asset', 1, 1)",
      [account, vault],
    );
    await sourceDatabase.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'BRL', 1)",
      [pocket, account],
    );
    await sourceDatabase.customStatement(
      "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, title, created_at, updated_at) VALUES (?, ?, 'expense', '2026-08-22', 'Lunch', 1, 1)",
      [transaction, vault],
    );
    await sourceDatabase.customStatement(
      "INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor) VALUES ('018f47c2-9b72-7cc1-8b83-5d0fead0a006', ?, ?, -2590)",
      [transaction, pocket],
    );
    final stored = await sourceCodec.encryptBytes(
      clearBytes: receipt,
      destination: sourceLayout.encryptedAttachment(
        vaultId: vault,
        attachmentId: attachment,
      ),
      vaultId: vault,
      attachmentId: attachment,
    );
    await sourceDatabase.customStatement(
      "INSERT INTO attachments (id, vault_id, original_filename, mime_type, byte_size, local_path, sha256, upload_state, created_at, updated_at) VALUES (?, ?, 'receipt.txt', 'text/plain', ?, ?, ?, 'local', 1, 1)",
      [
        attachment,
        vault,
        stored.clearByteSize,
        stored.file.path,
        stored.clearSha256,
      ],
    );
    await sourceDatabase.customStatement(
      "INSERT INTO attachment_links VALUES (?, 'transaction', ?)",
      [attachment, transaction],
    );
  });

  tearDown(() async {
    await sourceDatabase.close();
    await targetDatabase.close();
    await temporary.delete(recursive: true);
  });

  test('creates, validates and restores a portable encrypted backup', () async {
    await sourceDatabase.customStatement(
      "INSERT INTO sync_activity_events VALUES (?, 'transaction', ?, 'sent', 1, 1, 1)",
      [vault, transaction],
    );
    final backup = File(
      '${temporary.path}${Platform.pathSeparator}vault.equis',
    );
    final created = await sourceService.create(
      vaultId: vault,
      password: password,
      destination: backup,
    );
    final validated = await sourceService.validate(
      source: backup,
      password: password,
    );
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    final manifest = utf8.decode(archive.find('manifest.json')!.readBytes()!);

    expect(created.attachmentCount, 1);
    expect(validated.schemaVersion, sourceDatabase.schemaVersion);
    expect(archive.find('vault.enc'), isNotNull);
    expect(archive.find('attachments/000001.enc'), isNotNull);
    expect(manifest, isNot(contains(vault)));
    expect(manifest, isNot(contains('receipt.txt')));
    expect(manifest, isNot(contains('Lunch')));

    final restored = await targetService.restore(
      source: backup,
      password: password,
    );
    expect(restored.attachmentCount, 1);
    expect(
      await targetDatabase
          .customSelect('SELECT * FROM sync_activity_events')
          .get(),
      isEmpty,
    );
    expect(
      await sourceDatabase
          .customSelect('SELECT * FROM sync_activity_events')
          .get(),
      hasLength(1),
    );
    final restoredTransaction = await targetDatabase
        .customSelect('SELECT id FROM transactions')
        .getSingle();
    expect(restoredTransaction.read<String>('id'), transaction);
    final restoredAttachment = await targetDatabase
        .customSelect('SELECT id, local_path FROM attachments')
        .getSingle();
    expect(restoredAttachment.read<String>('id'), attachment);
    final clear = await targetCodec.decryptBytes(
      source: File(restoredAttachment.read<String>('local_path')),
      vaultId: vault,
      attachmentId: attachment,
    );
    expect(clear, receipt);

    await expectLater(
      targetService.restore(source: backup, password: password),
      throwsA(anything),
    );
    expect(
      (await targetDatabase.customSelect('SELECT id FROM transactions').get()),
      hasLength(1),
    );
  });

  test(
    'migrates legacy backup once and restores a single identity on two devices',
    () async {
      final legacy = File('${temporary.path}/legacy.equis');
      final migrated = File('${temporary.path}/migrated.equis');
      await sourceService.create(
        vaultId: vault,
        password: password,
        destination: legacy,
      );
      final originalBytes = await legacy.readAsBytes();
      await sourceService.migrate(
        source: legacy,
        password: password,
        destination: migrated,
        newPassword: password,
      );
      expect(await legacy.readAsBytes(), originalBytes);
      final identity = await sourceService.inspectIdentity(
        source: migrated,
        password: password,
      );
      expect(identity.vaultId, isNot(vault));
      expect(identity.ownerId, isNull);
      final archive = ZipDecoder().decodeBytes(await migrated.readAsBytes());
      final manifest =
          jsonDecode(utf8.decode(archive.find('manifest.json')!.readBytes()!))
              as Map;
      expect(manifest['format_version'], 2);
      expect(manifest.toString(), isNot(contains('master_key')));
      final keys = VaultKeyManager(
        store: _Store(base64UrlEncode(List.filled(32, 91))),
        protocolVersion: 2,
      );
      final codec = EncryptedAttachmentFileCodec(
        cipher: AttachmentCipher(keys: keys),
      );
      final service = _service(
        database: targetDatabase,
        codec: codec,
        layout: targetLayout,
        seed: 15,
      );
      await expectLater(
        service.restore(source: legacy, password: password),
        throwsA(isA<LegacyBackupNeedsMigration>()),
      );
      await service.restore(source: migrated, password: password);
      expect(
        await (await keys.requireVault(identity.vaultId)).fingerprint(),
        await identity.fingerprint(),
      );
      final row = await targetDatabase
          .customSelect('SELECT id,vault_id FROM transactions')
          .getSingle();
      expect(row.read<String>('id'), transaction);
      expect(row.read<String>('vault_id'), identity.vaultId);
      expect(
        await codec.decryptBytes(
          source: targetLayout.encryptedAttachment(
            vaultId: identity.vaultId,
            attachmentId: attachment,
          ),
          vaultId: identity.vaultId,
          attachmentId: attachment,
        ),
        receipt,
      );
      final another = VaultKeyManager(
        store: _Store(base64UrlEncode(List.filled(32, 123))),
        protocolVersion: 2,
      );
      await another.installVaultIdentity(
        await service.inspectIdentity(source: migrated, password: password),
      );
      final record = SyncRecordIdentity(
        vaultId: identity.vaultId,
        recordId: transaction,
        entityType: 'transaction',
        revision: 1,
      );
      final encrypted = await SyncPayloadCipher(
        keys: keys,
      ).encrypt(identity: record, payload: {'check': true});
      expect(
        await SyncPayloadCipher(
          keys: another,
        ).decrypt(identity: record, envelope: encrypted),
        {'check': true},
      );
      await expectLater(
        sourceService.migrate(
          source: migrated,
          password: password,
          destination: File('${temporary.path}/again.equis'),
          newPassword: password,
        ),
        throwsA(isA<BackupAlreadyMigrated>()),
      );
    },
  );

  test(
    'rejects wrong passwords and authenticated ciphertext tampering',
    () async {
      final backup = File(
        '${temporary.path}${Platform.pathSeparator}vault.equis',
      );
      await sourceService.create(
        vaultId: vault,
        password: password,
        destination: backup,
      );
      await expectLater(
        sourceService.validate(
          source: backup,
          password: 'wrong password value',
        ),
        throwsA(isA<EquisBackupAuthenticationException>()),
      );

      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      final vaultFile = archive.find('vault.enc')!;
      final changed = vaultFile.readBytes()!..[0] ^= 1;
      archive.add(ArchiveFile.bytes('vault.enc', changed));
      final tampered = File(
        '${temporary.path}${Platform.pathSeparator}tampered.equis',
      );
      await tampered.writeAsBytes(ZipEncoder().encodeBytes(archive));
      await expectLater(
        sourceService.validate(source: tampered, password: password),
        throwsA(isA<EquisBackupFormatException>()),
      );
    },
  );

  test('rejects a partial archive without changing the target', () async {
    final backup = File(
      '${temporary.path}${Platform.pathSeparator}vault.equis',
    );
    await sourceService.create(
      vaultId: vault,
      password: password,
      destination: backup,
    );
    final complete = await backup.readAsBytes();
    final partial = File(
      '${temporary.path}${Platform.pathSeparator}partial.equis',
    );
    await partial.writeAsBytes(complete.take(complete.length ~/ 2).toList());

    await expectLater(
      targetService.restore(source: partial, password: password),
      throwsA(isA<EquisBackupFormatException>()),
    );
    expect(
      await targetDatabase.customSelect('SELECT id FROM vaults').get(),
      isEmpty,
    );
    expect(
      await targetLayout.root
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList(),
      isEmpty,
    );
  });
}

EquisBackupService _service({
  required EquisDatabase database,
  required EncryptedAttachmentFileCodec codec,
  required EquisFileLayout layout,
  required int seed,
}) => EquisBackupService(
  snapshots: VaultLogicalSnapshotStore(database),
  attachments: codec,
  layout: layout,
  parameters: const RecoveryKdfParameters(memoryKiB: 32, iterations: 1),
  random: Random(seed),
);

AttachmentCipher _cipher(int seed) => AttachmentCipher(
  keys: VaultKeyManager(
    store: _Store(base64UrlEncode(List<int>.generate(32, (i) => i + seed))),
  ),
);

final class _Store implements SecureStringStore {
  _Store(String master) : values = {'equis.vault_master_key.v1': master};

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
