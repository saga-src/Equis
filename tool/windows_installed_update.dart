import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:equis/infrastructure/updates/update_manifest.dart';
import 'package:equis/infrastructure/updates/windows_install_preflight.dart';
import 'package:equis/infrastructure/updates/windows_update_catalog.dart';
import 'package:equis/infrastructure/updates/windows_update_identity.dart';
import 'package:equis/infrastructure/updates/windows_update_native.dart';

final _transactionPattern = RegExp(r'^[0-9a-f]{32}$');
final _versionPattern = RegExp(
  r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
);

/// The installed helper speaks only the local app protocol. Inno is the
/// installer and remains visible. All authorization is rederived here from
/// the installed catalog, signed manifest, registry and retained file handles.
Future<bool> runWindowsInstalledUpdate(String requestPath) async {
  _InstalledRequest? request;
  _InstalledRun? run;
  try {
    if (!windowsInstalledUpdateEnabled) {
      throw const _InstalledFailure('installed_update_disabled');
    }
    request = await _InstalledRequest.read(requestPath);
    run = _InstalledRun(request);
    return await run.execute();
  } on _InstalledFailure catch (error) {
    await run?.reportError(error.code, error.win32Error);
    if (run == null) {
      await _reportPreparationFailure(requestPath, request, error.code);
    }
    return false;
  } on WindowsUpdateNativeException catch (error) {
    await run?.reportError(error.code, error.win32 ?? 0);
    if (run == null) {
      await _reportPreparationFailure(requestPath, request, error.code);
    }
    return false;
  } catch (error) {
    await run?.reportError('internal_error', 0, detail: '$error');
    if (run == null) {
      await _reportPreparationFailure(requestPath, request, 'internal_error');
    }
    return false;
  } finally {
    await run?.close();
  }
}

Future<void> _reportPreparationFailure(
  String path,
  _InstalledRequest? request,
  String code,
) async {
  // Recover only the response identifier from the filename, not authorization.
  // An invalid request still cannot acquire a lease, start setup or write GO.
  final attempt = RegExp(
    r'^installed-([0-9a-f]{32})$',
  ).firstMatch(p.basename(p.dirname(path)));
  final transaction =
      request?.transaction ??
      (p.basename(path) == 'request.json' ? attempt?.group(1) : null);
  if (transaction != null) {
    await _emitBestEffort(transaction, 'ERROR', code: code);
  } else {
    try {
      stderr.writeln(jsonEncode({'format': 2, 'type': 'ERROR', 'code': code}));
      await stderr.flush().timeout(const Duration(seconds: 30));
    } catch (_) {}
  }
}

final class _InstalledFailure implements Exception {
  const _InstalledFailure(this.code);
  final String code;
  final int win32Error = 0;
}

final class _InstalledRequest {
  const _InstalledRequest({
    required this.transaction,
    required this.cache,
    required this.target,
    required this.hive,
    required this.sid,
    required this.appPid,
    required this.appCreatedFiletime,
    required this.oldVersion,
    required this.oldBuild,
    required this.newVersion,
    required this.newBuild,
    required this.requiresElevation,
  });

  final String transaction, cache, target, hive, sid;
  final int appPid, appCreatedFiletime, oldBuild, newBuild;
  final String oldVersion, newVersion;
  final bool requiresElevation;

