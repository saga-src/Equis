import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'app_update_service.dart';
import 'windows_install_preflight.dart';
import 'windows_update_catalog.dart';
import 'windows_update_identity.dart';
import 'windows_update_native.dart';

/// A refusal made before stopping sync or draining the database.
final class WindowsUpdateCloseRefused implements Exception {
  const WindowsUpdateCloseRefused();
}

final class WindowsInstalledUpdateException implements Exception {
  const WindowsInstalledUpdateException(this.code);
  final String code;
  @override
  String toString() => 'Windows update: $code';
}

/// The medium helper owns the attempt after the app exits. No journal resumes it.
final class WindowsInstalledUpdateSession {
  WindowsInstalledUpdateSession._(
    this.transaction,
    this._process,
    this._messages,
  );

  final String transaction;
  final Process _process;
  final StreamIterator<Map<String, dynamic>> _messages;
  bool _used = false;
  bool _closeStarted = false;

  static Future<WindowsInstalledUpdateSession> prepare(
    AppUpdateService service,
  ) async {
    if (!Platform.isWindows || service.platform != 'windows-installed') {
      throw const WindowsInstalledUpdateException('unsupported_platform');
    }
    if (!windowsInstalledUpdateEnabled) {
      throw const WindowsInstalledUpdateException(
        'installed_update_gate_pending',
      );
    }
    final cache = p.normalize(service.directory.absolute.path);
    final journal = File(p.join(cache, 'installation.json'));
    if (await journal.exists()) {
      final entry = jsonDecode(await journal.readAsString());
      if (entry is! Map ||
          entry['state'] == 'installation_started' ||
          entry['state'] == 'manual_recovery' ||
          entry['state'] == 'replacing' ||
          entry['state'] == 'relaunch_consumed') {
        throw const WindowsInstalledUpdateException('manual_recovery_required');
      }
    }
    final payload = await service.validateForInstallation();
    final target = p.dirname(Platform.resolvedExecutable);
    final identity = await const WindowsInstalledPreflight().inspect(
      target: target,
      executable: Platform.resolvedExecutable,
      runningVersion: AppUpdateService.current,
      updateVersion: service.manifest!.version,
      package: service.package!,
      payload: payload,
    );
    final app = WindowsUpdateProcess.current();
    WindowsUpdateCatalog? source;
    WindowsUpdateFile? copiedLock;
    Process? helper;
    try {
      if (app.integrityRid != 0x2000 || app.sid != identity.sid) {
        throw const WindowsInstalledUpdateException('app_must_be_unelevated');
      }
      source = await WindowsUpdateCatalog.inspect(target);
      if (source.version != AppUpdateService.current.version ||
          source.build != AppUpdateService.current.build ||
          service.manifest!.version.build <= source.build) {
        throw const WindowsInstalledUpdateException(
          'installed_version_mismatch',
        );
      }
      final random = Random.secure();
      final transaction = List.generate(
        16,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final directory = Directory(p.join(cache, 'installed-$transaction'));
      if (p.isWithin(target, directory.path) ||
          p.equals(target, directory.path)) {
        throw const WindowsInstalledUpdateException('helper_inside_target');
      }
      await directory.create();
      final copied = await File(
        source.helperPath,
      ).copy(p.join(directory.path, 'equis-update-helper.exe'));
      copiedLock = WindowsUpdateFile.open(copied.path);
      if (!copiedLock.verifySha256(
        source.helperSha256,
        source.files['equis-update-helper.exe']!.size,
      )) {
        throw const WindowsInstalledUpdateException('helper_hash_mismatch');
      }
      copiedLock.revalidate();
      await source.revalidate();
      final request = File(p.join(directory.path, 'request.json'));
      await request.writeAsString(
        jsonEncode({
          'format': 2,
          'transaction': transaction,
          'cache': cache,
          'target': identity.target,
          'hive': identity.hive,
          'sid': identity.sid,
          'appPid': pid,
          'appCreatedFiletime': app.createdFiletime.toString(),
          'oldVersion': source.version,
          'oldBuild': source.build,
          'newVersion': service.manifest!.version.version,
          'newBuild': service.manifest!.version.build,
          'requiresElevation': identity.requiresElevation,
        }),
        flush: true,
      );
      helper = await Process.start(copied.path, [
        'installed-v2',
        request.path,
      ], workingDirectory: directory.path);
      // Errors are structured on stdout/journal; stderr must not block the child.
      unawaited(helper.stderr.drain<void>());
      final peer = WindowsUpdateProcess.open(helper.pid);
      try {
        if (peer.sid != app.sid ||
            peer.session != app.session ||
            peer.integrityRid != 0x2000) {
          throw const WindowsInstalledUpdateException(
            'helper_identity_mismatch',
          );
        }
      } finally {
        peer.close();
      }
      final messages = StreamIterator(
        _decodeMessages(helper.stdout, transaction),
      );
      final session = WindowsInstalledUpdateSession._(
        transaction,
        helper,
        messages,
      );
      final prepared = await session._next().timeout(
        const Duration(seconds: 30),
      );
      if (prepared['type'] != 'PREPARED') {
        await session.abort();
        throw WindowsInstalledUpdateException(
          prepared['code'] as String? ?? 'helper_preparation_failed',
        );
      }
      return session;
    } catch (_) {
      if (helper != null) {
        try {
          await helper.stdin.close();
        } catch (_) {
          /* Helper observes EOF. */
        }
      }
      rethrow;
    } finally {
      copiedLock?.close();
      await source?.close();
      app.close();
    }
  }

  Future<String> install(Future<void> Function() closeWorkspace) async {
    if (_used) throw StateError('The update session was already consumed');
    _used = true;
    await _send('START_SETUP');
    try {
      while (true) {
        // Waiting for UAC and for the user to finish the wizard has no deadline.
        final message = await _next();
        switch (message['type']) {
          case 'CLOSE_REQUEST':
            if (_closeStarted) {
              throw const WindowsInstalledUpdateException(
                'repeated_close_request',
              );
            }
            _closeStarted = true;
            try {
              final closeBudget = DateTime.fromMillisecondsSinceEpoch(
                message['closeDeadlineMillis'] as int,
              ).difference(DateTime.now());
              if (closeBudget <= Duration.zero) {
                throw const WindowsUpdateCloseRefused();
              }
              await closeWorkspace().timeout(closeBudget);
            } on WindowsUpdateCloseRefused {
              _closeStarted = false;
              await _send('CLOSE_FAILED', {'closeStarted': false});
              return 'close_refused';
            } catch (_) {
              // drainForUpdate can permanently stop transactions. A new process
              // is required; returning to the old UI would expose disposed state.
              try {
                await _send('CLOSE_FAILED', {'closeStarted': true});
              } catch (_) {}
              exit(1);
            }
            try {
              await _send('CLOSE_OK');
            } catch (_) {
              // The helper cannot issue GO without our acknowledgement.
              exit(1);
            }
            exit(0);
          case 'RESULT':
            return message['code'] as String? ?? 'cancelled';
          case 'ERROR':
            throw WindowsInstalledUpdateException(
              message['code'] as String? ?? 'installation_failed',
            );
          default:
            throw const WindowsInstalledUpdateException(
              'unexpected_helper_message',
            );
        }
      }
    } finally {
      if (!_closeStarted) await abort();
    }
  }

  Future<Map<String, dynamic>> _next() async {
    if (!await _messages.moveNext()) {
      throw const WindowsInstalledUpdateException('helper_disconnected');
    }
    return _messages.current;
  }

  Future<void> _send(
    String type, [
    Map<String, Object> extra = const {},
  ]) async {
    _process.stdin.writeln(
      jsonEncode({
        'format': 2,
        'transaction': transaction,
        'type': type,
        ...extra,
      }),
    );
    await _process.stdin.flush().timeout(const Duration(seconds: 30));
  }

  Future<void> abort() async {
    try {
      await _send('ABORT');
    } catch (_) {
      /* Never kill the installer. */
    }
    try {
      await _process.stdin.close();
    } catch (_) {}
    await _messages.cancel();
  }

  static Stream<Map<String, dynamic>> _decodeMessages(
    Stream<List<int>> input,
    String transaction,
  ) async* {
    final buffer = <int>[];
    await for (final chunk in input) {
      for (final byte in chunk) {
        if (byte != 10) {
          if (buffer.length >= 8192) {
            throw const WindowsInstalledUpdateException(
              'oversized_helper_message',
            );
          }
          buffer.add(byte);
          continue;
        }
        final value = jsonDecode(utf8.decode(buffer));
        buffer.clear();
        if (value is! Map<String, dynamic> ||
            value['format'] != 2 ||
            value['transaction'] != transaction ||
            value['type'] is! String ||
            value.keys.any(
              (key) => !{
                'format',
                'transaction',
                'type',
                'code',
                'closeDeadlineMillis',
              }.contains(key),
            )) {
          throw const WindowsInstalledUpdateException('invalid_helper_message');
        }
        if ((value['type'] == 'CLOSE_REQUEST' &&
                (value['closeDeadlineMillis'] is! int ||
                    (value['closeDeadlineMillis'] as int) >
                        DateTime.now()
                            .add(const Duration(seconds: 120))
                            .millisecondsSinceEpoch)) ||
            (value['type'] != 'CLOSE_REQUEST' &&
                value.containsKey('closeDeadlineMillis'))) {
          throw const WindowsInstalledUpdateException('invalid_close_deadline');
        }
        yield value;
      }
    }
    if (buffer.isNotEmpty) {
      throw const WindowsInstalledUpdateException('truncated_helper_message');
    }
  }
}
