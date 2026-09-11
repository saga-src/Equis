import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/ports/attachment_ports.dart';
import '../security/vault_key_manager.dart';
import '../../domain/attachments/attachment_models.dart';

final class SupabaseAttachmentCloudStore implements AttachmentCloudStore {
  const SupabaseAttachmentCloudStore(
    this.client, {
    this.bucket = 'equis-attachments',
    this.keys,
  });

  final SupabaseClient client;
  final String bucket;
  final VaultKeyManager? keys;

  @override
  Future<void> upload(AttachmentMetadata attachment) async {
    final localPath = attachment.localPath;
    if (localPath == null) throw const AttachmentCloudFileUnavailable();
    final file = File(localPath);
    if (!await file.exists()) throw const AttachmentCloudFileUnavailable();
    await client.storage
        .from(bucket)
        .upload(
          await _path(attachment),
          file,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/octet-stream',
            cacheControl: '3600',
          ),
        )
        .timeout(const Duration(minutes: 2));
  }

  @override
  Future<void> download(
    AttachmentMetadata attachment,
    String destinationPath,
  ) async {
    final destination = File(destinationPath);
    if (await destination.exists()) throw const AttachmentCloudFileExists();
    await destination.parent.create(recursive: true);
    final temporary = File('$destinationPath.part');
    if (await temporary.exists()) await temporary.delete();
    try {
      final bytes = await client.storage
          .from(bucket)
          .download(await _path(attachment))
          .timeout(const Duration(minutes: 2));
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destinationPath);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(AttachmentMetadata attachment) async {
    await client.storage
        .from(bucket)
        .remove([await _path(attachment)])
        .timeout(const Duration(minutes: 2));
  }

  Future<String> _path(AttachmentMetadata attachment) async {
    if (keys?.protocolVersion == 2) {
      final identity = await keys!.requireVault(attachment.vaultId.value);
      if (identity.ownerId == null ||
          identity.ownerId != client.auth.currentUser?.id) {
        throw const AttachmentCloudFileUnavailable();
      }
      return 'vault/${identity.vaultId}/${await identity.fingerprint()}/attachments/${attachment.id.value}';
    }
    return 'vault/${attachment.vaultId.value}/attachments/${attachment.id.value}';
  }
}

final class AttachmentCloudFileUnavailable implements Exception {
  const AttachmentCloudFileUnavailable();
}

final class AttachmentCloudFileExists implements Exception {
  const AttachmentCloudFileExists();
}