  static Future<_InstalledRequest> read(String path) async {
    if (!Platform.isWindows ||
        !p.isAbsolute(path) ||
        !p.equals(p.basename(path), 'request.json')) {
      throw const _InstalledFailure('invalid_request_path');
    }
    final file = File(path);
    if (await file.length() > 8192) {
      throw const _InstalledFailure('invalid_request_size');
    }
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        !_exactKeys(decoded, const {
          'format',
          'transaction',
          'cache',
          'target',
          'hive',
          'sid',
          'appPid',
          'appCreatedFiletime',
          'oldVersion',
          'oldBuild',
          'newVersion',
          'newBuild',
          'requiresElevation',
        }) ||
        decoded['format'] != 2 ||
        decoded['transaction'] is! String ||
        !_transactionPattern.hasMatch(decoded['transaction'] as String) ||
        decoded['cache'] is! String ||
        decoded['target'] is! String ||
        decoded['hive'] is! String ||
        !{'HKCU', 'HKLM'}.contains(decoded['hive']) ||
        decoded['sid'] is! String ||
        !RegExp(r'^S-[0-9]+(?:-[0-9]+)+$').hasMatch(decoded['sid'] as String) ||
        decoded['appPid'] is! int ||
        (decoded['appPid'] as int) < 1 ||
        (decoded['appPid'] as int) > 0xffffffff ||
        decoded['appCreatedFiletime'] is! String ||
        !RegExp(
          r'^[1-9][0-9]{0,19}$',
        ).hasMatch(decoded['appCreatedFiletime'] as String) ||
        decoded['oldVersion'] is! String ||
        !_validVersion(decoded['oldVersion'] as String) ||
        decoded['newVersion'] is! String ||
        !_validVersion(decoded['newVersion'] as String) ||
        decoded['oldBuild'] is! int ||
        (decoded['oldBuild'] as int) < 1 ||
        (decoded['oldBuild'] as int) > 2147483647 ||
        decoded['newBuild'] is! int ||
        (decoded['newBuild'] as int) < 1 ||
        (decoded['newBuild'] as int) > 2147483647 ||
        decoded['requiresElevation'] is! bool) {
      throw const _InstalledFailure('invalid_request');
    }
    final transaction = decoded['transaction'] as String;
    final cache = decoded['cache'] as String;
    final target = decoded['target'] as String;
    if (!p.isAbsolute(cache) ||
        !p.isAbsolute(target) ||
        p.normalize(cache) != cache ||
        p.normalize(target) != target ||
        !p.equals(p.dirname(p.dirname(path)), cache) ||
        !p.equals(p.basename(p.dirname(path)), 'installed-$transaction') ||
        p.equals(cache, target) ||
        p.isWithin(target, cache) ||
        p.isWithin(cache, target)) {
      throw const _InstalledFailure('invalid_request_path');
    }
    await _rejectLinks(path);
    await _rejectLinks(cache);
    await _rejectLinks(target);
    return _InstalledRequest(
      transaction: transaction,
      cache: cache,
      target: target,
      hive: decoded['hive'] as String,
      sid: decoded['sid'] as String,
      appPid: decoded['appPid'] as int,
      appCreatedFiletime: int.parse(decoded['appCreatedFiletime'] as String),
      oldVersion: decoded['oldVersion'] as String,
      oldBuild: decoded['oldBuild'] as int,
      newVersion: decoded['newVersion'] as String,
      newBuild: decoded['newBuild'] as int,
      requiresElevation: decoded['requiresElevation'] as bool,
    );
  }
}

final class _InstalledRun {
  _InstalledRun(this.request)
    : journal = File(p.join(request.cache, 'installation.json'));

  final _InstalledRequest request;
  final File journal;
  WindowsUpdateCatalog? oldCatalog;
  WindowsUpdateFile? payloadLock, selfLock;
  WindowsUpdateMutex? mutex;
  WindowsUpdateProcess? appProcess, loader, setup;
  WindowsUpdateProcess? selfProcess;
  Future<int>? loaderExit;
  WindowsUpdatePipeServer? pipe;
  WindowsUpdatePipeConnection? connection;
  StreamIterator<String>? appMessages;
  UpdatePackage? package;
  bool goSent = false;
  bool closeStarted = false;
  bool appExited = false;
  bool errorReported = false;

