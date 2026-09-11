import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/update_helper.dart' as helper;

void main() {
  test(
    'portable update verifies staging and preserves extras in paths with spaces',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'equis portable test ',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = await Directory('${root.path}/updates').create();
      final target = await Directory('${root.path}/portable app').create();
      await File(
        '${target.path}/app-version.json',
      ).writeAsString(jsonEncode({'version': '1.0.0', 'build': 6}));
      await File('${target.path}/equis.exe').writeAsString('old binary');
      await File(
        '${target.path}/personal-notes.txt',
      ).writeAsString('preserve me');
      final archive = Archive();
      final contents = {
        'equis.exe': utf8.encode('new binary'),
        'app-version.json': utf8.encode(
          jsonEncode({'version': '1.0.1', 'build': 7}),
        ),
        'app-files.json': utf8.encode(
          jsonEncode(['equis.exe', 'app-version.json']),
        ),
      };
      for (final entry in contents.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final bytes = ZipEncoder().encode(archive);
      await File('${cache.path}/update.zip').writeAsBytes(bytes);
      final hash = (await Sha256().hash(
        bytes,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final manifest = utf8.encode(
        jsonEncode({
          'format': 1,
          'applicationId': 'app.saga.equis',
          'version': '1.0.1',
          'build': 7,
          'tag': 'v1.0.1',
          'packages': [
            {
              'platform': 'windows-portable',
              'file': 'update.zip',
              'size': bytes.length,
              'sha256': hash,
            },
          ],
        }),
      );
      final key = await Ed25519().newKeyPair();
      final public = base64Encode((await key.extractPublicKey()).bytes);
      await File('${cache.path}/manifest.json').writeAsBytes(manifest);
      await File('${cache.path}/manifest.sig').writeAsString(
        base64Encode((await Ed25519().sign(manifest, keyPair: key)).bytes),
      );
      List<String> arguments(String command) => [
        command,
        cache.path,
        target.path,
        'windows-portable',
        '987654321',
      ];
      expect(
        await helper.runUpdate(arguments('prepare'), publicKey: public),
        true,
      );
      await File('${cache.path}/stage-7/equis.exe').writeAsString('tampered');
      expect(
        await helper.runUpdate(
          arguments('apply'),
          publicKey: public,
          launch: (_) async {},
        ),
        false,
      );
      expect(
        await File('${target.path}/equis.exe').readAsString(),
        'old binary',
      );
      expect(
        await helper.runUpdate(arguments('prepare'), publicKey: public),
        true,
      );
      var launched = false;
      final locked = await File(
        '${target.path}/equis.exe',
      ).open(mode: FileMode.append);
      await locked.lock(FileLock.exclusive);
      try {
        expect(
          await helper.runUpdate(
            arguments('apply'),
            publicKey: public,
            launch: (_) async {},
          ),
          false,
          reason: 'A locked app file must not permit installation',
        );
      } finally {
        await locked.unlock();
        await locked.close();
      }
      await helper.recoverInterrupted(cache, target);
      expect(
        await File('${target.path}/equis.exe').readAsString(),
        'old binary',
      );
      expect(
        await helper.runUpdate(arguments('prepare'), publicKey: public),
        true,
      );
      expect(
        await helper.runUpdate(
          arguments('apply'),
          publicKey: public,
          launch: (_) async {
            launched = true;
          },
        ),
        true,
      );
      expect(launched, true);
      expect(
        await File('${target.path}/equis.exe').readAsString(),
        'new binary',
      );
      expect(
        await File('${target.path}/personal-notes.txt').readAsString(),
        'preserve me',
      );
      expect(
        await File('${cache.path}/previous-7/equis.exe').readAsString(),
        'old binary',
      );
      expect(
        await helper.runUpdate(arguments('prepare'), publicKey: public),
        false,
        reason: 'Installing the same build or a downgrade is forbidden',
      );
    },
    skip: !Platform.isWindows,
  );
}
