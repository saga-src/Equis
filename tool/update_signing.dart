import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/updates/update_public_key.dart';
import 'package:equis/infrastructure/updates/update_manifest.dart';

// Never print private material. UPDATE_SIGNING_SEED is a base64 32-byte seed.
Future<void> main(List<String> args) async {
  final algorithm = Ed25519();
  if (args.length == 2 && args[0] == 'init') {
    final directory = Directory(args[1]);
    await directory.create(recursive: true);
    final keyFile = File('${directory.path}/ed25519.seed');
    if (await keyFile.exists()) throw StateError('Signing key already exists');
    final key = await algorithm.newKeyPair();
    await keyFile.writeAsString(
      base64Encode(await key.extractPrivateKeyBytes()),
      flush: true,
    );
    final public = base64Encode((await key.extractPublicKey()).bytes);
    await File(
      'lib/infrastructure/updates/update_public_key.dart',
    ).writeAsString(
      '// Public release verification key. Private seed stays outside Git.\n'
      "const updatePublicKey = '$public';\n",
    );
    return;
  }
  if (args.length != 4 || args[0] != 'sign') {
    throw ArgumentError(
      'init <private-directory> | sign <artifacts-directory> <version> <build>',
    );
  }
  final seed = Platform.environment['UPDATE_SIGNING_SEED'];
  if (seed == null) throw StateError('UPDATE_SIGNING_SEED is required');
  late final SimpleKeyPair key;
  try {
    final bytes = base64Decode(seed.trim());
    if (bytes.length != 32) throw const FormatException();
    key = await algorithm.newKeyPairFromSeed(bytes);
  } catch (_) {
    // FormatException/ArgumentError can otherwise echo the secret input.
    throw StateError('Invalid update signing secret');
  }
  if (base64Encode((await key.extractPublicKey()).bytes) != updatePublicKey) {
    throw StateError('Release signing key does not match the application');
  }
  final dir = Directory(args[1]);
  final version = args[2], build = int.parse(args[3]);
  UpdateVersion(version, build).compareTo(UpdateVersion(version, build));
  if (build < 1) throw ArgumentError('Build must be positive');
  final packages = <Map<String, Object>>[];
  for (final platform in ['android', 'windows-installed', 'windows-portable']) {
    final suffix = switch (platform) {
      'android' => 'Android-$version.apk',
      'windows-installed' => 'Windows-$version-setup.exe',
      _ => 'Windows-$version-portable.zip',
    };
    final file = File('${dir.path}/Equis-$suffix');
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    packages.add({
      'platform': platform,
      'file': file.uri.pathSegments.last,
      'size': await file.length(),
      'sha256': hash.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    });
  }
  final bytes = utf8.encode(
    jsonEncode({
      'format': 1,
      'applicationId': 'app.saga.equis',
      'version': version,
      'build': build,
      'tag': 'v$version',
      'packages': packages,
    }),
  );
  final signature = await algorithm.sign(bytes, keyPair: key);
  await File(
    '${dir.path}/update-manifest.json',
  ).writeAsBytes(bytes, flush: true);
  await File(
    '${dir.path}/update-manifest.sig',
  ).writeAsString(base64Encode(signature.bytes), flush: true);
}