  Future<bool> execute() async {
    // Only the lease owner may read/replace the shared diagnostic journal.
    mutex = WindowsUpdateMutex.acquire(request.target);
    await _rejectPendingJournal();
    final self = WindowsUpdateProcess.current();
    selfProcess = self;
    if (self.sid != request.sid || self.integrityRid != 0x2000) {
      throw const _InstalledFailure('sid_mismatch');
    }
    appProcess = WindowsUpdateProcess.open(
      request.appPid,
      createdFiletime: request.appCreatedFiletime,
    );
    if (!appProcess!.isAlive ||
        appProcess!.sid != request.sid ||
        appProcess!.session != self.session ||
        appProcess!.integrityRid != 0x2000) {
      throw const _InstalledFailure('app_identity_changed');
    }
    if (p.equals(request.target, p.dirname(Platform.resolvedExecutable)) ||
        p.isWithin(request.target, Platform.resolvedExecutable)) {
      throw const _InstalledFailure('helper_inside_target');
    }
    final manifestPath = p.join(request.cache, 'manifest.json');
    final signaturePath = p.join(request.cache, 'manifest.sig');
    await _rejectLinks(manifestPath);
    await _rejectLinks(signaturePath);
    final manifest = await UpdateManifest.verify(
      await File(manifestPath).readAsBytes(),
      base64Decode((await File(signaturePath).readAsString()).trim()),
      base64Decode(windowsUpdateVerificationKey),
      expectedApplicationId: windowsUpdateApplicationId,
    );
    if (manifest.version.version != request.newVersion ||
        manifest.version.build != request.newBuild ||
        manifest.version.compareTo(
              UpdateVersion(request.oldVersion, request.oldBuild),
            ) <=
            0 ||
        request.newBuild <= request.oldBuild) {
      throw const _InstalledFailure('request_mismatch');
    }
    final installedPackages = manifest.packages
        .where((value) => value.platform == 'windows-installed')
        .toList();
    if (installedPackages.length != 1 ||
        installedPackages.single.trustCatalogSha256 == null) {
      throw const _InstalledFailure('manifest_missing_catalog_binding');
    }
    package = installedPackages.single;
    final payload = File(p.join(request.cache, package!.name));
    await _rejectLinks(payload.path);
    oldCatalog = await WindowsUpdateCatalog.inspect(request.target);
    if (oldCatalog!.version != request.oldVersion ||
        oldCatalog!.build != request.oldBuild) {
      throw const _InstalledFailure('old_catalog_version_mismatch');
    }
    selfLock = WindowsUpdateFile.open(Platform.resolvedExecutable);
    if (!selfLock!.verifySha256(
      oldCatalog!.helperSha256,
      oldCatalog!.files['equis-update-helper.exe']!.size,
    )) {
      throw const _InstalledFailure('helper_image_mismatch');
    }
    payloadLock = WindowsUpdateFile.open(payload.path);
    if (!payloadLock!.verifySha256(package!.sha256, package!.size)) {
      throw const _InstalledFailure('payload_invalid');
    }
    final identity = await const WindowsInstalledPreflight().inspect(
      target: request.target,
      executable: p.join(request.target, 'equis.exe'),
      runningVersion: UpdateVersion(request.oldVersion, request.oldBuild),
      updateVersion: manifest.version,
      package: package!,
      payload: payload,
    );
    if (identity.hive != request.hive ||
        identity.sid != request.sid ||
        !p.equals(identity.target, request.target) ||
        identity.requiresElevation != request.requiresElevation) {
      throw const _InstalledFailure('registration_mismatch');
    }
    await _verifyRegisteredTarget();
    final pipeName = r'\\.\pipe\Equis.Update.' + request.transaction;
    pipe = WindowsUpdatePipeServer.create(pipeName, request.sid);
    appMessages = StreamIterator<String>(_boundedAppLines(stdin));
    await _emit(request.transaction, 'PREPARED');
    final first = await _readAppMessage();
    if (first['type'] == 'ABORT') {
      throw const _InstalledFailure('aborted');
    }
    if (first['type'] != 'START_SETUP' || !appProcess!.isAlive) {
      throw const _InstalledFailure('invalid_app_sequence');
    }
    await _rejectPendingJournal();
    payloadLock!.revalidate();
    await oldCatalog!.revalidate();
    final setupArguments = [
      '/EQUISMANAGEDUPDATE',
      '/EQUISTRANSACTION=${request.transaction}',
      '/EQUISPIPE=$pipeName',
      '/DIR=${request.target}',
      request.hive == 'HKLM' ? '/ALLUSERS' : '/CURRENTUSER',
      '/NOCLOSEAPPLICATIONS',
      '/NORESTART',
      '/NORESTARTAPPLICATIONS',
      '/NOFORCECLOSEAPPLICATIONS',
      '/LOG=${p.join(request.cache, 'installed-${request.transaction}', 'inno.log')}',
    ].map(_quoteWindowsArgument).join(' ');
    loader = await WindowsUpdateNative.launchSetup(
      executable: payload.path,
      arguments: setupArguments,
      workingDirectory: request.cache,
      elevate: request.requiresElevation,
    );
    // A cancelled wizard never connects. Observe its loader without imposing
    // a deadline on UAC or on the user's interaction with the wizard.
    loaderExit = loader!.waitForExit();
    final accepting = pipe!.accept();
    connection = await Future.any<WindowsUpdatePipeConnection?>([
      accepting,
      loaderExit!.then<WindowsUpdatePipeConnection?>((_) => null),
    ]);
    if (connection == null) {
      await pipe!.close();
      try {
        await (await accepting).close();
      } catch (_) {}
      final code = await loaderExit!;
      await _writeJournal({
        'state': 'cancelled',
        'transaction': request.transaction,
        'target': request.target,
        'innoExit': code,
        'code': code == 2 ? 'wizard_cancelled' : 'setup_ended_before_install',
        'log': p.join(
          request.cache,
          'installed-${request.transaction}',
          'inno.log',
        ),
      });
      await _emit(
        request.transaction,
        'RESULT',
        code: code == 2 ? 'wizard_cancelled' : 'setup_ended_before_install',
      );
      return false;
    }
    setup = connection!.process;
    await _verifySetupClient(self);
    final requestLine = await connection!.readLine();
    final expected = [
      'EQUIS_UPDATE_2',
      'INSTALL_REQUEST',
      request.transaction,
      request.hive,
      request.newVersion,
      '${request.newBuild}',
      request.target,
    ].join('\t');
    if (requestLine != expected) {
      await connection!.writeLine(
        'EQUIS_UPDATE_2\tABORT\t${request.transaction}',
      );
      throw const _InstalledFailure('installer_request_mismatch');
    }
    final closeDeadline = DateTime.now().add(const Duration(seconds: 120));
    // A lost response cannot prove that the app never began dismantling its
    // workspace. Recovery still requires observing its exit and intact files.
    closeStarted = true;
    await _emit(
      request.transaction,
      'CLOSE_REQUEST',
      closeDeadlineMillis: closeDeadline.millisecondsSinceEpoch,
    );
    final close = await _readAppMessage(
      timeout: _remainingCloseTime(closeDeadline),
    );
    if (close['type'] == 'CLOSE_FAILED') {
      closeStarted = close['closeStarted'] as bool;
      await connection!.writeLine(
        'EQUIS_UPDATE_2\tABORT\t${request.transaction}',
      );
      if (closeStarted) {
        await _restartOldIfIntact();
      }
      throw const _InstalledFailure('close_aborted');
    }
    if (close['type'] != 'CLOSE_OK') {
      await connection!.writeLine(
        'EQUIS_UPDATE_2\tABORT\t${request.transaction}',
      );
      throw const _InstalledFailure('invalid_close_response');
    }
    closeStarted = true;
    try {
      await appProcess!.waitForExit(
        timeout: _remainingCloseTime(closeDeadline),
      );
      appExited = true;
    } on WindowsUpdateNativeException catch (error) {
      if (error.code != 'process_wait_timeout') rethrow;
      await connection!.writeLine(
        'EQUIS_UPDATE_2\tABORT\t${request.transaction}',
      );
      throw const _InstalledFailure('app_exit_timeout');
    }
    payloadLock!.revalidate();
    if (!payloadLock!.verifySha256(package!.sha256, package!.size)) {
      await connection!.writeLine(
        'EQUIS_UPDATE_2\tABORT\t${request.transaction}',
      );
      throw const _InstalledFailure('payload_changed');
    }
    await oldCatalog!.revalidate();
    await _verifyRegisteredTarget();
    await _writeJournal({
      'state': 'installation_started',
      'transaction': request.transaction,
      'target': request.target,
      'hive': request.hive,
      'build': request.newBuild,
      'log': p.join(
        request.cache,
        'installed-${request.transaction}',
        'inno.log',
      ),
    });
    await oldCatalog!.close();
    oldCatalog = null;
    // From this point a failed write is ambiguous: the client may have read GO.
    goSent = true;
    await connection!.writeLine('EQUIS_UPDATE_2\tGO\t${request.transaction}');
    // Inno may create a distinct extracted setup process. Its pipe handle is
    // the process whose exit code decides the result; the loader is secondary.
    final setupExit = await setup!.waitForExit();
    await loaderExit!;
    if (setupExit != 0) {
      await _writeJournal({
        'state': 'manual_recovery',
        'transaction': request.transaction,
        'target': request.target,
        'code': 'setup_failed',
        'innoExit': setupExit,
      });
      await _emitBestEffort(
        request.transaction,
        'RESULT',
        code: 'setup_failed',
      );
      return false;
    }
    final next = await WindowsUpdateCatalog.inspect(request.target);
    try {
      if (next.version != request.newVersion ||
          next.build != request.newBuild ||
          next.rawHash != package!.trustCatalogSha256) {
        throw const _InstalledFailure('postverify_failed');
      }
      await _verifyRegisteredTarget(expectedVersion: request.newVersion);
    } finally {
      await next.close();
    }
    await _writeJournal({
      'state': 'relaunch_consumed',
      'transaction': request.transaction,
      'target': request.target,
      'build': request.newBuild,
      'outcome': 'success',
    });
    try {
      await Process.start(
        p.join(request.target, 'equis.exe'),
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: request.target,
      );
      await _writeJournal({
        'state': 'completed',
        'transaction': request.transaction,
        'target': request.target,
        'build': request.newBuild,
      });
      await _emitBestEffort(request.transaction, 'RESULT', code: 'ok');
      return true;
    } catch (_) {
      await _emitBestEffort(
        request.transaction,
        'RESULT',
        code: 'relaunch_failed',
      );
      return false;
    }
  }

