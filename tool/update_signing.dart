import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:equis/infrastructure/updates/update_public_key.dart';
import 'package:equis/infrastructure/updates/update_manifest.dart';

// Never print private material. UPDATE_SIGNING_SEED is a base64 32-byte seed.
Future<void> main(List<String> args) async {
  final algorithm = Ed25519();
  if (args.length == 2 && args[0] == 'init-test') {
    final directory = Directory(args[1]);
    _requireTestPath(directory.path);
    await directory.create(recursive: true);
    final seed = File(p.join(directory.path, 'ed25519.seed'));
    if (await seed.exists()) {
      throw StateError('Test signing key already exists');
    }
    final key = await algorithm.newKeyPair();
    await seed.writeAsString(
      base64Encode(await key.extractPrivateKeyBytes()),
      flush: true,
    );
    await File(p.join(directory.path, 'public-key.txt')).writeAsString(
      base64Encode((await key.extractPublicKey()).bytes),
      flush: true,
    );
    return;
  }
  if (args.length == 2 && args[0] == 'init') {
    final directory = Directory(args[1]);
    await directory.create(recursive: true);
    final keyFile = File('${directory.path}/ed25519.seed');
    if (await keyFile.exists()) throw StateError('Signing key already exists');
    final key = await algorithm.newKeyPair();
    await keyFile.writeAsString(
      base64Encode(await key.extractPrivateKeyBytes()),
      flush: true,
    );
    final public = base64Encode((await key.extractPublicKey()).bytes);
    await File(
      'lib/infrastructure/updates/update_public_key.dart',
    ).writeAsString(
      '// Public release verification key. Private seed stays outside Git.\n'
      "const updatePublicKey = '$public';\n",
    );
    return;
  }
  if (args.length != 4 ||
      !const {
        'sign',
        'sign-catalog',
        'sign-test',
        'sign-catalog-test',
      }.contains(args[0])) {
    throw ArgumentError(
      'init <private-directory> | sign-catalog <release-directory> <version> <build> | sign <artifacts-directory> <version> <build>',
    );
  }
  final testMode = args[0].endsWith('-test');
  final publicKey = testMode ? _testPublicKey() : updatePublicKey;
  if (testMode) _requireTestPath(args[1]);
  final seed = Platform.environment['UPDATE_SIGNING_SEED'];
  if (seed == null) throw StateError('UPDATE_SIGNING_SEED is required');
  late final SimpleKeyPair key;
  try {
    final bytes = base64Decode(seed.trim());
    if (bytes.length != 32) throw const FormatException();
    key = await algorithm.newKeyPairFromSeed(bytes);
  } catch (_) {
    // FormatException/ArgumentError can otherwise echo the secret input.
    throw StateError('Invalid update signing secret');
  }
  if (base64Encode((await key.extractPublicKey()).bytes) != publicKey) {
    throw StateError('Release signing key does not match the application');
  }
  final dir = Directory(args[1]);
  final version = args[2], build = int.parse(args[3]);
  UpdateVersion(version, build).compareTo(UpdateVersion(version, build));
  if (build < 1) throw ArgumentError('Build must be positive');
  if (args[0] == 'sign-catalog' || args[0] == 'sign-catalog-test') {
    await _signCatalog(dir, version, build, algorithm, key, testMode: testMode);
    return;
  }
  final catalogHash = await verifyWindowsCatalogInPortable(
    dir,
    version,
    build,
    testMode: testMode,
  );
  final packages = <Map<String, Object>>[];
  for (final platform in [
    if (!testMode) 'android',
    'windows-installed',
    'windows-portable',
  ]) {
    final suffix = switch (platform) {
      'android' => 'Android-$version.apk',
      'windows-installed' => 'Windows-$version-setup.exe',
      _ => 'Windows-$version-portable.zip',
    };
    final file = File('${dir.path}/Equis-$suffix');
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    final entry = <String, Object>{
      'platform': platform,
      'file': file.uri.pathSegments.last,
      'size': await file.length(),
      'sha256': hash.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    };
    if (platform == 'windows-installed') {
      entry['trustCatalogSha256'] = catalogHash;
    }
    packages.add(entry);
  }
  final bytes = utf8.encode(
    jsonEncode({
      'format': 1,
      'applicationId': testMode
          ? 'app.saga.equis.update-test'
          : 'app.saga.equis',
      'version': version,
      'build': build,
      'tag': 'v$version',
      'packages': packages,
    }),
  );
  final signature = await algorithm.sign(bytes, keyPair: key);
  await File(
    '${dir.path}/update-manifest.json',
  ).writeAsBytes(bytes, flush: true);
  await File(
    '${dir.path}/update-manifest.sig',
  ).writeAsString(base64Encode(signature.bytes), flush: true);
}

