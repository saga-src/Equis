import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/updates/windows_update_catalog.dart';
import 'package:equis/infrastructure/updates/windows_update_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _domain = 'Equis.WindowsFileCatalog\u0000v1\u0000';

void main() {
  group('WindowsUpdateCatalog', () {
    test(
      'accepts an independently signed complete format 2 catalog',
      () async {
        final fixture = await _SignedCatalog.create();
        addTearDown(fixture.dispose);
        final catalog = await _inspect(fixture);
        try {
          expect(catalog.version, '1.2.1');
          expect(catalog.build, 13);
          expect(
            catalog.helperPath,
            p.join(fixture.root.path, 'equis-update-helper.exe'),
          );
          expect(
            catalog.helperSha256,
            fixture.hashes['equis-update-helper.exe'],
          );
          expect(
            catalog.files.keys,
            containsAll(['equis.exe', 'app-version.json']),
          );
          await catalog.revalidate();

          // The returned catalog retains no-write/no-delete handles until close.
          final app = File(p.join(fixture.root.path, 'equis.exe'));
          await expectLater(
            app.rename('${app.path}.renamed'),
            throwsA(anything),
          );
        } finally {
          await catalog.close();
        }
        final app = File(p.join(fixture.root.path, 'equis.exe'));
        await app.rename('${app.path}.renamed');
        expect(await File('${app.path}.renamed').exists(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'rejects a modified signature before accepting catalog metadata',
      () async {
        final fixture = await _SignedCatalog.create();
        addTearDown(fixture.dispose);
        final signature = File(p.join(fixture.root.path, 'app-trust.sig'));
        final bytes = await signature.readAsBytes();
        bytes[0] ^= 1;
        await signature.writeAsBytes(bytes, flush: true);

        await expectLater(_inspect(fixture), throwsA(isA<FormatException>()));
      },
      skip: !Platform.isWindows,
    );

    test(
      'rejects signed catalogs with unsafe paths and stale inventories',
      () async {
        final unsafe = await _SignedCatalog.create(
          extraEntry: {
            'path': '../outside.bin',
            'role': 'data',
            'size': 1,
            'sha256': List.filled(64, '0').join(),
          },
        );
        addTearDown(unsafe.dispose);
        await expectLater(_inspect(unsafe), throwsA(isA<FormatException>()));

        final staleInventory = await _SignedCatalog.create(
          inventoryOverride: const ['app-files.json'],
        );
        addTearDown(staleInventory.dispose);
        await expectLater(
          _inspect(staleInventory),
          throwsA(isA<FormatException>()),
        );

        final divergentMetadata = await _SignedCatalog.create(
          metadataVersion: '1.2.0',
        );
        addTearDown(divergentMetadata.dispose);
        await expectLater(
          _inspect(divergentMetadata),
          throwsA(isA<FormatException>()),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'rejects missing, truncated, and hash-mismatched catalog files',
      () async {
        final missing = await _SignedCatalog.create();
        addTearDown(missing.dispose);
        await File(
          p.join(missing.root.path, 'equis-update-helper.exe'),
        ).delete();
        await expectLater(_inspect(missing), throwsA(anything));

        final changed = await _SignedCatalog.create();
        addTearDown(changed.dispose);
        await File(p.join(changed.root.path, 'equis.exe')).writeAsBytes([0, 0]);
        await expectLater(_inspect(changed), throwsA(isA<FormatException>()));

        final truncated = await _SignedCatalog.create();
        addTearDown(truncated.dispose);
        await File(
          p.join(truncated.root.path, 'app-trust.sig'),
        ).writeAsBytes([1]);
        await expectLater(_inspect(truncated), throwsA(isA<FormatException>()));
      },
      skip: !Platform.isWindows,
    );
  });
}

Future<WindowsUpdateCatalog> _inspect(_SignedCatalog fixture) =>
    WindowsUpdateCatalog.inspect(
      fixture.root.path,
      verificationKey: fixture.publicKey,
    );

final class _SignedCatalog {
  _SignedCatalog(this.root, this.publicKey, this.hashes);

  final Directory root;
  final String publicKey;
  final Map<String, String> hashes;

  static Future<_SignedCatalog> create({
    Map<String, Object>? extraEntry,
    List<String>? inventoryOverride,
    String metadataVersion = '1.2.1',
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'equis signed Windows catalog with spaces ',
    );
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = base64Encode((await keyPair.extractPublicKey()).bytes);
    final contents = <String, List<int>>{
      'equis.exe': [1, 2, 3, 4],
      'equis-update-helper.exe': [5, 6, 7, 8],
      'app-version.json': utf8.encode(
        jsonEncode({
          'version': metadataVersion,
          'build': 13,
          'applicationId': windowsUpdateApplicationId,
          'innoAppId': windowsUpdateInnoAppId,
          'updateTestMode': windowsUpdateTestMode,
        }),
      ),
    };
    final hashes = <String, String>{};
    for (final entry in contents.entries) {
      await File(p.join(root.path, entry.key)).writeAsBytes(entry.value);
      hashes[entry.key] = _hex((await Sha256().hash(entry.value)).bytes);
    }

    final fileEntries = <Map<String, Object>>[
      for (final entry in contents.entries)
        {
          'path': entry.key,
          'role': switch (entry.key) {
            'equis.exe' => 'app',
            'equis-update-helper.exe' => 'coordinator',
            _ => 'data',
          },
          'size': entry.value.length,
          'sha256': hashes[entry.key]!,
        },
    ];
    if (extraEntry != null) fileEntries.add(extraEntry);
    final listedFiles = fileEntries
        .map((entry) => entry['path'] as String)
        .toList();
    final inventory =
        inventoryOverride ??
        [...listedFiles, 'app-files.json', 'app-trust.json', 'app-trust.sig'];
    if (inventoryOverride == null) inventory.sort();
    await File(
      p.join(root.path, 'app-files.json'),
    ).writeAsString(jsonEncode(inventory), flush: true);
    contents['app-files.json'] = await File(
      p.join(root.path, 'app-files.json'),
    ).readAsBytes();
    hashes['app-files.json'] = _hex(
      (await Sha256().hash(contents['app-files.json']!)).bytes,
    );
    fileEntries.add({
      'path': 'app-files.json',
      'role': 'data',
      'size': contents['app-files.json']!.length,
      'sha256': hashes['app-files.json']!,
    });
    // The catalog inventory covers itself, metadata, both executable files,
    // and the two trust sidecars. Sidecar bytes are outside its file list.
    final raw = utf8.encode(
      jsonEncode({
        'kind': 'equis-windows-file-catalog',
        'format': 2,
        'applicationId': windowsUpdateApplicationId,
        'innoAppId': windowsUpdateInnoAppId,
        'architecture': 'x64',
        'version': '1.2.1',
        'build': 13,
        'files': fileEntries,
      }),
    );
    final signature = await Ed25519().sign([
      ...ascii.encode(_domain),
      ...raw,
    ], keyPair: keyPair);
    await File(p.join(root.path, 'app-trust.json')).writeAsBytes(raw);
    await File(
      p.join(root.path, 'app-trust.sig'),
    ).writeAsBytes(signature.bytes);
    return _SignedCatalog(root, publicKey, hashes);
  }

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