  Future<void> _verifySetupClient(WindowsUpdateProcess helper) async {
    if (setup == null ||
        !setup!.isAlive ||
        setup!.sid != request.sid ||
        setup!.session != helper.session ||
        setup!.integrityRid != (request.requiresElevation ? 0x3000 : 0x2000)) {
      throw const _InstalledFailure('installer_identity_mismatch');
    }
  }

  Future<void> _verifyRegisteredTarget({String? expectedVersion}) async {
    final system = const NativeWindowsInstallSystem();
    final selected = await system.installLocation(request.hive);
    final opposite = await system.installLocation(
      request.hive == 'HKCU' ? 'HKLM' : 'HKCU',
    );
    if (selected == null ||
        opposite != null ||
        !p.equals(p.absolute(selected), request.target) ||
        !p.equals(await system.canonicalDirectory(selected), request.target) ||
        !await system.hasLocalInnoMarker(request.target) ||
        await system.registeredVersion(request.hive) !=
            (expectedVersion ?? request.oldVersion)) {
      throw const _InstalledFailure('postverify_registration_mismatch');
    }
  }

  Future<void> _restartOldIfIntact() async {
    if (!closeStarted || goSent || oldCatalog == null) return;
    try {
      await appProcess!.waitForExit(timeout: const Duration(seconds: 120));
      appExited = true;
      await oldCatalog!.revalidate();
      await _verifyRegisteredTarget();
      await oldCatalog!.close();
      oldCatalog = null;
      await _writeJournal({
        'state': 'relaunch_consumed',
        'transaction': request.transaction,
        'target': request.target,
        'build': request.oldBuild,
        'outcome': 'close_failed_old_intact',
      });
      await Process.start(
        p.join(request.target, 'equis.exe'),
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: request.target,
      );
    } catch (_) {
      // A failed old relaunch is manual recovery. Never retry automatically.
    }
  }

