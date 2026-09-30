import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'update_manifest.dart';
import 'windows_update_identity.dart';

const windowsInnoUninstallKey =
    'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{$windowsUpdateInnoAppId}_is1';

/// A failure here must be reported while the vault and the old app are open.
final class WindowsUpdatePreflightException implements Exception {
  const WindowsUpdatePreflightException(this.code);
  final String code;

  @override
  String toString() => 'Windows update preflight: $code';
}

final class WindowsInstallIdentity {
  const WindowsInstallIdentity({
    required this.hive,
    required this.target,
    required this.executable,
    required this.sid,
    required this.installedVersion,
    required this.writable,
  });

  final String hive;
  final String target;
  final String executable;
  final String sid;
  final UpdateVersion installedVersion;
  final bool writable;

  bool get requiresElevation => hive == 'HKLM' || !writable;
}

/// Kept injectable so the registry, identity and ACL decisions can be tested
/// without starting Inno or requesting elevation.
abstract interface class WindowsInstallSystem {
  Future<String?> installLocation(String hive);
  Future<bool> hasLocalInnoMarker(String directory);
  Future<String> currentSid();
  Future<bool> canWrite(String directory);
  Future<String> canonicalDirectory(String path);
  Future<String> canonicalFile(String path);
}

final class NativeWindowsInstallSystem implements WindowsInstallSystem {
  const NativeWindowsInstallSystem();

  @override
  Future<bool> hasLocalInnoMarker(String directory) async {
    // The project's Inno setup uses the default UninstallFilesDir={app}.
    // Either surviving half of the uninstaller is evidence of a damaged or
    // unregistered installed copy, so it must not become portable.
    final name = RegExp(r'^unins[0-9]{3}\.(dat|exe)$', caseSensitive: false);
    await for (final entry in Directory(directory).list(followLinks: false)) {
      if (name.hasMatch(p.basename(entry.path)) && entry is! Directory) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<String?> installLocation(String hive) async {
    if (hive != 'HKCU' && hive != 'HKLM') {
      throw const WindowsUpdatePreflightException('invalid_hive');
    }
    final registryHive = hive == 'HKCU' ? 'CurrentUser' : 'LocalMachine';
    // The Registry API distinguishes an absent key from access or read errors.
    // reg.exe uses the same exit code for both, which would classify a broken
    // installed registration as a portable copy.
    final script =
        '''
try {
  \$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::$registryHive,
    [Microsoft.Win32.RegistryView]::Registry64)
  \$key = \$root.OpenSubKey('$windowsInnoUninstallKey')
  if (\$null -eq \$key) { [Console]::Out.Write('ABSENT'); exit 0 }
  if (\$key.GetValueKind('InstallLocation') -ne
      [Microsoft.Win32.RegistryValueKind]::String) { exit 2 }
  \$value = \$key.GetValue('InstallLocation')
  if (\$value -isnot [string] -or \$value.Length -eq 0) { exit 2 }
  [Console]::Out.Write('PRESENT:' +
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(\$value)))
  exit 0
} catch { exit 2 }
''';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw const WindowsUpdatePreflightException('registry_unavailable');
    }
    final output = result.stdout.toString();
    if (output == 'ABSENT') return null;
    if (!output.startsWith('PRESENT:')) {
      throw const WindowsUpdatePreflightException('invalid_registration');
    }
    try {
      return utf8.decode(base64Decode(output.substring('PRESENT:'.length)));
    } on FormatException {
      throw const WindowsUpdatePreflightException('invalid_registration');
    }
  }

  @override
  Future<String> currentSid() async {
    final result = await Process.run('whoami.exe', [
      '/user',
      '/fo',
      'csv',
      '/nh',
    ]);
    final match = RegExp(
      r'^"[^"]+","(S-\d+(?:-\d+)+)"',
    ).firstMatch(result.stdout.toString().trim());
    if (result.exitCode != 0 || match == null) {
      throw const WindowsUpdatePreflightException('sid_unavailable');
    }
    return match.group(1)!;
  }

  /// Inno's uninstall registration must agree with the signed file catalog.
  Future<String> registeredVersion(String hive) async {
    if (hive != 'HKCU' && hive != 'HKLM') {
      throw const WindowsUpdatePreflightException('invalid_hive');
    }
    final registryHive = hive == 'HKCU' ? 'CurrentUser' : 'LocalMachine';
    final script =
        '''
try {
  \$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::$registryHive,
    [Microsoft.Win32.RegistryView]::Registry64)
  \$key = \$root.OpenSubKey('$windowsInnoUninstallKey')
  if (\$null -eq \$key -or
      \$key.GetValueKind('DisplayVersion') -ne
      [Microsoft.Win32.RegistryValueKind]::String) { exit 2 }
  \$value = \$key.GetValue('DisplayVersion')
  if (\$value -isnot [string] -or \$value.Length -eq 0) { exit 2 }
  [Console]::Out.Write([Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes(\$value)))
  exit 0
} catch { exit 2 }
''';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw const WindowsUpdatePreflightException(
        'registry_version_unavailable',
      );
    }
    try {
      return utf8.decode(base64Decode(result.stdout.toString()));
    } on FormatException {
      throw const WindowsUpdatePreflightException('invalid_registration');
    }
  }

  @override
  Future<String> canonicalDirectory(String path) =>
      Directory(path).resolveSymbolicLinks();

  @override
  Future<String> canonicalFile(String path) =>
      File(path).resolveSymbolicLinks();

