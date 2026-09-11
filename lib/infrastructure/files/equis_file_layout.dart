import 'dart:io';

final class EquisFileLayout {
  const EquisFileLayout(this.root);

  final Directory root;

  Directory get attachments =>
      Directory('${root.path}${Platform.pathSeparator}attachments');
  Directory get cache =>
      Directory('${root.path}${Platform.pathSeparator}cache');
  Directory get backups =>
      Directory('${root.path}${Platform.pathSeparator}backups');
  Directory get exports =>
      Directory('${root.path}${Platform.pathSeparator}exports');

  Future<void> ensureCreated() async {
    for (final directory in {root, attachments, cache, backups, exports}) {
      await directory.create(recursive: true);
    }
  }

  File encryptedAttachment({
    required String vaultId,
    required String attachmentId,
  }) => File(
    '${attachments.path}${Platform.pathSeparator}$vaultId'
    '${Platform.pathSeparator}$attachmentId.equisatt',
  );
}
