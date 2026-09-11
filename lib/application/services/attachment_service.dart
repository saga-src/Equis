import '../../domain/attachments/attachment_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../ports/attachment_ports.dart';

final class AttachmentService {
  const AttachmentService({
    required this.repository,
    required this.content,
    this.cloud,
  });

  final AttachmentRepository repository;
  final AttachmentContentStore content;
  final AttachmentCloudStore? cloud;
  bool get cloudAvailable => cloud != null;

  Future<AttachmentMetadata> add({
    required EntityId vaultId,
    required String sourcePath,
    required Iterable<AttachmentLinkDefinition> links,
    required UtcInstant now,
    String? originalFilename,
    String? mimeType,
  }) async {
    final id = EntityId.generate();
    final stored = await content.import(
      sourcePath: sourcePath,
      vaultId: vaultId,
      attachmentId: id,
    );
    final attachment = AttachmentMetadata(
      id: id,
      vaultId: vaultId,
      originalFilename: originalFilename ?? _basename(sourcePath),
      mimeType: mimeType,
      byteSize: stored.byteSize,
      localPath: stored.localPath,
      sha256: stored.sha256,
      uploadState: cloud == null
          ? AttachmentUploadState.local
          : AttachmentUploadState.pending,
      links: links,
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await repository.save(attachment);
    } catch (_) {
      await content.delete(attachment);
      rethrow;
    }
    if (cloud != null) {
      try {
        await upload(attachment);
      } catch (_) {
        // The local encrypted attachment is authoritative while cloud is offline.
      }
    }
    return await repository.find(id) ?? attachment;
  }

  Future<List<AttachmentMetadata>> listForEntity({
    required AttachmentEntityType entityType,
    required EntityId entityId,
  }) => repository.listForEntity(entityType: entityType, entityId: entityId);

  Future<void> exportClear(
    AttachmentMetadata attachment,
    String destinationPath,
  ) => content.decryptTo(
    attachment: attachment,
    destinationPath: destinationPath,
  );

  Future<void> upload(AttachmentMetadata attachment) async {
    final remote = cloud;
    if (remote == null) throw const AttachmentCloudUnavailable();
    await repository.setUploadState(
      attachment.id,
      AttachmentUploadState.pending,
    );
    try {
      await remote.upload(attachment);
      await repository.setUploadState(
        attachment.id,
        AttachmentUploadState.uploaded,
      );
    } catch (_) {
      await repository.setUploadState(
        attachment.id,
        AttachmentUploadState.failed,
      );
      rethrow;
    }
  }

  Future<bool> uploadPendingForVault(EntityId vaultId) async {
    if (cloud == null) return true;
    var succeeded = true;
    for (final attachment in await repository.listPendingForVault(vaultId)) {
      try {
        await upload(attachment);
      } catch (_) {
        succeeded = false;
      }
    }
    return succeeded;
  }
}

final class AttachmentCloudUnavailable implements Exception {
  const AttachmentCloudUnavailable();
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
