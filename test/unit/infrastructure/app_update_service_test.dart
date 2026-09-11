import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/updates/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'signed newer-version update downloads, persists and observes six-hour interval',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = await Directory.systemTemp.createTemp('equis-update');
      addTearDown(() => dir.delete(recursive: true));
      final key = await Ed25519().newKeyPair();
      final public = base64Encode((await key.extractPublicKey()).bytes);
      final data = [1, 2, 3];
      final hash = (await Sha256().hash(
        data,
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final raw = utf8.encode(
        jsonEncode({
          'format': 1,
          'applicationId': 'app.saga.equis',
          'version': '1.0.1',
          'build': 7,
          'tag': 'v1.0.1',
          'packages': [
            {
              'platform': 'android',
              'file': 'update.apk',
              'size': 3,
              'sha256': hash,
            },
          ],
        }),
      );
      final signature = base64Encode(
        (await Ed25519().sign(raw, keyPair: key)).bytes,
      );
      var requests = 0;
      var truncate = false;
      final client = MockClient((r) async {
        requests++;
        if (r.url.path.endsWith('/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.0.1',
              'draft': false,
              'prerelease': false,
            }),
            200,
          );
        }
        if (r.url.path.endsWith('.json')) return http.Response.bytes(raw, 200);
        if (r.url.path.endsWith('.sig')) return http.Response(signature, 200);
        return http.Response.bytes(
          truncate ? data.take(2).toList() : data,
          200,
        );
      });
      final service = AppUpdateService(
        directory: dir,
        preferences: prefs,
        platform: 'android',
        client: client,
        verificationKey: public,
        network: () async => [ConnectivityResult.mobile],
      );
      addTearDown(service.dispose);
      await service.check();
      expect(service.status, UpdateStatus.wifi);
      final previousRequests = requests;
      await service.check();
      expect(requests, previousRequests);
      await service.download(allowMobile: true);
      expect(service.status, UpdateStatus.ready);
      expect(
        await (await service.validateForInstallation()).readAsBytes(),
        data,
      );
      final reopened = AppUpdateService(
        directory: dir,
        preferences: prefs,
        platform: 'android',
        verificationKey: public,
        client: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(reopened.dispose);
      await reopened.restore();
      expect(reopened.status, UpdateStatus.ready);
      await reopened.setAutomatic(false);
      expect(prefs.getBool('updates.automatic'), false);
      await service.packageFile!.delete();
      truncate = true;
      await service.download(allowMobile: true);
      expect(service.status, UpdateStatus.failed);
      expect(await service.packageFile!.exists(), false);
      expect(await File('${dir.path}/update.apk.part').exists(), false);
      truncate = false;
      await service.download(allowMobile: true);
      expect(service.status, UpdateStatus.ready);
    },
  );
  test(
    'private repository or no release is recoverable and needs no authentication',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('equis-404');
      addTearDown(() => dir.delete(recursive: true));
      final service = AppUpdateService(
        directory: dir,
        preferences: await SharedPreferences.getInstance(),
        platform: 'windows-portable',
        client: MockClient((r) async {
          expect(r.headers.containsKey('Authorization'), false);
          return http.Response('', 404);
        }),
      );
      addTearDown(service.dispose);
      await service.check(manual: true);
      expect(service.status, UpdateStatus.failed);
      expect(service.errorCode, 'http_404');
    },
  );
}
