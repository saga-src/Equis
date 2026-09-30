import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_public_key.dart';

const windowsUpdateTestMode = bool.fromEnvironment('EQUIS_UPDATE_TEST_MODE');
const windowsUpdateApplicationId = windowsUpdateTestMode
    ? 'app.saga.equis.update-test'
    : 'app.saga.equis';
const windowsUpdateInnoAppId = windowsUpdateTestMode
    ? '8B18F7D4-35F6-4DDE-ABFD-E76991B831D2'
    : 'B9ECD233-7990-478B-A5F1-C30E4BCAA15E';
const windowsUpdateVerificationKey = windowsUpdateTestMode
    ? String.fromEnvironment('EQUIS_UPDATE_TEST_PUBLIC_KEY')
    : updatePublicKey;

// Production activation was authorized after the disposable matrix closeout.
// Test builds still opt in explicitly; production can be disabled per build.
const windowsInstalledUpdateEnabled = windowsUpdateTestMode
    ? bool.fromEnvironment('EQUIS_WINDOWS_INSTALLED_UPDATE_ENABLED')
    : !bool.fromEnvironment('EQUIS_WINDOWS_INSTALLED_UPDATE_DISABLED');

Future<Directory?> windowsUpdateSupportDirectoryRoot() async {
  if (!windowsUpdateTestMode) return null;
  const root = String.fromEnvironment('EQUIS_UPDATE_TEST_ROOT');
  if (root.isEmpty || !p.isAbsolute(root) || p.normalize(root) != root) {
    throw StateError('An absolute isolated update test root is required');
  }
  var current = root;
  while (true) {
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory)) {
      throw StateError('The update test root must not contain links');
    }
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
  final directory = Directory(root);
  await directory.create(recursive: true);
  final resolved = await directory.resolveSymbolicLinks();
  if (!p.equals(resolved, root)) {
    throw StateError(
      'The update test root resolves outside its configured path',
    );
  }
  return directory;
}