Future<void> _signCatalog(
  Directory release,
  String version,
  int build,
  Ed25519 algorithm,
  SimpleKeyPair key, {
  required bool testMode,
}) async {
  if (!await release.exists()) {
    throw StateError('Windows release directory is missing');
  }
  final metadata = jsonDecode(
    await File(p.join(release.path, 'app-version.json')).readAsString(),
  );
  if (metadata is! Map<String, dynamic> ||
      metadata['version'] != version ||
      metadata['build'] != build ||
      !_validMetadata(metadata, testMode)) {
    throw StateError('Windows bundle version differs from the signing request');
  }
  final entries = <String, File>{};
  await for (final entity in release.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is Link) {
      throw StateError('Links are forbidden in the Windows bundle');
    }
    if (entity is! File) continue;
    final name = p
        .relative(entity.path, from: release.path)
        .replaceAll('\\', '/');
    _validateCatalogPath(name);
    if (const {
      'app-files.json',
      'app-trust.json',
      'app-trust.sig',
    }.contains(name.toLowerCase())) {
      if (name != name.toLowerCase()) {
        throw StateError('Non-canonical Windows trust file name');
      }
      continue;
    }
    if (entries.keys.any((old) => old.toLowerCase() == name.toLowerCase())) {
      throw StateError('Duplicate Windows bundle path');
    }
    entries[name] = entity;
  }
  for (final name in const ['equis.exe', 'equis-update-helper.exe']) {
    if (!entries.containsKey(name)) {
      throw StateError('Missing Windows application/helper bundle role');
    }
  }
  if (entries.keys.any(
    (name) => name.toLowerCase() == 'equis-update-broker.exe',
  )) {
    throw StateError('Obsolete broker is forbidden in the Windows bundle');
  }
  final names = <String>{
    ...entries.keys,
    'app-files.json',
    'app-trust.json',
    'app-trust.sig',
  }.toList()..sort();
  final inventory = File(p.join(release.path, 'app-files.json'));
  await inventory.writeAsBytes(utf8.encode(jsonEncode(names)), flush: true);
  entries['app-files.json'] = inventory;
  final files = <Map<String, Object>>[];
  final catalogNames = entries.keys.toList()..sort();
  for (final name in catalogNames) {
    final file = entries[name]!;
    final size = await file.length();
    if (size > 2147483648) {
      throw StateError('Windows catalog file is too large');
    }
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    files.add({
      'path': name,
      'role': switch (name) {
        'equis.exe' => 'app',
        'equis-update-helper.exe' => 'coordinator',
        _ => 'data',
      },
      'size': size,
      'sha256': _hex((await sink.hash()).bytes),
    });
  }
  if (files.length > 8192) {
    throw StateError('Windows catalog has too many files');
  }
  final raw = utf8.encode(
    jsonEncode({
      'kind': 'equis-windows-file-catalog',
      'format': 2,
      'applicationId': testMode
          ? 'app.saga.equis.update-test'
          : 'app.saga.equis',
      'innoAppId': testMode
          ? '8B18F7D4-35F6-4DDE-ABFD-E76991B831D2'
          : 'B9ECD233-7990-478B-A5F1-C30E4BCAA15E',
      'architecture': 'x64',
      'version': version,
      'build': build,
      'files': files,
    }),
  );
  if (raw.length > 1048576) throw StateError('Windows catalog is too large');
  const prefix = 'Equis.WindowsFileCatalog\u0000v1\u0000';
  final signature = await algorithm.sign([
    ...utf8.encode(prefix),
    ...raw,
  ], keyPair: key);
  await File(
    p.join(release.path, 'app-trust.json'),
  ).writeAsBytes(raw, flush: true);
  // Catalog verifiers consume exactly 64 signature bytes, not base64 text.
  await File(
    p.join(release.path, 'app-trust.sig'),
  ).writeAsBytes(signature.bytes, flush: true);
  final written = await File(
    p.join(release.path, 'app-trust.json'),
  ).readAsBytes();
  final writtenSignature = await File(
    p.join(release.path, 'app-trust.sig'),
  ).readAsBytes();
  if (!_equalBytes(written, raw) ||
      !_equalBytes(writtenSignature, signature.bytes) ||
      !await algorithm.verify(
        [...utf8.encode(prefix), ...written],
        signature: Signature(
          writtenSignature,
          publicKey: await key.extractPublicKey(),
        ),
      )) {
    throw StateError('Windows trust catalog write verification failed');
  }
  for (final entry in files) {
    final path = entry['path'] as String;
    final file = entries[path]!;
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    if (await file.length() != entry['size'] ||
        _hex((await sink.hash()).bytes) != entry['sha256']) {
      throw StateError('Windows bundle changed during catalog signing');
    }
  }
}

