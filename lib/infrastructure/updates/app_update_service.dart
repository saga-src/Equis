import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_manifest.dart';
import 'update_public_key.dart';

enum UpdateStatus {
  idle,
  checking,
  available,
  wifi,
  downloading,
  ready,
  failed,
  installing,
}

/// Installation-scoped: deliberately not owned by a vault's ProviderContainer.
final class AppUpdateService extends ChangeNotifier
    with WidgetsBindingObserver {
  AppUpdateService({
    required this.directory,
    required this.preferences,
    required this.platform,
    http.Client? client,
    this.verificationKey = updatePublicKey,
    this.network,
  }) : _client = client ?? http.Client();
  static const current = UpdateVersion(
    String.fromEnvironment('EQUIS_VERSION', defaultValue: '1.0.0'),
    int.fromEnvironment('EQUIS_BUILD', defaultValue: 6),
  );
  final Directory directory;
  final SharedPreferences preferences;
  final String platform;
  final String verificationKey;
  final Future<List<ConnectivityResult>> Function()? network;
  Future<List<ConnectivityResult>> _network() =>
      network?.call() ?? Connectivity().checkConnectivity();
  final http.Client _client;
  UpdateStatus status = UpdateStatus.idle;
  UpdateManifest? manifest;
  UpdatePackage? package;
  double progress = 0;
  String? errorCode;
  bool _busy = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool get automatic => preferences.getBool('updates.automatic') ?? true;
  File? get packageFile =>
      package == null ? null : File('${directory.path}/${package!.name}');
  static Future<AppUpdateService> create(String platform) async {
    final root = await getApplicationSupportDirectory();
    final service = AppUpdateService(
      directory: Directory('${root.path}/updates'),
      preferences: await SharedPreferences.getInstance(),
      platform: platform,
    );
    await service.directory.create(recursive: true);
    WidgetsBinding.instance.addObserver(service);
    service._connectivity = Connectivity().onConnectivityChanged.listen((_) {
      if (service.status == UpdateStatus.wifi && service.automatic) {
        unawaited(service.download());
      }
    });
    unawaited(service.restore());
    return service;
  }

  Future<void> restore() async {
    try {
      await _readCachedManifest();
      if (packageFile != null && await packageFile!.exists()) {
        await package!.validate(packageFile!);
        _set(UpdateStatus.ready);
      } else if (package != null) {
        _set(UpdateStatus.available);
        if (automatic) await download();
      }
    } catch (_) {
      manifest = null;
      package = null;
    }
    await check();
  }

  Future<void> _readCachedManifest() async {
    final bytes = await File('${directory.path}/manifest.json').readAsBytes();
    final sig = base64Decode(
      await File('${directory.path}/manifest.sig').readAsString(),
    );
    final candidate = await UpdateManifest.verify(
      bytes,
      sig,
      base64Decode(verificationKey),
    );
    if (candidate.version.compareTo(current) <= 0) return;
    final p = candidate.packages.where((p) => p.platform == platform).single;
    manifest = candidate;
    package = p;
  }

  Future<void> setAutomatic(bool value) async {
    await preferences.setBool('updates.automatic', value);
    notifyListeners();
    if (value && package != null && status != UpdateStatus.ready) {
      await download();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  void _set(UpdateStatus value, [String? code]) {
    status = value;
    errorCode = code;
    notifyListeners();
  }

  Future<List<int>> _get(Uri uri, int limit) async {
    final response = await _client
        .send(
          http.Request('GET', uri)
            ..headers['Accept'] = 'application/vnd.github+json',
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('http_${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('Response too large');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Uri _asset(String tag, String name) =>
      Uri.https('github.com', '/saga-src/Equis/releases/download/$tag/$name');
  Future<void> check({bool manual = false}) async {
    if (_busy || status == UpdateStatus.installing) return;
    final now = DateTime.now().toUtc();
    final last = preferences.getInt('updates.lastCheck');
    if (!manual &&
        last != null &&
        now.millisecondsSinceEpoch - last <
            const Duration(hours: 6).inMilliseconds) {
      return;
    }
    _busy = true;
    final previous = status;
    _set(UpdateStatus.checking);
    try {
      final bytes = await _get(
        Uri.https('api.github.com', '/repos/saga-src/Equis/releases/latest'),
        1048576,
      );
      final release = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (release['prerelease'] != false || release['draft'] != false) {
        throw const FormatException('Unstable release');
      }
      final tag = release['tag_name'] as String;
      if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
        throw const FormatException('Invalid stable release tag');
      }
      final raw = await _get(_asset(tag, 'update-manifest.json'), 65536);
      final sig = await _get(_asset(tag, 'update-manifest.sig'), 256);
      final candidate = await UpdateManifest.verify(
        raw,
        base64Decode(utf8.decode(sig).trim()),
        base64Decode(verificationKey),
      );
      if (candidate.tag != tag) throw const FormatException('Tag mismatch');
      if (candidate.version.compareTo(current) > 0 &&
          (manifest == null ||
              candidate.version.compareTo(manifest!.version) >= 0)) {
        final selected = candidate.packages
            .where((p) => p.platform == platform)
            .single;
        await File(
          '${directory.path}/manifest.json',
        ).writeAsBytes(raw, flush: true);
        await File(
          '${directory.path}/manifest.sig',
        ).writeAsBytes(sig, flush: true);
        manifest = candidate;
        package = selected;
        if (await packageFile!.exists()) {
          await selected.validate(packageFile!);
          _set(UpdateStatus.ready);
        } else {
          _set(UpdateStatus.available);
        }
      } else {
        _set(previous == UpdateStatus.ready ? previous : UpdateStatus.idle);
      }
    } on HttpException catch (e) {
      _set(
        previous == UpdateStatus.ready ? previous : UpdateStatus.failed,
        e.message,
      );
    } catch (_) {
      _set(
        previous == UpdateStatus.ready ? previous : UpdateStatus.failed,
        'verification_or_network',
      );
    } finally {
      await preferences.setInt('updates.lastCheck', now.millisecondsSinceEpoch);
      _busy = false;
    }
    if (automatic && status == UpdateStatus.available) await download();
  }

  Future<void> download({bool allowMobile = false}) async {
    if (_busy ||
        package == null ||
        manifest == null ||
        status == UpdateStatus.installing) {
      return;
    }
    _busy = true;
    final p = package!;
    File? partial;
    IOSink? sink;
    try {
      if (platform == 'android' &&
          !allowMobile &&
          !(await _network()).contains(ConnectivityResult.wifi)) {
        _set(UpdateStatus.wifi);
        return;
      }
      _set(UpdateStatus.downloading);
      progress = 0;
      partial = File('${directory.path}/${p.name}.part');
      final response = await _client
          .send(http.Request('GET', _asset(manifest!.tag, p.name)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw HttpException('http_${response.statusCode}');
      }
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        if (platform == 'android' &&
            !allowMobile &&
            !(await _network()).contains(ConnectivityResult.wifi)) {
          _set(UpdateStatus.wifi);
          return;
        }
        received += chunk.length;
        if (received > p.size) throw const FormatException('Oversized package');
        sink.add(chunk);
        progress = received / p.size;
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await p.validate(partial);
      await partial.rename(packageFile!.path);
      partial = null;
      _set(UpdateStatus.ready);
    } catch (_) {
      _set(UpdateStatus.failed, 'download_or_verification');
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        /* Disk failure. */
      }
      if (partial != null && await partial.exists()) await partial.delete();
      _busy = false;
    }
  }

  Future<File> validateForInstallation() async {
    await _readCachedManifest();
    if (manifest == null || manifest!.version.compareTo(current) <= 0) {
      throw StateError('No update');
    }
    await package!.validate(packageFile!);
    return packageFile!;
  }

  void installing() => _set(UpdateStatus.installing);
  void installationFailed() => _set(UpdateStatus.ready, 'installation');
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_connectivity?.cancel());
    _client.close();
    super.dispose();
  }
}
