import 'dart:convert';
import 'dart:io';

import 'package:equis/infrastructure/updates/app_update_service.dart';
import 'package:equis/infrastructure/updates/windows_update_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final helperPath = Platform.environment['EQUIS_UPDATE_VALIDATION_HELPER'];

  test(
    'a lease loser cannot replace an existing installation journal',
    () async {
      final helper = File(helperPath!);
      expect(await helper.exists(), isTrue);
      final root = await Directory.systemTemp.createTemp(
        'equis update lease contention with spaces ',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final target = await Directory(
        p.join(root.path, 'installed target'),
      ).create();
      const transaction = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final mixedCacheInput = '${root.path}/update cache';
      final service = AppUpdateService(
        directory: Directory(mixedCacheInput),
        preferences: preferences,
        platform: 'windows-installed',
      );
      addTearDown(service.dispose);
      expect(service.directory.path, p.normalize(mixedCacheInput));
      expect(service.directory.path, isNot(mixedCacheInput));
      await service.directory.create(recursive: true);
      final cache = service.directory;
      final attempt = Directory(p.join(cache.path, 'installed-$transaction'));
      await attempt.create();
      final request = File(p.join(attempt.path, 'request.json'));
      final owner = WindowsUpdateProcess.current();
      final originalJournal = const {
        'state': 'preflight_failed',
        'target': 'preserve this previous diagnostic',
        'code': 'previous_attempt',
      };
      final journal = File(p.join(cache.path, 'installation.json'));
      final lock = WindowsUpdateMutex.acquire(target.path);
      try {
        await journal.writeAsString(jsonEncode(originalJournal), flush: true);
        await request.writeAsString(
          jsonEncode({
            'format': 2,
            'transaction': transaction,
            // Match WindowsInstalledUpdateSession: request.cache is taken from
            // the normalized AppUpdateService directory, not the input path.
            'cache': service.directory.absolute.path,
            'target': target.path,
            'hive': 'HKCU',
            'sid': owner.sid,
            'appPid': owner.pid,
            'appCreatedFiletime': owner.createdFiletime.toString(),
            'oldVersion': '1.2.0',
            'oldBuild': 12,
            'newVersion': '1.2.1',
            'newBuild': 13,
            'requiresElevation': false,
          }),
          flush: true,
        );

        final result = await Process.run(helper.path, [
          'installed-v2',
          request.path,
        ]);
        expect(result.exitCode, 1);
        final messages = result.stdout
            .toString()
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(messages, hasLength(1));
        expect(messages.single['type'], 'ERROR');
        expect(messages.single['code'], 'update_already_running');
        expect(jsonDecode(await journal.readAsString()), originalJournal);
        expect(await File('${journal.path}.new').exists(), isFalse);

        final invalidRequestJson = jsonEncode({
          'format': 2,
          'transaction': transaction,
          // Deliberately retain the mixed raw input. The helper must reject it
          // before any journal or cache write instead of repairing the path.
          'cache': mixedCacheInput,
          'target': target.path,
          'hive': 'HKCU',
          'sid': owner.sid,
          'appPid': owner.pid,
          'appCreatedFiletime': owner.createdFiletime.toString(),
          'oldVersion': '1.2.0',
          'oldBuild': 12,
          'newVersion': '1.2.1',
          'newBuild': 13,
          'requiresElevation': false,
        });
        await request.writeAsString(invalidRequestJson, flush: true);
        final entriesBefore = await _relativeEntries(cache);

        final malformedResult = await Process.run(helper.path, [
          'installed-v2',
          request.path,
        ]);
        expect(malformedResult.exitCode, 1);
        final malformedMessages = malformedResult.stdout
            .toString()
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(malformedMessages, hasLength(1));
        expect(malformedMessages.single['type'], 'ERROR');
        expect(malformedMessages.single['code'], 'invalid_request_path');
        expect(await _relativeEntries(cache), entriesBefore);
        expect(await request.readAsString(), invalidRequestJson);
        expect(jsonDecode(await journal.readAsString()), originalJournal);
        expect(await File('${journal.path}.new').exists(), isFalse);
      } finally {
        lock.close();
        owner.close();
      }
    },
    skip: !Platform.isWindows || helperPath == null || helperPath.isEmpty,
  );
}

Future<List<String>> _relativeEntries(Directory root) async {
  final entries = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    entries.add(p.relative(entity.path, from: root.path));
  }
  entries.sort();
  return entries;
}