/// Checks the signed sidecar against every file in the portable bundle before
/// the release manifest can bind that catalog to the installed package.
Future<String> verifyWindowsCatalogInPortable(
  Directory artifacts,
  String version,
  int build, {
  bool testMode = false,
}) async {
  if (testMode) _requireTestPath(artifacts.path);
  final raw = await File(
    p.join(artifacts.path, 'app-trust.json'),
  ).readAsBytes();
  final signature = await File(
    p.join(artifacts.path, 'app-trust.sig'),
  ).readAsBytes();
  if (raw.isEmpty || raw.length > 1048576 || signature.length != 64) {
    throw StateError('Invalid Windows trust catalog sidecar');
  }
  const prefix = 'Equis.WindowsFileCatalog\u0000v1\u0000';
  final valid = await Ed25519().verify(
    [...utf8.encode(prefix), ...raw],
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(
        base64Decode(testMode ? _testPublicKey() : updatePublicKey),
        type: KeyPairType.ed25519,
      ),
    ),
  );
  if (!valid) throw StateError('Invalid Windows trust catalog signature');
  final catalog = jsonDecode(utf8.decode(raw));
  if (catalog is! Map<String, dynamic> ||
      !_exactKeys(catalog, const {
        'kind',
        'format',
        'applicationId',
        'innoAppId',
        'architecture',
        'version',
        'build',
        'files',
      }) ||
      catalog['kind'] != 'equis-windows-file-catalog' ||
      catalog['format'] != 2 ||
      catalog['applicationId'] !=
          (testMode ? 'app.saga.equis.update-test' : 'app.saga.equis') ||
      catalog['innoAppId'] !=
          (testMode
              ? '8B18F7D4-35F6-4DDE-ABFD-E76991B831D2'
              : 'B9ECD233-7990-478B-A5F1-C30E4BCAA15E') ||
      catalog['architecture'] != 'x64' ||
      catalog['version'] != version ||
      catalog['build'] != build ||
      catalog['files'] is! List) {
    throw StateError('Windows trust catalog identity mismatch');
  }
  final zip = File(
    p.join(artifacts.path, 'Equis-Windows-$version-portable.zip'),
  );
  final archive = ZipDecoder().decodeBytes(
    await zip.readAsBytes(),
    verify: true,
  );
  final files = <String, List<int>>{};
  final folded = <String>{};
  var expanded = 0;
  for (final entry in archive) {
    if (entry.isSymbolicLink) {
      throw StateError('Windows bundle contains a link');
    }
    final name = entry.isDirectory && entry.name.endsWith('/')
        ? entry.name.substring(0, entry.name.length - 1)
        : entry.name;
    _validateCatalogPath(name);
    if (name.toLowerCase() == 'equis-update-broker.exe') {
      throw StateError('Obsolete broker is forbidden in the Windows bundle');
    }
    if (!folded.add(name.toLowerCase())) {
      throw StateError('Duplicate Windows bundle path');
    }
    if (entry.isFile) {
      expanded += entry.size;
      if (entry.size < 0 || entry.size > 2147483648 || expanded > 4294967296) {
        throw StateError('Windows bundle file is too large');
      }
      files[name] = entry.content;
    }
  }
  if (files.length > 8194 ||
      !_equalBytes(files['app-trust.json'], raw) ||
      !_equalBytes(files['app-trust.sig'], signature)) {
    throw StateError('Windows trust catalog differs from the portable bundle');
  }
  final entries = catalog['files'] as List;
  if (entries.isEmpty ||
      entries.length > 8192 ||
      entries.length + 2 != files.length) {
    throw StateError('Windows trust catalog coverage mismatch');
  }
  final covered = <String>{};
  final roles = <String>{};
  for (final item in entries) {
    if (item is! Map<String, dynamic> ||
        !_exactKeys(item, const {'path', 'role', 'size', 'sha256'})) {
      throw StateError('Invalid Windows trust catalog entry');
    }
    final name = item['path'];
    final role = item['role'];
    final size = item['size'];
    final hash = item['sha256'];
    if (name is! String ||
        role is! String ||
        size is! int ||
        hash is! String ||
        size < 0 ||
        size > 2147483648 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw StateError('Invalid Windows trust catalog entry');
    }
    _validateCatalogPath(name);
    if (!covered.add(name) ||
        const {
          'app-trust.json',
          'app-trust.sig',
        }.contains(name.toLowerCase())) {
      throw StateError('Duplicate Windows trust catalog path');
    }
    final expectedRole = switch (name) {
      'equis.exe' => 'app',
      'equis-update-helper.exe' => 'coordinator',
      _ => 'data',
    };
    if (role != expectedRole ||
        (role != 'data' && (size == 0 || !roles.add(role)))) {
      throw StateError('Invalid Windows trust catalog role');
    }
    final bytes = files[name];
    if (bytes == null ||
        bytes.length != size ||
        _hex((await Sha256().hash(bytes)).bytes) != hash) {
      throw StateError('Windows bundle file differs from the trust catalog');
    }
  }
  if (roles.length != 2 ||
      !covered.contains('app-version.json') ||
      !covered.contains('app-files.json') ||
      files.keys.any(
        (name) =>
            name != 'app-trust.json' &&
            name != 'app-trust.sig' &&
            !covered.contains(name),
      )) {
    throw StateError('Windows trust catalog coverage mismatch');
  }
  final inventory = jsonDecode(utf8.decode(files['app-files.json']!));
  final expectedNames = files.keys.toList()..sort();
  if (inventory is! List || inventory.length != expectedNames.length) {
    throw StateError('Windows bundle inventory mismatch');
  }
  for (var i = 0; i < expectedNames.length; i++) {
    if (inventory[i] != expectedNames[i]) {
      throw StateError('Windows bundle inventory mismatch');
    }
  }
  final metadata = jsonDecode(utf8.decode(files['app-version.json']!));
  if (metadata is! Map<String, dynamic> ||
      !_validMetadata(metadata, testMode) ||
      metadata['version'] != version ||
      metadata['build'] != build) {
    throw StateError('Windows bundle metadata mismatch');
  }
  return _hex((await Sha256().hash(raw)).bytes);
}

