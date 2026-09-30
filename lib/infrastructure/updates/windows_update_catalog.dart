import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'windows_update_identity.dart';
import 'windows_update_native.dart';

const _catalogDomain = 'Equis.WindowsFileCatalog\u0000v1\u0000';
final _hashPattern = RegExp(r'^[0-9a-f]{64}$');

/// Retains read locks on the signed installed files until the caller closes it.
/// A new setup cannot replace those files while this attestation is open.
final class WindowsUpdateCatalog {
  WindowsUpdateCatalog._(
    this._locks, {
    required this.directory,
    required this.version,
    required this.build,
    required this.rawHash,
    required this.helperSha256,
    required this.files,
  });

  final String directory, version, rawHash, helperSha256;
  final int build;
  final Map<String, WindowsUpdateCatalogFile> files;
  final List<WindowsUpdateFile> _locks;
  bool _closed = false;

  String get helperPath => p.join(directory, 'equis-update-helper.exe');

  static Future<WindowsUpdateCatalog> inspect(
    String directory, {
    String? verificationKey,
  }) async {
    if (!Platform.isWindows ||
        !p.isAbsolute(directory) ||
        p.normalize(directory) != directory) {
      throw const FormatException('Invalid catalog directory');
    }
    final canonical = await Directory(directory).resolveSymbolicLinks();
    if (!p.equals(canonical, directory)) {
      throw const FormatException('Catalog directory changed');
    }
    final locks = <WindowsUpdateFile>[];
    try {
      Future<WindowsUpdateFile> locked(String name) async {
        final path = p.join(directory, name);
        await _rejectLinks(directory, path);
        final lock = WindowsUpdateFile.open(path);
        locks.add(lock);
        return lock;
      }

      final catalogLock = await locked('app-trust.json');
      final signatureLock = await locked('app-trust.sig');
      if (catalogLock.size < 1 ||
          catalogLock.size > 1048576 ||
          signatureLock.size != 64) {
        throw const FormatException('Invalid Windows catalog size');
      }
      final raw = await File(p.join(directory, 'app-trust.json')).readAsBytes();
      final signature = await File(
        p.join(directory, 'app-trust.sig'),
      ).readAsBytes();
      catalogLock.revalidate();
      signatureLock.revalidate();
      if (raw.length != catalogLock.size || signature.length != 64) {
        throw const FormatException('Windows catalog changed');
      }
      final publicKey = base64Decode(
        verificationKey ?? windowsUpdateVerificationKey,
      );
      if (publicKey.length != 32 ||
          !await Ed25519().verify(
            [...ascii.encode(_catalogDomain), ...raw],
            signature: Signature(
              signature,
              publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
            ),
          )) {
        throw const FormatException('Invalid Windows catalog signature');
      }
      final decoded = jsonDecode(utf8.decode(raw, allowMalformed: false));
      if (decoded is! Map<String, dynamic> ||
          !_keys(decoded, const {
            'kind',
            'format',
            'applicationId',
            'innoAppId',
            'architecture',
            'version',
            'build',
            'files',
          }) ||
          decoded['kind'] != 'equis-windows-file-catalog' ||
          decoded['format'] != 2 ||
          decoded['applicationId'] != windowsUpdateApplicationId ||
          decoded['innoAppId'] != windowsUpdateInnoAppId ||
          decoded['architecture'] != 'x64' ||
          decoded['version'] is! String ||
          !_version(decoded['version'] as String) ||
          decoded['build'] is! int ||
          (decoded['build'] as int) < 1 ||
          (decoded['build'] as int) > 2147483647 ||
          decoded['files'] is! List) {
        throw const FormatException('Invalid Windows catalog identity');
      }
      final entries = decoded['files'] as List;
      if (entries.isEmpty || entries.length > 8192) {
        throw const FormatException('Invalid Windows catalog entries');
      }
      final files = <String, WindowsUpdateCatalogFile>{};
      final folded = <String>{};
      final roles = <String>{};
      for (final item in entries) {
        if (item is! Map<String, dynamic> ||
            !_keys(item, const {'path', 'role', 'size', 'sha256'})) {
          throw const FormatException('Invalid Windows catalog file');
        }
        final name = item['path'];
        final role = item['role'];
        final size = item['size'];
        final hash = item['sha256'];
        if (name is! String ||
            role is! String ||
            size is! int ||
            size < 0 ||
            size > 2147483648 ||
            hash is! String ||
            !_hashPattern.hasMatch(hash)) {
          throw const FormatException('Invalid Windows catalog entry');
        }
        _safeName(name);
        if (!folded.add(name.toLowerCase()) ||
            {'app-trust.json', 'app-trust.sig'}.contains(name.toLowerCase())) {
          throw const FormatException('Duplicate Windows catalog entry');
        }
        final expectedRole = switch (name) {
          'equis.exe' => 'app',
          'equis-update-helper.exe' => 'coordinator',
          _ => 'data',
        };
        if (role != expectedRole ||
            (role != 'data' && (size == 0 || !roles.add(role)))) {
          throw const FormatException('Invalid Windows catalog role');
        }
        files[name] = WindowsUpdateCatalogFile(name, role, size, hash);
      }
      if (!roles.containsAll({'app', 'coordinator'}) ||
          roles.length != 2 ||
          !files.containsKey('app-files.json') ||
          !files.containsKey('app-version.json')) {
        throw const FormatException('Incomplete Windows catalog');
      }
      for (final entry in files.values) {
        final file = await locked(entry.path);
        if (!file.verifySha256(entry.sha256, entry.size)) {
          throw FormatException('Windows catalog hash mismatch: ${entry.path}');
        }
      }
      final inventory = jsonDecode(
        await File(p.join(directory, 'app-files.json')).readAsString(),
      );
      final expectedNames = [...files.keys, 'app-trust.json', 'app-trust.sig']
        ..sort();
      if (inventory is! List || inventory.length != expectedNames.length) {
        throw const FormatException('Windows inventory count mismatch');
      }
      for (var i = 0; i < expectedNames.length; i++) {
        if (inventory[i] != expectedNames[i]) {
          throw const FormatException('Windows inventory mismatch');
        }
      }
      final metadata = jsonDecode(
        await File(p.join(directory, 'app-version.json')).readAsString(),
      );
      if (metadata is! Map<String, dynamic> ||
          !_keys(metadata, const {
            'version',
            'build',
            'applicationId',
            'innoAppId',
            'updateTestMode',
          }) ||
          metadata['version'] != decoded['version'] ||
          metadata['build'] != decoded['build'] ||
          metadata['applicationId'] != windowsUpdateApplicationId ||
          metadata['innoAppId'] != windowsUpdateInnoAppId ||
          metadata['updateTestMode'] != windowsUpdateTestMode) {
        throw const FormatException('Windows version metadata mismatch');
      }
      for (final lock in locks) {
        lock.revalidate();
      }
      return WindowsUpdateCatalog._(
        locks,
        directory: directory,
        version: decoded['version'] as String,
        build: decoded['build'] as int,
        rawHash: _hex((await Sha256().hash(raw)).bytes),
        helperSha256: files['equis-update-helper.exe']!.sha256,
        files: Map.unmodifiable(files),
      );
    } catch (_) {
      for (final lock in locks.reversed) {
        lock.close();
      }
      rethrow;
    }
  }

