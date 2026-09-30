import 'dart:convert';
import 'dart:io';
import 'package:equis/infrastructure/updates/update_manifest.dart';
import 'package:equis/infrastructure/updates/update_public_key.dart';
import 'update_signing.dart' show verifyWindowsCatalogInPortable;

Future<void> main(List<String> args) async {
  final testMode = args.length == 2 && args.first == '--test';
  if (testMode) args = [args.last];
  if (args.length != 1) throw ArgumentError('Expected artifact directory');
  final root = Directory(args.single);
  final manifest = await UpdateManifest.verify(
    await File('${root.path}/update-manifest.json').readAsBytes(),
    base64Decode(
      (await File('${root.path}/update-manifest.sig').readAsString()).trim(),
    ),
    base64Decode(
      testMode
          ? Platform.environment['EQUIS_UPDATE_TEST_PUBLIC_KEY'] ?? ''
          : updatePublicKey,
    ),
    expectedApplicationId: testMode
        ? 'app.saga.equis.update-test'
        : 'app.saga.equis',
  );
  for (final package in manifest.packages) {
    await package.validate(File('${root.path}/${package.name}'));
    stdout.writeln('${package.sha256}  ${package.name}');
  }
  if (manifest.version.compareTo(const UpdateVersion('1.2.0', 12)) >= 0) {
    final installed = manifest.packages.singleWhere(
      (package) => package.platform == 'windows-installed',
    );
    final expected = installed.trustCatalogSha256;
    if (expected == null ||
        expected !=
            await verifyWindowsCatalogInPortable(
              root,
              manifest.version.version,
              manifest.version.build,
              testMode: testMode,
            )) {
      throw const FormatException('Windows trust catalog differs from release');
    }
  }
  stdout.writeln('Verified Ed25519 manifest ${manifest.version}');
}