bool _validMetadata(Map<String, dynamic> metadata, bool testMode) =>
    _exactKeys(metadata, const {
      'version',
      'build',
      'applicationId',
      'innoAppId',
      'updateTestMode',
    }) &&
    metadata['applicationId'] ==
        (testMode ? 'app.saga.equis.update-test' : 'app.saga.equis') &&
    metadata['innoAppId'] ==
        (testMode
            ? '8B18F7D4-35F6-4DDE-ABFD-E76991B831D2'
            : 'B9ECD233-7990-478B-A5F1-C30E4BCAA15E') &&
    metadata['updateTestMode'] == testMode;

String _testPublicKey() {
  final value = Platform.environment['EQUIS_UPDATE_TEST_PUBLIC_KEY'];
  if (value == null || value.isEmpty) {
    throw StateError('Test public key is required');
  }
  try {
    if (base64Decode(value).length != 32 || value == updatePublicKey) {
      throw const FormatException();
    }
  } catch (_) {
    throw StateError('Invalid isolated test public key');
  }
  return value;
}

void _requireTestPath(String path) {
  final root = Platform.environment['EQUIS_UPDATE_TEST_ROOT'];
  if (root == null ||
      !p.isAbsolute(root) ||
      !p.isAbsolute(path) ||
      !p.isWithin(p.normalize(root), p.normalize(path))) {
    throw StateError(
      'Test signing output must be inside the isolated test root',
    );
  }
  var current = p.normalize(path);
  while (true) {
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError('Test signing paths must not contain links');
    }
    if (type == FileSystemEntityType.directory &&
        !p.equals(Directory(current).resolveSymbolicLinksSync(), current)) {
      throw StateError(
        'Test signing paths must not contain redirected directories',
      );
    }
    final parent = p.dirname(current);
    if (parent == current) break;
    current = parent;
  }
}

bool _exactKeys(Map<String, dynamic> value, Set<String> keys) =>
    value.length == keys.length && value.keys.toSet().containsAll(keys);

bool _equalBytes(List<int>? left, List<int> right) {
  if (left == null || left.length != right.length) return false;
  for (var i = 0; i < right.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

void _validateCatalogPath(String name) {
  if (name.isEmpty ||
      utf8.encode(name).length > 1024 ||
      name.contains('\\') ||
      name.startsWith('/') ||
      name.endsWith('/')) {
    throw StateError('Invalid Windows catalog path');
  }
  final parts = name.split('/');
  if (parts.length > 32) throw StateError('Invalid Windows catalog path');
  final reserved = RegExp(
    r'^(con|prn|aux|nul|conin\$|conout\$|com[1-9¹²³]|lpt[1-9¹²³])$',
    caseSensitive: false,
  );
  for (final part in parts) {
    final stem = part.split('.').first.replaceFirst(RegExp(r'[ .]+$'), '');
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.length > 255 ||
        part.endsWith(' ') ||
        part.endsWith('.') ||
        reserved.hasMatch(stem) ||
        part.contains(RegExp(r'[\\:*?"<>|\x00-\x1f\x7f]'))) {
      throw StateError('Invalid Windows catalog path');
    }
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