  Future<void> revalidate() async {
    if (_closed) throw StateError('Windows catalog was closed');
    for (final lock in _locks) {
      lock.revalidate();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final lock in _locks.reversed) {
      lock.close();
    }
  }
}

final class WindowsUpdateCatalogFile {
  const WindowsUpdateCatalogFile(this.path, this.role, this.size, this.sha256);
  final String path, role, sha256;
  final int size;
}

bool _keys(Map<String, dynamic> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

bool _version(String value) {
  final match = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  ).firstMatch(value);
  return match != null &&
      utf8.encode(value).length <= 32 &&
      match
          .groups([1, 2, 3])
          .every((part) => BigInt.parse(part!) <= BigInt.from(2147483647));
}

Future<void> _rejectLinks(String root, String path) async {
  var current = path;
  while (true) {
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Linked Windows catalog path');
    }
    if (p.equals(current, root)) return;
    final parent = p.dirname(current);
    if (parent == current) throw const FormatException('Catalog path escaped');
    current = parent;
  }
}

void _safeName(String name) {
  if (name.isEmpty ||
      utf8.encode(name).length > 1024 ||
      name.contains('\\') ||
      name.startsWith('/') ||
      name.endsWith('/')) {
    throw const FormatException('Unsafe Windows catalog path');
  }
  final segments = name.split('/');
  if (segments.length > 32) {
    throw const FormatException('Unsafe Windows catalog depth');
  }
  final reserved = RegExp(
    r'^(con|prn|aux|nul|conin\$|conout\$|com[1-9¹²³]|lpt[1-9¹²³])$',
    caseSensitive: false,
  );
  for (final segment in segments) {
    final stem = segment.split('.').first.replaceFirst(RegExp(r'[ .]+$'), '');
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.length > 255 ||
        segment.endsWith(' ') ||
        segment.endsWith('.') ||
        reserved.hasMatch(stem) ||
        segment.contains(RegExp(r'[\\:*?"<>|\x00-\x1f\x7f]'))) {
      throw const FormatException('Unsafe Windows catalog segment');
    }
  }
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
