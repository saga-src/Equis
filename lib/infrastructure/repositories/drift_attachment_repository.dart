import 'package:drift/drift.dart';

import '../../application/ports/attachment_ports.dart';
import '../../application/sync/sync_models.dart';
import '../../domain/attachments/attachment_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftAttachmentRepository implements AttachmentRepository {
  const DriftAttachmentRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(AttachmentMetadata attachment) =>
      syncRecorder?.run(
        vaultId: attachment.vaultId.value,
        entityType: SyncEntityType.attachment,
        recordId: attachment.id.value,
        newRevision: attachment.revision,
        operation: attachment.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(attachment),
      ) ??
      _save(attachment);

  Future<void> _save(AttachmentMetadata attachment) => database.transaction(
    () async {
      for (final link in attachment.links) {
        await _verifyLinkTarget(attachment.vaultId, link);
      }
      final current = await database
          .customSelect(
            'SELECT revision FROM attachments WHERE id = ?',
            variables: [Variable(attachment.id.value)],
            readsFrom: {database.attachments},
          )
          .getSingleOrNull();
      if (current == null) {
        if (attachment.revision != 1) {
          throw AttachmentRevisionConflict(id: attachment.id);
        }
        await database.customStatement(
          'INSERT INTO attachments '
          '(id, vault_id, original_filename, mime_type, byte_size, local_path, '
          'sha256, upload_state, revision, created_at, updated_at, deleted_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            attachment.id.value,
            attachment.vaultId.value,
            attachment.originalFilename,
            attachment.mimeType,
            attachment.byteSize,
            attachment.localPath,
            attachment.sha256,
            attachment.uploadState.name,
            attachment.revision,
            attachment.createdAt.epochMicroseconds,
            attachment.updatedAt.epochMicroseconds,
            attachment.deletedAt?.epochMicroseconds,
          ],
        );
      } else {
        final expected = attachment.revision - 1;
        if (current.read<int>('revision') != expected) {
          throw AttachmentRevisionConflict(id: attachment.id);
        }
        final changed = await database.customUpdate(
          'UPDATE attachments SET original_filename = ?, mime_type = ?, '
          'byte_size = ?, local_path = ?, sha256 = ?, upload_state = ?, '
          'revision = ?, updated_at = ?, deleted_at = ? '
          'WHERE id = ? AND vault_id = ? AND revision = ?',
          variables: _variables([
            attachment.originalFilename,
            attachment.mimeType,
            attachment.byteSize,
            attachment.localPath,
            attachment.sha256,
            attachment.uploadState.name,
            attachment.revision,
            attachment.updatedAt.epochMicroseconds,
            attachment.deletedAt?.epochMicroseconds,
            attachment.id.value,
            attachment.vaultId.value,
            expected,
          ]),
          updates: {database.attachments},
        );
        if (changed != 1) {
          throw AttachmentRevisionConflict(id: attachment.id);
        }
        await database.customStatement(
          'DELETE FROM attachment_links WHERE attachment_id = ?',
          [attachment.id.value],
        );
      }
      for (final link in attachment.links) {
        await database.customStatement(
          'INSERT INTO attachment_links '
          '(attachment_id, entity_type, entity_id) VALUES (?, ?, ?)',
          [attachment.id.value, link.entityType.stored, link.entityId.value],
        );
      }
    },
  );

  Future<void> _verifyLinkTarget(
    EntityId vaultId,
    AttachmentLinkDefinition link,
  ) async {
    final table = switch (link.entityType) {
      AttachmentEntityType.transaction => 'transactions',
      AttachmentEntityType.account => 'accounts',
      AttachmentEntityType.goal => 'goals',
      AttachmentEntityType.asset => 'assets',
      AttachmentEntityType.investmentInstrument => 'investment_instruments',
    };
    final row = await database
        .customSelect(
          'SELECT 1 AS present FROM $table '
          'WHERE id = ? AND vault_id = ? AND deleted_at IS NULL',
          variables: [Variable(link.entityId.value), Variable(vaultId.value)],
        )
        .getSingleOrNull();
    if (row == null) throw AttachmentLinkTargetNotFound(link: link);
  }

  @override
  Future<AttachmentMetadata?> find(EntityId id) async {
    final row = await database
        .customSelect(
          'SELECT * FROM attachments WHERE id = ? AND deleted_at IS NULL',
          variables: [Variable(id.value)],
          readsFrom: {database.attachments},
        )
        .getSingleOrNull();
    return row == null ? null : _load(row.data);
  }

  @override
  Future<List<AttachmentMetadata>> listForEntity({
    required AttachmentEntityType entityType,
    required EntityId entityId,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT attachment.* FROM attachments AS attachment '
          'INNER JOIN attachment_links AS link '
          'ON link.attachment_id = attachment.id '
          'WHERE link.entity_type = ? AND link.entity_id = ? '
          'AND attachment.deleted_at IS NULL '
          'ORDER BY attachment.created_at, attachment.id',
          variables: [Variable(entityType.stored), Variable(entityId.value)],
          readsFrom: {database.attachments, database.attachmentLinks},
        )
        .get();
    return Future.wait(rows.map((row) => _load(row.data)));
  }

  @override
  Future<List<AttachmentMetadata>> listPendingForVault(EntityId vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM attachments WHERE vault_id = ? '
          "AND upload_state IN ('pending', 'failed') "
          'AND deleted_at IS NULL ORDER BY created_at, id',
          variables: [Variable(vaultId.value)],
          readsFrom: {database.attachments},
        )
        .get();
    return Future.wait(rows.map((row) => _load(row.data)));
  }

  Future<AttachmentMetadata> _load(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final linkRows = await database
        .customSelect(
          'SELECT entity_type, entity_id FROM attachment_links '
          'WHERE attachment_id = ? ORDER BY entity_type, entity_id',
          variables: [Variable(id)],
          readsFrom: {database.attachmentLinks},
        )
        .get();
    return AttachmentMetadata(
      id: EntityId.parse(id),
      vaultId: EntityId.parse(row['vault_id']! as String),
      originalFilename: row['original_filename']! as String,
      mimeType: row['mime_type'] as String?,
      byteSize: row['byte_size']! as int,
      localPath: row['local_path'] as String?,
      sha256: row['sha256']! as String,
      uploadState: AttachmentUploadState.fromStorage(
        row['upload_state']! as String,
      ),
      links: {
        for (final link in linkRows)
          AttachmentLinkDefinition(
            entityType: AttachmentEntityType.fromStorage(
              link.read<String>('entity_type'),
            ),
            entityId: EntityId.parse(link.read<String>('entity_id')),
          ),
      },
      revision: row['revision']! as int,
      createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
      updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
    );
  }

  @override
  Future<void> setUploadState(EntityId id, AttachmentUploadState state) async {
    final changed = await database.customUpdate(
      'UPDATE attachments SET upload_state = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      variables: [Variable(state.name), Variable(id.value)],
      updates: {database.attachments},
    );
    if (changed != 1) throw AttachmentRevisionConflict(id: id);
  }
}

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map(Variable<Object>.new).toList(growable: false);