  Future<Map<String, Object?>> _readAppMessage({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final more = await appMessages!.moveNext().timeout(timeout);
    if (!more) throw const _InstalledFailure('app_channel_closed');
    final line = appMessages!.current;
    if (utf8.encode(line).length > 8192) {
      throw const _InstalledFailure('app_message_too_large');
    }
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 2 ||
        decoded['transaction'] != request.transaction ||
        decoded['type'] is! String ||
        !{
          'START_SETUP',
          'CLOSE_OK',
          'CLOSE_FAILED',
          'ABORT',
        }.contains(decoded['type'])) {
      throw const _InstalledFailure('invalid_app_message');
    }
    final expected = decoded['type'] == 'CLOSE_FAILED'
        ? const {'format', 'transaction', 'type', 'closeStarted'}
        : const {'format', 'transaction', 'type'};
    if (!_exactKeys(decoded, expected) ||
        (decoded['type'] == 'CLOSE_FAILED' &&
            decoded['closeStarted'] is! bool)) {
      throw const _InstalledFailure('invalid_app_message');
    }
    return decoded;
  }

  Future<void> _rejectPendingJournal() async {
    if (!await journal.exists()) return;
    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const _InstalledFailure('journal_invalid');
    }
    if ({
      'installation_started',
      'manual_recovery',
      'relaunch_consumed',
    }.contains(decoded['state'])) {
      throw const _InstalledFailure('manual_recovery_required');
    }
  }

  Future<void> _writeJournal(Map<String, Object?> value) async {
    final pending = File('${journal.path}.new');
    await pending.writeAsString(jsonEncode(value), flush: true);
    await pending.rename(journal.path);
  }

  Future<void> reportError(String code, int win32, {String? detail}) async {
    if (errorReported) return;
    errorReported = true;
    if (mutex == null) {
      // A lease loser must not touch installation.json. Keep useful diagnostics
      // in its own existing attempt directory instead.
      if (detail != null) {
        try {
          await File(
            p.join(
              request.cache,
              'installed-${request.transaction}',
              'helper-error.json',
            ),
          ).writeAsString(
            jsonEncode({'code': code, 'win32Error': win32, 'detail': detail}),
            flush: true,
          );
        } catch (_) {}
      }
      await _emitBestEffort(request.transaction, 'ERROR', code: code);
      return;
    }
    if (!goSent && connection != null) {
      try {
        await connection!.writeLine(
          'EQUIS_UPDATE_2\tABORT\t${request.transaction}',
        );
      } catch (_) {}
    }
    if (closeStarted && !goSent && oldCatalog != null) {
      await _restartOldIfIntact();
    }
    if (!goSent && await journal.exists()) {
      try {
        final existing = jsonDecode(await journal.readAsString());
        if (existing is Map &&
            {
              'installation_started',
              'manual_recovery',
              'relaunch_consumed',
            }.contains(existing['state'])) {
          await _emitBestEffort(request.transaction, 'ERROR', code: code);
          return;
        }
      } catch (_) {
        // Preserve unreadable state; never overwrite a potentially pending GO.
        await _emitBestEffort(request.transaction, 'ERROR', code: code);
        return;
      }
    }
    if (!goSent) {
      await _writeJournal({
        'state': 'preflight_failed',
        'transaction': request.transaction,
        'target': request.target,
        'code': code,
        'win32Error': win32,
        'log': p.join(
          request.cache,
          'installed-${request.transaction}',
          'inno.log',
        ),
        'detail': ?detail,
      });
    } else {
      await _writeJournal({
        'state': 'manual_recovery',
        'transaction': request.transaction,
        'target': request.target,
        'code': code,
        'win32Error': win32,
        'log': p.join(
          request.cache,
          'installed-${request.transaction}',
          'inno.log',
        ),
        'detail': ?detail,
      });
    }
    await _emitBestEffort(request.transaction, 'ERROR', code: code);
  }

  Future<void> close() async {
    await appMessages?.cancel();
    await connection?.close();
    await pipe?.close();
    await oldCatalog?.close();
    payloadLock?.close();
    selfLock?.close();
    mutex?.close();
    setup?.close();
    loader?.close();
    appProcess?.close();
    selfProcess?.close();
  }
}

