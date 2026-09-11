import '../../domain/attachments/attachment_models.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class AttachmentRepository {
  Future<void> save(AttachmentMetadata attachment);
  Future<AttachmentMetadata?> find(EntityId id);
  Future<List<AttachmentMetadata>> listForEntity({
    required AttachmentEntityType entityType,
    required EntityId entityId,
  });
  Future<List<AttachmentMetadata>> listPendingForVault(EntityId vaultId);
  Future<void> setUploadState(EntityId id, AttachmentUploadState state);
}

final class StoredAttachmentContent {
  const StoredAttachmentContent({
    required this.localPath,
    required this.byteSize,
    required this.sha256,
  });

  final String localPath;
  final int byteSize;
  final String sha256;
}

abstract interface class AttachmentContentStore {
  Future<StoredAttachmentContent> import({
    required String sourcePath,
    required EntityId vaultId,
    required EntityId attachmentId,
  });
  Future<void> decryptTo({
    required AttachmentMetadata attachment,
    required String destinationPath,
  });
  Future<void> delete(AttachmentMetadata attachment);
}

abstract interface class AttachmentCloudStore {
  Future<void> upload(AttachmentMetadata attachment);
  Future<void> download(AttachmentMetadata attachment, String destinationPath);
  Future<void> delete(AttachmentMetadata attachment);
}

final class AttachmentRevisionConflict implements Exception {
  const AttachmentRevisionConflict({required this.id});

  final EntityId id;
}

final class AttachmentLinkTargetNotFound implements Exception {
  const AttachmentLinkTargetNotFound({required this.link});

  final AttachmentLinkDefinition link;
}
