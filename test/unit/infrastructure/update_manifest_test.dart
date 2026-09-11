import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/update_helper.dart' as helper;

void main() {
  test(
    'interrupted replacement restores app files and preserves extras',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'equis recovery spaces ',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = await Directory('${root.path}/cache').create();
      final target = await Directory('${root.path}/app').create();
      final backup = await Directory('${cache.path}/previous-7').create();
      await File('${target.path}/equis.exe').writeAsString('partial');
      await File('${target.path}/notes.txt').writeAsString('personal');
      await File('${target.path}/new.dll').writeAsString('new');
      await File('${backup.path}/equis.exe').writeAsString('old');
      final journal = File('${cache.path}/installation.json');
      await journal.writeAsString(
        jsonEncode({
          'state': 'replacing',
          'target': target.path,
          'backup': backup.path,
          'files': ['equis.exe', 'new.dll'],
          'existed': ['equis.exe'],
        }),
      );
      await helper.recoverInterrupted(cache, target);
      expect(await File('${target.path}/equis.exe').readAsString(), 'old');
      expect(await File('${target.path}/notes.txt').readAsString(), 'personal');
      expect(await File('${target.path}/new.dll').exists(), false);
      await File('${target.path}/equis.exe').writeAsString('new launched');
      await journal.writeAsString(
        jsonEncode({
          'state': 'launching',
          'target': target.path,
          'backup': backup.path,
          'files': ['equis.exe'],
          'existed': ['equis.exe'],
        }),
      );
      await helper.recoverInterrupted(cache, target);
      expect(
        await File('${target.path}/equis.exe').readAsString(),
        'new launched',
      );
    },
  );
  test('public versions ignore internal builds; downgrade is rejected', () {
    expect(
      const UpdateVersion(
        '1.0.0',
        7,
      ).compareTo(const UpdateVersion('1.0.0', 6)),
      0,
    );
    expect(
      const UpdateVersion(
        '1.0.0',
        5,
      ).compareTo(const UpdateVersion('1.0.0', 6)),
      0,
    );
    expect(
      () => const UpdateVersion(
        '1.0.1-beta',
        8,
      ).compareTo(const UpdateVersion('1.0.0', 6)),
      throwsFormatException,
    );
  });
  test('public version ordering rejects downgrades regardless of build', () {
    expect(
      const UpdateVersion(
        '1.0.1',
        7,
      ).compareTo(const UpdateVersion('1.0.0', 99)),
      greaterThan(0),
    );
    expect(
      const UpdateVersion(
        '1.0.0',
        99,
      ).compareTo(const UpdateVersion('1.0.1', 7)),
      lessThan(0),
    );
    expect(const UpdateVersion('1.0.0', 99).toString(), '1.0.0');
  });
  test('only an unmodified signed manifest is trusted', () async {
    final key = await Ed25519().newKeyPair();
    final public = (await key.extractPublicKey()).bytes;
    final bytes = utf8.encode(
      jsonEncode({
        'format': 1,
        'applicationId': 'app.saga.equis',
        'version': '1.0.1',
        'build': 7,
        'tag': 'v1.0.1',
        'packages': [
          {
            'platform': 'android',
            'file': 'Equis-Android-1.0.1.apk',
            'size': 12,
            'sha256': 'a' * 64,
          },
        ],
      }),
    );
    final sig = (await Ed25519().sign(bytes, keyPair: key)).bytes;
    expect((await UpdateManifest.verify(bytes, sig, public)).version.build, 7);
    for (final replacement in [
      {'applicationId': 'app.equis.equis'},
      {'tag': 'v1.0.1+7'},
    ]) {
      final altered = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      altered.addAll(replacement);
      final encoded = utf8.encode(jsonEncode(altered));
      final signed = (await Ed25519().sign(encoded, keyPair: key)).bytes;
      await expectLater(
        UpdateManifest.verify(encoded, signed, public),
        throwsFormatException,
      );
    }
    await expectLater(
      UpdateManifest.verify([...bytes, 32], sig, public),
      throwsFormatException,
    );
    await expectLater(
      UpdateManifest.verify(bytes, List.filled(64, 0), public),
      throwsFormatException,
    );
  });
  test('incomplete and corrupted packages are rejected', () async {
    final directory = await Directory.systemTemp.createTemp(
      'equis-update-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File(
      '${directory.path}/package.apk',
    ).writeAsBytes([1, 2, 3]);
    await expectLater(
      UpdatePackage('android', 'package.apk', 4, 'a' * 64).validate(file),
      throwsFormatException,
    );
    await expectLater(
      UpdatePackage('android', 'package.apk', 3, 'a' * 64).validate(file),
      throwsFormatException,
    );
  });
  test(
    'portable paths reject traversal, ADS, absolute paths and device names',
    () {
      for (final name in [
        '../vault',
        '/vault',
        'C:\\vault',
        'data/../vault',
        'equis.exe:stream',
        'NUL.txt',
        'dir/file.',
      ]) {
        expect(
          () => helper.safeName(name),
          throwsFormatException,
          reason: name,
        );
      }
      expect(
        helper.safeName('data/flutter_assets/AssetManifest.bin'),
        isNotEmpty,
      );
    },
  );
}
