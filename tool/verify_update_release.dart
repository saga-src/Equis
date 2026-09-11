import 'dart:convert';
import 'dart:io';
import 'package:equis/infrastructure/updates/update_manifest.dart';
import 'package:equis/infrastructure/updates/update_public_key.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Expected artifact directory');
  final root = Directory(args.single);
  final manifest = await UpdateManifest.verify(
    await File('${root.path}/update-manifest.json').readAsBytes(),
    base64Decode(
      (await File('${root.path}/update-manifest.sig').readAsString()).trim(),
    ),
    base64Decode(updatePublicKey),
  );
  for (final package in manifest.packages) {
    await package.validate(File('${root.path}/${package.name}'));
    stdout.writeln('${package.sha256}  ${package.name}');
  }
  stdout.writeln('Verified Ed25519 manifest ${manifest.version}');
}
