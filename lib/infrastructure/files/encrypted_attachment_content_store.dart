import 'dart:io';

import '../../application/ports/attachment_ports.dart';
import '../../domain/attachments/attachment_models.dart';
import '../../domain/shared/uuid_v7.dart';
import 'encrypted_attachment_file_codec.dart';
import 'equis_file_layout.dart';

final class EncryptedAttachmentContentStore implements AttachmentContentStore {
  const EncryptedAttachmentContentStore({
    required this.layout,
    required this.codec,
  });

  final EquisFileLayout layout;
  final EncryptedAttachmentFileCodec codec;

  @override
  Future<StoredAttachmentContent> import({
    required String sourcePath,
    required EntityId vaultId,
    required EntityId attachmentId,
  }) async {
    final stored = await codec.encryptFile(
      source: File(sourcePath),
      destination: layout.encryptedAttachment(
        vaultId: vaultId.value,
        attachmentId: attachmentId.value,
      ),
      vaultId: vaultId.value,
      attachmentId: attachmentId.value,
    );
    return StoredAttachmentContent(
      localPath: stored.file.path,
      byteSize: stored.clearByteSize,
      sha256: stored.clearSha256,
    );
  }

  @override
  Future<void> decryptTo({
    required AttachmentMetadata attachment,
    required String destinationPath,
  }) async {
    final localPath = attachment.localPath;
    if (localPath == null) throw const AttachmentFileNotFoundException();
    await codec.decryptFile(
      source: File(localPath),
      destination: File(destinationPath),
      vaultId: attachment.vaultId.value,
      attachmentId: attachment.id.value,
    );
  }

  @override
  Future<void> delete(AttachmentMetadata attachment) async {
    final localPath = attachment.localPath;
    if (localPath == null) return;
    final file = File(localPath);
    if (await file.exists()) await file.delete();
    final partial = File('$localPath.part');
    if (await partial.exists()) await partial.delete();
  }
}
