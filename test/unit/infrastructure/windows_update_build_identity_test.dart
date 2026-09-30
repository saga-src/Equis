import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Assert-ProductionWindowsUpdateBuild', () {
    late _BuildIdentityFixture fixture;

    setUp(() async {
      fixture = await _BuildIdentityFixture.create();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('rejects a missing generated CMake configuration', () async {
      await fixture.prepareExecutable();

      final result = await fixture.invoke();

      expect(result.exitCode, 17, reason: result.description);
    }, skip: !Platform.isWindows);

    test(
      'rejects an executable older than generated build configuration',
      () async {
        await fixture.prepareExecutable();
        await fixture.writeConfiguration('FLUTTER_TARGET_PLATFORM=windows-x64');
        await fixture.setTimes(
          executable: DateTime.utc(2025),
          configuration: DateTime.utc(2026),
        );

        final result = await fixture.invoke();

        expect(result.exitCode, 17, reason: result.description);
      },
      skip: !Platform.isWindows,
    );

    for (final definition in [
      'EQUIS_UPDATE_TEST_MODE=true',
      'EQUIS_UPDATE_TEST_PUBLIC_KEY=fixture-public-key',
      'EQUIS_UPDATE_TEST_ROOT=C:\\fixture\\test-root',
      'EQUIS_WINDOWS_INSTALLED_UPDATE_ENABLED=true',
    ]) {
      test(
        'rejects production build definition $definition',
        () async {
          await fixture.prepareExecutable();
          await fixture.writeConfiguration(
            _configuration(definitions: [definition]),
          );
          await fixture.setTimes(
            executable: DateTime.utc(2026),
            configuration: DateTime.utc(2026),
          );

          final result = await fixture.invoke();

          expect(result.exitCode, 17, reason: result.description);
          expect(result.stdout, isNot(contains(definition)));
          expect(result.stderr, isNot(contains(definition)));
        },
        skip: !Platform.isWindows,
      );
    }

    test('allows ordinary production definitions', () async {
      await fixture.prepareExecutable();
      await fixture.writeConfiguration(
        _configuration(
          definitions: const [
            'FLUTTER_TARGET_PLATFORM=windows-x64',
            'SOME_OTHER_FEATURE=true',
          ],
        ),
      );
      await fixture.setTimes(
        executable: DateTime.utc(2026),
        configuration: DateTime.utc(2026),
      );

      final result = await fixture.invoke();

      expect(result.exitCode, 0, reason: result.description);
    }, skip: !Platform.isWindows);

    test(
      'allows a fresh production configuration without DART_DEFINES',
      () async {
        await fixture.prepareExecutable();
        await fixture.writeConfiguration('FLUTTER_TARGET_PLATFORM=windows-x64');
        await fixture.setTimes(
          executable: DateTime.utc(2026),
          configuration: DateTime.utc(2026),
        );

        final result = await fixture.invoke();

        expect(result.exitCode, 0, reason: result.description);
      },
      skip: !Platform.isWindows,
    );
  });
}

String _configuration({required List<String> definitions}) {
  final encoded = definitions.map((value) => base64.encode(utf8.encode(value)));
  return '  "DART_DEFINES=${encoded.join(',')}"\r\n';
}

final class _BuildIdentityFixture {
  _BuildIdentityFixture(this.root, this.scriptPath, this.harness);

  final Directory root;
  final String scriptPath;
  final File harness;

  String get projectRoot => root.path;
  String get executable => p.join(root.path, 'build', 'fake equis.exe');
  String get configuration => p.join(
    root.path,
    'windows',
    'flutter',
    'ephemeral',
    'generated_config.cmake',
  );

  static Future<_BuildIdentityFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'equis Windows build identity with spaces ',
    );
    final scriptPath = p.join(
      Directory.current.path,
      'tool',
      'windows_update_build_identity.ps1',
    );
    final harness = File(p.join(root.path, 'invoke identity check.ps1'));
    await harness.writeAsString('''
param([string]\$Library, [string]\$ProjectRoot, [string]\$Executable)
\$ErrorActionPreference = 'Stop'
. \$Library
try {
  Assert-ProductionWindowsUpdateBuild -ProjectRoot \$ProjectRoot -Executable \$Executable
  exit 0
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit 17
}
''');
    return _BuildIdentityFixture(root, scriptPath, harness);
  }

  Future<void> prepareExecutable() async {
    final file = File(executable);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([0x45, 0x51, 0x55, 0x49, 0x53]);
  }

  Future<void> writeConfiguration(String contents) async {
    final file = File(configuration);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  }

  Future<void> setTimes({
    required DateTime executable,
    required DateTime configuration,
  }) async {
    await File(this.executable).setLastModified(executable);
    await File(this.configuration).setLastModified(configuration);
  }

  Future<ProcessResult> invoke() => Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    harness.path,
    scriptPath,
    projectRoot,
    executable,
  ]);

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

extension on ProcessResult {
  String get description => 'exit=$exitCode stdout=$stdout stderr=$stderr';
}
