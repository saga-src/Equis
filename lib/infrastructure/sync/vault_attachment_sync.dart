import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import '../../application/services/attachment_service.dart';
import '../../application/ports/cloud_sync_gateway.dart';
import '../../application/sync/encrypted_sync_models.dart';
import '../../domain/shared/uuid_v7.dart';
import '../files/encrypted_attachment_file_codec.dart';
import '../files/equis_file_layout.dart';
import '../persistence/database/equis_database.dart';
import '../repositories/drift_attachment_repository.dart';

/// Local file paths and transfer state never enter the encrypted aggregate.
final class VaultAttachmentSync {
  const VaultAttachmentSync({
    required this.database,
    required this.service,
    required this.codec,
    required this.layout,
  });
  final EquisDatabase database;
  final AttachmentService service;
  final EncryptedAttachmentFileCodec codec;
  final EquisFileLayout layout;

  Future<void> upload(String vaultId) async {
    await database.customStatement(
      "UPDATE attachments SET upload_state='pending' WHERE vault_id=? "
      "AND local_path IS NOT NULL AND upload_state='local' AND deleted_at IS NULL",
      [vaultId],
    );
    if (!await service.uploadPendingForVault(EntityId.parse(vaultId))) {
      throw const CloudSyncFailure(CloudSyncFailureCode.network);
    }
  }

  Future<void> download(String vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT id FROM attachments WHERE vault_id=? AND local_path IS NULL AND deleted_at IS NULL',
          variables: [Variable(vaultId)],
        )
        .get();
    final repository = DriftAttachmentRepository(database);
    for (final row in rows) {
      final attachment = (await repository.find(
        EntityId.parse(row.read<String>('id')),
      ))!;
      final destination = layout.encryptedAttachment(
        vaultId: vaultId,
        attachmentId: attachment.id.value,
      );
      // A prior interrupted download can leave an authenticated but unregistered file.
      if (!await destination.exists()) {
        try {
          await service.cloud!.download(attachment, destination.path);
        } on SocketException {
          throw const CloudSyncFailure(CloudSyncFailureCode.network);
        }
      }
      try {
        final clear = await codec.decryptBytes(
          source: destination,
          vaultId: vaultId,
          attachmentId: attachment.id.value,
        );
        try {
          final digest = (await Sha256().hash(
            clear,
          )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
          if (clear.length != attachment.byteSize ||
              digest != attachment.sha256) {
            throw const PayloadAuthenticationException();
          }
        } finally {
          clear.fillRange(0, clear.length, 0);
        }
      } catch (_) {
        if (await destination.exists()) await destination.delete();
        rethrow;
      }
      await database.customStatement(
        "UPDATE attachments SET local_path=?,upload_state='uploaded' WHERE id=? AND vault_id=?",
        [destination.path, attachment.id.value, vaultId],
      );
    }
  }
}