  @override
  Future<bool> canWrite(String directory) async {
    final random = Random.secure();
    final probe = File(
      p.join(directory, '.equis-update-probe-${random.nextInt(1 << 32)}'),
    );
    try {
      await probe.create(exclusive: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

final class WindowsInstalledPreflight {
  const WindowsInstalledPreflight({
    this.system = const NativeWindowsInstallSystem(),
  });

  final WindowsInstallSystem system;

  Future<WindowsInstallIdentity> inspect({
    required String target,
    required String executable,
    required UpdateVersion runningVersion,
    required UpdateVersion updateVersion,
    required UpdatePackage package,
    required File payload,
  }) async {
    await _rejectLinks(target);
    await _rejectLinks(executable);
    await _rejectLinks(payload.path);
    await _rejectLinks(p.join(target, 'app-version.json'));
    if (p.basename(executable).toLowerCase() != 'equis.exe' ||
        !p.equals(p.dirname(executable), target)) {
      throw const WindowsUpdatePreflightException('executable_mismatch');
    }
    final canonicalTarget = await system.canonicalDirectory(target);
    final canonicalExecutable = await system.canonicalFile(executable);
    if (!p.equals(p.absolute(target), canonicalTarget) ||
        !p.equals(p.absolute(executable), canonicalExecutable) ||
        !p.equals(canonicalTarget, p.dirname(canonicalExecutable))) {
      throw const WindowsUpdatePreflightException('executable_mismatch');
    }
    if (!await system.hasLocalInnoMarker(canonicalTarget)) {
      throw const WindowsUpdatePreflightException('uninstaller_missing');
    }
    final locations = <String, String>{};
    for (final hive in const ['HKCU', 'HKLM']) {
      final location = await system.installLocation(hive);
      if (location != null) locations[hive] = location;
    }
    if (locations.length != 1) {
      throw WindowsUpdatePreflightException(
        locations.isEmpty ? 'registration_missing' : 'registration_ambiguous',
      );
    }
    final hive = locations.keys.single;
    final registered = locations.values.single;
    await _rejectLinks(registered);
    if (!p.equals(p.absolute(registered), canonicalTarget) ||
        !p.equals(
          await system.canonicalDirectory(registered),
          canonicalTarget,
        )) {
      throw const WindowsUpdatePreflightException('registration_mismatch');
    }
    final version =
        jsonDecode(
              await File(
                p.join(canonicalTarget, 'app-version.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final installedVersion = UpdateVersion(
      version['version'] as String,
      version['build'] as int,
    );
    if (installedVersion.version != runningVersion.version ||
        installedVersion.build != runningVersion.build ||
        updateVersion.compareTo(installedVersion) <= 0) {
      throw const WindowsUpdatePreflightException('installed_version_mismatch');
    }
    if (package.platform != 'windows-installed') {
      throw const WindowsUpdatePreflightException('package_platform_mismatch');
    }
    await package.validate(payload);
    return WindowsInstallIdentity(
      hive: hive,
      target: canonicalTarget,
      executable: canonicalExecutable,
      sid: await system.currentSid(),
      installedVersion: installedVersion,
      writable: await system.canWrite(canonicalTarget),
    );
  }
}

/// A registered copy must never fall through to portable replacement.
Future<String> classifyWindowsPlatform({
  required WindowsInstallSystem system,
  required String executable,
}) async {
  final target = p.dirname(executable);
  await _rejectLinks(target);
  await _rejectLinks(executable);
  final canonicalTarget = await system.canonicalDirectory(target);
  if (!p.equals(p.absolute(target), canonicalTarget)) {
    throw const WindowsUpdatePreflightException('executable_mismatch');
  }
  final localMarker = await system.hasLocalInnoMarker(canonicalTarget);
  final locations = <String, String>{};
  for (final hive in const ['HKCU', 'HKLM']) {
    final location = await system.installLocation(hive);
    if (location != null) locations[hive] = location;
  }
  if (locations.length > 1 && localMarker) {
    throw const WindowsUpdatePreflightException('registration_ambiguous');
  }
  var matchingRegistrations = 0;
  for (final registered in locations.values) {
    final lexicalMatch = p.equals(p.absolute(registered), canonicalTarget);
    late final String canonicalRegistered;
    try {
      canonicalRegistered = await system.canonicalDirectory(registered);
    } on FileSystemException catch (error) {
      // A stale registration for a removed, separate installation does not
      // turn this portable copy into an installed one. Access errors and a
      // missing path at our own target still fail closed.
      if (!localMarker &&
          !lexicalMatch &&
          const {2, 3}.contains(error.osError?.errorCode)) {
        continue;
      }
      rethrow;
    }
    if (p.equals(canonicalRegistered, canonicalTarget)) {
      await _rejectLinks(registered);
      if (!p.equals(p.absolute(registered), canonicalTarget)) {
        throw const WindowsUpdatePreflightException('registration_mismatch');
      }
      matchingRegistrations++;
    }
  }
  if (matchingRegistrations > 1) {
    throw const WindowsUpdatePreflightException('registration_ambiguous');
  }
  if (matchingRegistrations == 1) {
    if (!localMarker) {
      throw const WindowsUpdatePreflightException('uninstaller_missing');
    }
    return 'windows-installed';
  }
  if (localMarker) {
    throw WindowsUpdatePreflightException(
      locations.isEmpty ? 'registration_missing' : 'registration_mismatch',
    );
  }
  return 'windows-portable';
}

Future<void> _rejectLinks(String path) async {
  var current = p.absolute(path);
  while (true) {
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const WindowsUpdatePreflightException('linked_path');
    }
    final parent = p.dirname(current);
    if (parent == current) return;
    current = parent;
  }
}
