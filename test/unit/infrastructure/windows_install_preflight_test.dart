import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/updates/update_manifest.dart';
import 'package:equis/infrastructure/updates/windows_install_preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WindowsInstalledPreflight', () {
    late Directory root;
    late Directory target;
    late Directory cache;
    late File executable;
    late File payload;
    late UpdatePackage package;
    late _FakeWindowsInstallSystem system;

    const runningVersion = UpdateVersion('1.0.0', 6);
    const updateVersion = UpdateVersion('1.0.1', 7);
    const sid = 'S-1-5-21-1000-2000-3000-1001';
    final payloadBytes = <int>[1, 2, 3];

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'equis windows preflight with spaces ',
      );
      target = await Directory(
        p.join(root.path, 'Program Files', 'Equis'),
      ).create(recursive: true);
      cache = await Directory(p.join(root.path, 'update cache')).create();

      executable = File(p.join(target.path, 'equis.exe'));
      await executable.writeAsBytes([0]);
      await _writeInstalledVersion(target, runningVersion);

      payload = File(p.join(cache.path, 'Equis-Windows-1.0.1-setup.exe'));
      await payload.writeAsBytes(payloadBytes);
      package = await _package(payloadBytes);

      system = _FakeWindowsInstallSystem(
        locations: {'HKCU': target.path},
        sid: sid,
      );
      system.localInnoMarker = true;
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    Future<WindowsInstallIdentity> inspect({
      String? targetPath,
      String? executablePath,
      UpdateVersion? installedVersion,
      UpdateVersion? update,
      UpdatePackage? updatePackage,
      File? updatePayload,
    }) {
      return WindowsInstalledPreflight(system: system).inspect(
        target: targetPath ?? target.path,
        executable: executablePath ?? executable.path,
        runningVersion: installedVersion ?? runningVersion,
        updateVersion: update ?? updateVersion,
        package: updatePackage ?? package,
        payload: updatePayload ?? payload,
      );
    }

    test(
      'accepts writable HKCU and preserves canonical paths with spaces',
      () async {
        system.writable = true;

        final identity = await inspect();

        expect(target.path, contains(' '));
        expect(identity.hive, 'HKCU');
        expect(identity.target, await target.resolveSymbolicLinks());
        expect(identity.executable, await executable.resolveSymbolicLinks());
        expect(identity.sid, sid);
        expect(identity.installedVersion.version, runningVersion.version);
        expect(identity.installedVersion.build, runningVersion.build);
        expect(identity.writable, isTrue);
        expect(identity.requiresElevation, isFalse);
        expect(system.checkedWritableDirectory, identity.target);
      },
    );

    test(
      'protected HKCU requires elevation even for the current user',
      () async {
        system.writable = false;

        final identity = await inspect();

        expect(identity.hive, 'HKCU');
        expect(identity.sid, sid);
        expect(identity.writable, isFalse);
        expect(identity.requiresElevation, isTrue);
      },
    );

    test('HKLM requires elevation even when the target is writable', () async {
      system.locations
        ..clear()
        ..['HKLM'] = target.path;
      system.writable = true;

      final identity = await inspect();

      expect(identity.hive, 'HKLM');
      expect(identity.writable, isTrue);
      expect(identity.requiresElevation, isTrue);
    });

    test('rejects a missing registration', () async {
      system.locations.clear();

      await _expectPreflightCode(inspect(), 'registration_missing');
    });

    test('rejects registrations in both hives as ambiguous', () async {
      system.locations['HKLM'] = target.path;

      await _expectPreflightCode(inspect(), 'registration_ambiguous');
    });

    test(
      'rejects a registered target without local Inno uninstall files',
      () async {
        system.localInnoMarker = false;

        await _expectPreflightCode(inspect(), 'uninstaller_missing');
      },
    );

    test(
      'propagates registry read errors instead of treating them as absence',
      () async {
        system.installLocationError = const WindowsUpdatePreflightException(
          'registry_unavailable',
        );

        await _expectPreflightCode(inspect(), 'registry_unavailable');
      },
    );

    test(
      'rejects a registered directory that differs from the executable target',
      () async {
        final other = await Directory(
          p.join(root.path, 'Other Equis'),
        ).create();
        system.locations['HKCU'] = other.path;

        await _expectPreflightCode(inspect(), 'registration_mismatch');
      },
    );

    test(
      'rejects an executable outside the registered installation directory',
      () async {
        final other = await Directory(
          p.join(root.path, 'Other Equis'),
        ).create();
        final otherExecutable = File(p.join(other.path, 'equis.exe'));
        await otherExecutable.writeAsBytes([0]);

        await _expectPreflightCode(
          inspect(executablePath: otherExecutable.path),
          'executable_mismatch',
        );
      },
    );

    test(
      'rejects a running version or build that differs from app-version.json',
      () async {
        await _expectPreflightCode(
          inspect(installedVersion: const UpdateVersion('1.0.0', 5)),
          'installed_version_mismatch',
        );
        await _expectPreflightCode(
          inspect(installedVersion: const UpdateVersion('1.0.1', 6)),
          'installed_version_mismatch',
        );
      },
    );

    test(
      'rejects an update that is not newer than the installed version',
      () async {
        await _expectPreflightCode(
          inspect(update: const UpdateVersion('1.0.0', 99)),
          'installed_version_mismatch',
        );
      },
    );

    test('rejects a package for the portable platform', () async {
      final portable = UpdatePackage(
        'windows-portable',
        'Equis-Windows-1.0.1.zip',
        package.size,
        package.sha256,
      );

      await _expectPreflightCode(
        inspect(updatePackage: portable),
        'package_platform_mismatch',
      );
    });

    test(
      'rejects a payload whose bytes changed after its hash was recorded',
      () async {
        await payload.writeAsBytes([3, 2, 1]);

        await expectLater(
          inspect(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Package hash mismatch',
            ),
          ),
        );
      },
    );
  });

  group('classifyWindowsPlatform', () {
    late Directory root;
    late Directory target;
    late File executable;
    late _FakeWindowsInstallSystem system;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'equis platform classification with spaces ',
      );
      target = await Directory(
        p.join(root.path, 'Program Files', 'Equis'),
      ).create(recursive: true);
      executable = File(p.join(target.path, 'equis.exe'));
      await executable.writeAsBytes([0]);
      system = _FakeWindowsInstallSystem(locations: {});
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    Future<String> classify() =>
        classifyWindowsPlatform(system: system, executable: executable.path);

    test(
      'classifies a matching registration and local Inno marker as installed',
      () async {
        system.locations['HKCU'] = target.path;
        system.localInnoMarker = true;

        expect(await classify(), 'windows-installed');
      },
    );

    test('requires a registration when a local Inno marker exists', () async {
      system.localInnoMarker = true;

      await _expectPreflightCode(classify(), 'registration_missing');
    });

    test('rejects a local Inno marker registered to another target', () async {
      final other = await Directory(p.join(root.path, 'Other Equis')).create();
      system.locations['HKCU'] = other.path;
      system.localInnoMarker = true;

      await _expectPreflightCode(classify(), 'registration_mismatch');
    });

    test(
      'rejects a matching registration without a local Inno marker',
      () async {
        system.locations['HKLM'] = target.path;

        await _expectPreflightCode(classify(), 'uninstaller_missing');
      },
    );

    test(
      'keeps a portable copy portable when another install is registered',
      () async {
        final other = await Directory(
          p.join(root.path, 'Other Equis'),
        ).create();
        system.locations['HKCU'] = other.path;

        expect(await classify(), 'windows-portable');
      },
    );

    test(
      'keeps a portable copy when another installation path no longer exists',
      () async {
        system.locations['HKCU'] = p.join(root.path, 'Removed Equis');

        expect(await classify(), 'windows-portable');
      },
    );

    test(
      'does not ignore access errors while resolving another registration',
      () async {
        final other = await Directory(
          p.join(root.path, 'Other Equis'),
        ).create();
        system.locations['HKCU'] = other.path;
        system.canonicalDirectoryErrorCodes[other.path] = 5;

        await expectLater(
          classify(),
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.osError?.errorCode,
              'osError.errorCode',
              5,
            ),
          ),
        );
      },
    );

    test(
      'does not ignore a missing other registration when a local marker exists',
      () async {
        system.locations['HKCU'] = p.join(root.path, 'Removed Equis');
        system.localInnoMarker = true;

        await expectLater(classify(), throwsA(isA<FileSystemException>()));
      },
    );

    test(
      'keeps an unregistered copy portable when no install is registered',
      () async {
        expect(await classify(), 'windows-portable');
      },
    );

    test('rejects registrations in both hives as ambiguous', () async {
      system.locations
        ..['HKCU'] = target.path
        ..['HKLM'] = target.path;
      system.localInnoMarker = true;

      await _expectPreflightCode(classify(), 'registration_ambiguous');
    });

    test(
      'does not treat a registry read error as an absent registration',
      () async {
        system.installLocationError = const WindowsUpdatePreflightException(
          'registry_unavailable',
        );

        await _expectPreflightCode(classify(), 'registry_unavailable');
      },
    );
  });

  group('NativeWindowsInstallSystem.hasLocalInnoMarker', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'equis Inno marker paths with spaces ',
      );
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('recognizes either default Inno uninstall file', () async {
      const system = NativeWindowsInstallSystem();
      final dataFile = File(p.join(root.path, 'unins000.dat'));
      await dataFile.writeAsBytes([0]);
      expect(await system.hasLocalInnoMarker(root.path), isTrue);

      await dataFile.delete();
      await File(p.join(root.path, 'unins123.exe')).writeAsBytes([0]);
      expect(await system.hasLocalInnoMarker(root.path), isTrue);
    });

    test(
      'ignores marker-shaped directories and unrelated file names',
      () async {
        const system = NativeWindowsInstallSystem();
        await Directory(p.join(root.path, 'unins000.exe')).create();
        await File(p.join(root.path, 'unins1234.exe')).writeAsBytes([0]);
        await File(p.join(root.path, 'unins001.log')).writeAsBytes([0]);

        expect(await system.hasLocalInnoMarker(root.path), isFalse);
      },
    );
  });
}

