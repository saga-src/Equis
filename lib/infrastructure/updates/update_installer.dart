import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_update_service.dart';

final class UpdateInstaller {
  static Future<bool> replacementInterrupted() async {
    if (!Platform.isWindows) return false;
    final support = await getApplicationSupportDirectory();
    final journal = File(p.join(support.path, 'updates', 'installation.json'));
    if (!await journal.exists()) return false;
    final value =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    return value['state'] == 'replacing' &&
        p.equals(
          value['target'] as String,
          p.dirname(Platform.resolvedExecutable),
        );
  }

  static Future<String> platform() async {
    if (Platform.isAndroid) return 'android';
    if (!Platform.isWindows) throw UnsupportedError('Updates unsupported');
    final executableDirectory = p.dirname(Platform.resolvedExecutable);
    for (final hive in ['HKCU', 'HKLM']) {
      final result = await Process.run('reg.exe', [
        'query',
        '$hive\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{B9ECD233-7990-478B-A5F1-C30E4BCAA15E}_is1',
        '/v',
        'InstallLocation',
        '/reg:64',
      ]);
      if (result.exitCode == 0) {
        final match = RegExp(
          r'InstallLocation\s+REG_SZ\s+(.+)',
        ).firstMatch(result.stdout.toString());
        if (match != null &&
            p.equals(
              p.normalize(match.group(1)!.trim()),
              p.normalize(executableDirectory),
            )) {
          return 'windows-installed';
        }
      }
    }
    return 'windows-portable';
  }

  /// Returns before app shutdown; staging errors leave the running vault usable.
  static Future<File?> prepare(AppUpdateService service) async {
    await service.validateForInstallation();
    if (Platform.isAndroid) return null;
    final original = File(
      p.join(p.dirname(Platform.resolvedExecutable), 'equis-update-helper.exe'),
    );
    final helper = await original.copy(
      p.join(service.directory.path, 'equis-update-helper.exe'),
    );
    final result = await Process.run(helper.path, [
      'prepare',
      service.directory.path,
      p.dirname(Platform.resolvedExecutable),
      service.platform,
      '$pid',
    ]);
    if (result.exitCode != 0) throw StateError('Update preparation failed');
    return helper;
  }

  static Future<String> install(
    AppUpdateService service,
    File? helper,
    Future<void> Function() closeWorkspace,
  ) async {
    final file = await service.validateForInstallation();
    if (Platform.isAndroid) {
      return await const MethodChannel(
            'app.saga.equis/updates',
          ).invokeMethod<String>('install', {'path': file.path}) ??
          'opened';
    }
    await Process.start(helper!.path, [
      'apply',
      service.directory.path,
      p.dirname(Platform.resolvedExecutable),
      service.platform,
      '$pid',
    ], mode: ProcessStartMode.detached);
    await closeWorkspace();
    exit(0);
  }
}
