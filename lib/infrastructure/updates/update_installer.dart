import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_update_service.dart';
import 'windows_install_preflight.dart';
import 'windows_installed_update_session.dart';
import 'windows_update_identity.dart';
import 'windows_update_native.dart';

export 'windows_installed_update_session.dart';

final class UpdateInstaller {
  static Future<bool> replacementInterrupted() async {
    if (!Platform.isWindows) return false;
    final support =
        await windowsUpdateSupportDirectoryRoot() ??
        await getApplicationSupportDirectory();
    final journal = File(p.join(support.path, 'updates', 'installation.json'));
    if (!await journal.exists()) return false;
    try {
      final value = jsonDecode(await journal.readAsString());
      if (value is! Map || value['state'] is! String) {
        return true;
      }
      if (!const {
        'replacing',
        'installation_started',
        'manual_recovery',
      }.contains(value['state'])) {
        return false;
      }
      return value['target'] is! String ||
          p.equals(
            value['target'] as String,
            p.dirname(Platform.resolvedExecutable),
          );
    } catch (_) {
      return true;
    }
  }

  static Future<WindowsInstalledUpdateSession> prepareInstalled(
    AppUpdateService service,
  ) => WindowsInstalledUpdateSession.prepare(service);

  static Future<String> installInstalled(
    WindowsInstalledUpdateSession session,
    Future<void> Function() closeWorkspace,
  ) => session.install(closeWorkspace);

  static Future<String> platform() async {
    if (Platform.isAndroid) return 'android';
    if (!Platform.isWindows) throw UnsupportedError('Updates unsupported');
    return classifyWindowsPlatform(
      system: const NativeWindowsInstallSystem(),
      executable: Platform.resolvedExecutable,
    );
  }

  /// Returns before app shutdown; staging errors leave the running vault usable.
  static Future<File?> prepare(AppUpdateService service) async {
    if (Platform.isWindows && service.platform == 'windows-installed') {
      try {
        final payload = await service.validateForInstallation();
        final identity = await const WindowsInstalledPreflight().inspect(
          target: p.dirname(Platform.resolvedExecutable),
          executable: Platform.resolvedExecutable,
          runningVersion: AppUpdateService.current,
          updateVersion: service.manifest!.version,
          package: service.package!,
          payload: payload,
        );
        // Positional legacy calls cannot coordinate safe app shutdown. The
        // installed-v2 session is the only supported installed update route.
        await _recordInstalledFailure(
          service.directory,
          'installed_session_required',
          hive: identity.hive,
          build: service.manifest!.version.build,
        );
        throw const WindowsUpdatePreflightException(
          'installed_session_required',
        );
      } on WindowsUpdatePreflightException catch (error) {
        if (error.code != 'installed_session_required') {
          await _recordInstalledFailure(service.directory, error.code);
        }
        rethrow;
      } catch (_) {
        await _recordInstalledFailure(
          service.directory,
          'verification_or_system_error',
        );
        rethrow;
      }
    }
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
    if (Platform.isWindows && service.platform == 'windows-installed') {
      await _recordInstalledFailure(
        service.directory,
        'installed_session_required',
      );
      throw const WindowsUpdatePreflightException('installed_session_required');
    }
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

  static Future<void> _recordInstalledFailure(
    Directory directory,
    String code, {
    String? hive,
    int? build,
  }) async {
    WindowsUpdateMutex? refusalLease;
    try {
      refusalLease = WindowsUpdateMutex.acquire(
        p.dirname(Platform.resolvedExecutable),
      );
    } on WindowsUpdateNativeException catch (error) {
      if (error.code == 'update_already_running') return;
      rethrow;
    }
    try {
      await directory.create(recursive: true);
      final journal = File(p.join(directory.path, 'installation.json'));
      if (await journal.exists()) {
        final old = jsonDecode(await journal.readAsString());
        if (old is! Map ||
            const {
              'installation_started',
              'manual_recovery',
              'replacing',
              'relaunch_consumed',
            }.contains(old['state'])) {
          return;
        }
      }
      final pending = File('${journal.path}.new');
      final entry = <String, Object>{
        'state': 'preflight_failed',
        'phase': 'preflight',
        'code': code,
      };
      if (hive != null) entry['hive'] = hive;
      if (build != null) entry['build'] = build;
      await pending.writeAsString(jsonEncode(entry), flush: true);
      await pending.rename(journal.path);
    } finally {
      refusalLease.close();
    }
  }
}