Future<void> _writeInstalledVersion(
  Directory target,
  UpdateVersion version,
) async {
  await File(p.join(target.path, 'app-version.json')).writeAsString(
    jsonEncode({'version': version.version, 'build': version.build}),
  );
}

Future<UpdatePackage> _package(List<int> bytes) async {
  final digest = await Sha256().hash(bytes);
  final hash = digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return UpdatePackage.fromJson({
    'platform': 'windows-installed',
    'file': 'Equis-Windows-1.0.1-setup.exe',
    'size': bytes.length,
    'sha256': hash,
  });
}

Future<void> _expectPreflightCode(Future<Object?> action, String code) async {
  await expectLater(
    action,
    throwsA(
      isA<WindowsUpdatePreflightException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    ),
  );
}

final class _FakeWindowsInstallSystem implements WindowsInstallSystem {
  _FakeWindowsInstallSystem({
    required this.locations,
    this.sid = 'S-1-5-21-1000-2000-3000-1001',
  });

  final Map<String, String> locations;
  final String sid;
  bool writable = true;
  bool localInnoMarker = false;
  WindowsUpdatePreflightException? installLocationError;
  String? checkedWritableDirectory;
  final Map<String, int> canonicalDirectoryErrorCodes = {};

  @override
  Future<String?> installLocation(String hive) async {
    final error = installLocationError;
    if (error != null) throw error;
    return locations[hive];
  }

  @override
  Future<String> currentSid() async => sid;

  @override
  Future<bool> canWrite(String directory) async {
    checkedWritableDirectory = directory;
    return writable;
  }

  @override
  Future<bool> hasLocalInnoMarker(String directory) async => localInnoMarker;

  @override
  Future<String> canonicalDirectory(String path) async {
    final errorCode = canonicalDirectoryErrorCodes[path];
    if (errorCode != null) {
      throw FileSystemException(
        'Simulated canonical path error',
        path,
        OSError('Simulated error', errorCode),
      );
    }
    return Directory(path).resolveSymbolicLinks();
  }

  @override
  Future<String> canonicalFile(String path) =>
      File(path).resolveSymbolicLinks();
}