Future<void> _emitBestEffort(
  String transaction,
  String type, {
  String? code,
}) async {
  try {
    await _emit(transaction, type, code: code);
  } catch (_) {
    // The app may already have exited and closed its stdout reader.
  }
}

String _quoteWindowsArgument(String value) {
  if (value.contains('\u0000')) {
    throw const _InstalledFailure('invalid_setup_argument');
  }
  final result = StringBuffer('"');
  final slashes = StringBuffer();
  for (final unit in value.codeUnits) {
    final char = String.fromCharCode(unit);
    if (char == r'\') {
      slashes.write(r'\');
      continue;
    }
    final prefix = slashes.toString();
    if (char == '"') {
      result.write(prefix);
      result.write(prefix);
      result.write(r'\"');
    } else {
      result.write(prefix);
      result.write(char);
    }
    slashes.clear();
  }
  final trailing = slashes.toString();
  result.write(trailing);
  result.write(trailing);
  result.write('"');
  return result.toString();
}

Future<void> _emit(
  String transaction,
  String type, {
  String? code,
  int? closeDeadlineMillis,
}) async {
  final encoded = jsonEncode({
    'format': 2,
    'transaction': transaction,
    'type': type,
    'code': ?code,
    'closeDeadlineMillis': ?closeDeadlineMillis,
  });
  if (utf8.encode(encoded).length > 8192) {
    throw const _InstalledFailure('helper_message_too_large');
  }
  stdout.writeln(encoded);
  await stdout.flush().timeout(const Duration(seconds: 30));
}

Duration _remainingCloseTime(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw const _InstalledFailure('app_exit_timeout');
  }
  return remaining;
}

Stream<String> _boundedAppLines(Stream<List<int>> input) async* {
  final bytes = <int>[];
  await for (final chunk in input) {
    for (final byte in chunk) {
      if (byte == 10) {
        yield utf8.decode(bytes, allowMalformed: false);
        bytes.clear();
      } else {
        if (byte == 0 || byte == 13 || bytes.length >= 8192) {
          throw const _InstalledFailure('invalid_app_line');
        }
        bytes.add(byte);
      }
    }
  }
  if (bytes.isNotEmpty) {
    throw const _InstalledFailure('truncated_app_message');
  }
}

bool _exactKeys(Map<String, dynamic> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

bool _validVersion(String value) {
  final match = _versionPattern.firstMatch(value);
  return match != null &&
      utf8.encode(value).length <= 32 &&
      match
          .groups([1, 2, 3])
          .every((part) => BigInt.parse(part!) <= BigInt.from(2147483647));
}

Future<void> _rejectLinks(String path) async {
  var current = p.absolute(path);
  while (true) {
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const _InstalledFailure('linked_path');
    }
    final parent = p.dirname(current);
    if (parent == current) return;
    current = parent;
  }
}
