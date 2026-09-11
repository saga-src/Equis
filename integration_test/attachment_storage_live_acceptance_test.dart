import 'dart:io';

import 'package:equis/app/providers/local_app_dependencies.dart';
import 'package:equis/core/config/app_config.dart';
import 'package:equis/domain/attachments/attachment_models.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/cloud/supabase_attachment_cloud_store.dart';
import 'package:equis/infrastructure/files/encrypted_attachment_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _enabled = bool.fromEnvironment('EQUIS_RUN_LIVE_ATTACHMENT_ACCEPTANCE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'private Storage accepts only member-authenticated attachment ciphertext',
    (tester) async {
      final dependencies = await LocalAppDependencies.bootstrap();
      final temporary = await Directory.systemTemp.createTemp(
        'equis-storage-acceptance-',
      );
      SupabaseAttachmentCloudStore? cloud;
      AttachmentMetadata? metadata;
      var uploaded = false;
      try {
        final snapshot = await dependencies.session.load();
        final vault = snapshot.vault;
        expect(
          vault,
          isNotNull,
          reason: 'A persisted local vault is required.',
        );
        expect(
          Supabase.instance.client.auth.currentSession,
          isNotNull,
          reason: 'A persisted confirmed Supabase session is required.',
        );
        final vaultId = vault!.id;
        final attachmentId = EntityId.generate();
        final source = File(
          '${temporary.path}${Platform.pathSeparator}acceptance-source.bin',
        );
        final encrypted = File(
          '${temporary.path}${Platform.pathSeparator}acceptance.equisatt',
        );
        final downloaded = File(
          '${temporary.path}${Platform.pathSeparator}downloaded.equisatt',
        );
        await source.writeAsBytes(
          List<int>.generate(777, (index) => (index * 37) % 256),
          flush: true,
        );
        final codec = EncryptedAttachmentFileCodec(
          cipher: dependencies.attachmentEncryption,
          chunkSize: 128,
        );
        final stored = await codec.encryptFile(
          source: source,
          destination: encrypted,
          vaultId: vaultId.value,
          attachmentId: attachmentId.value,
        );
        metadata = AttachmentMetadata(
          id: attachmentId,
          vaultId: vaultId,
          originalFilename: 'acceptance.bin',
          mimeType: 'application/octet-stream',
          byteSize: stored.clearByteSize,
          localPath: stored.file.path,
          sha256: stored.clearSha256,
          uploadState: AttachmentUploadState.pending,
          links: [
            AttachmentLinkDefinition(
              entityType: AttachmentEntityType.transaction,
              entityId: EntityId.generate(),
            ),
          ],
          revision: 1,
          createdAt: UtcInstant.now(),
          updatedAt: UtcInstant.now(),
        );
        cloud = SupabaseAttachmentCloudStore(Supabase.instance.client);
        await cloud.upload(metadata);
        uploaded = true;
        await cloud.download(metadata, downloaded.path);
        expect(await downloaded.readAsBytes(), await encrypted.readAsBytes());

        final path = 'vault/${vaultId.value}/attachments/${attachmentId.value}';
        final config = AppConfig.fromEnvironment();
        final anonymous = SupabaseClient(
          config.supabaseUrl,
          config.supabaseAnonKey,
        );
        await expectLater(
          anonymous.storage.from('equis-attachments').download(path),
          throwsA(isA<StorageException>()),
        );

        final unrelated = AttachmentMetadata(
          id: attachmentId,
          vaultId: EntityId.generate(),
          originalFilename: metadata.originalFilename,
          mimeType: metadata.mimeType,
          byteSize: metadata.byteSize,
          localPath: metadata.localPath,
          sha256: metadata.sha256,
          uploadState: AttachmentUploadState.pending,
          links: metadata.links,
          revision: 1,
          createdAt: metadata.createdAt,
          updatedAt: metadata.updatedAt,
        );
        await expectLater(
          cloud.upload(unrelated),
          throwsA(isA<StorageException>()),
        );

        final clear = await codec.decryptBytes(
          source: downloaded,
          vaultId: vaultId.value,
          attachmentId: attachmentId.value,
        );
        expect(clear, await source.readAsBytes());
      } finally {
        if (uploaded && cloud != null && metadata != null) {
          await cloud.delete(metadata);
        }
        await dependencies.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      }
    },
    skip: !_enabled,
  );
}
