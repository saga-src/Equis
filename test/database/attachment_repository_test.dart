import 'package:drift/native.dart';
import 'package:equis/application/ports/attachment_ports.dart';
import 'package:equis/domain/attachments/attachment_models.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_attachment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const otherVault = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  const account = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
  const attachment = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
  late EquisDatabase database;
  late DriftAttachmentRepository repository;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    repository = DriftAttachmentRepository(database);
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
      [vault],
    );
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Other', 'BRL', 'UTC', 1, 1)",
      [otherVault],
    );
    await database.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Checking', 'checking', 'asset', 1, 1)",
      [account, vault],
    );
  });

  tearDown(() => database.close());

  test('persists encrypted-file metadata and typed links atomically', () async {
    final value = _attachment(vault: vault, attachment: attachment);
    await repository.save(value);

    final loaded = await repository.find(value.id);
    expect(loaded?.originalFilename, 'receipt.pdf');
    expect(loaded?.localPath, r'F:\Equis\attachments\receipt.equisatt');
    expect(loaded?.links.single.entityType, AttachmentEntityType.account);
    expect(
      await repository.listForEntity(
        entityType: AttachmentEntityType.account,
        entityId: EntityId.parse(account),
      ),
      hasLength(1),
    );
  });

  test(
    'rejects links to another vault and leaves no metadata behind',
    () async {
      final value = _attachment(vault: otherVault, attachment: attachment);

      await expectLater(
        repository.save(value),
        throwsA(isA<AttachmentLinkTargetNotFound>()),
      );
      expect(await repository.find(value.id), isNull);
    },
  );

  test(
    'enforces revision conflicts while upload state remains local-only',
    () async {
      final value = _attachment(vault: vault, attachment: attachment);
      await repository.save(value);
      await repository.setUploadState(value.id, AttachmentUploadState.uploaded);
      final loaded = await repository.find(value.id);
      expect(loaded?.uploadState, AttachmentUploadState.uploaded);
      expect(loaded?.revision, 1);

      await expectLater(
        repository.save(value),
        throwsA(isA<AttachmentRevisionConflict>()),
      );
    },
  );

  test('lists only pending and failed uploads in the selected vault', () async {
    final pending = _attachment(
      vault: vault,
      attachment: attachment,
      uploadState: AttachmentUploadState.pending,
    );
    await repository.save(pending);

    final queued = await repository.listPendingForVault(pending.vaultId);
    expect(queued.map((value) => value.id), [pending.id]);
    await repository.setUploadState(pending.id, AttachmentUploadState.uploaded);
    expect(await repository.listPendingForVault(pending.vaultId), isEmpty);
  });
}

AttachmentMetadata _attachment({
  required String vault,
  required String attachment,
  AttachmentUploadState uploadState = AttachmentUploadState.local,
}) => AttachmentMetadata(
  id: EntityId.parse(attachment),
  vaultId: EntityId.parse(vault),
  originalFilename: 'receipt.pdf',
  mimeType: 'application/pdf',
  byteSize: 42,
  localPath: r'F:\Equis\attachments\receipt.equisatt',
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  uploadState: uploadState,
  links: {
    AttachmentLinkDefinition(
      entityType: AttachmentEntityType.account,
      entityId: EntityId.parse('018f47c2-9b72-7cc1-8b83-5d0fead0a003'),
    ),
  },
  revision: 1,
  createdAt: const UtcInstant.fromEpochMicroseconds(1),
  updatedAt: const UtcInstant.fromEpochMicroseconds(1),
);
