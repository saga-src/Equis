import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';

final class UpdateVersion implements Comparable<UpdateVersion> {
  const UpdateVersion(this.version, this.build);
  final String version;
  final int build;
  @override
  int compareTo(UpdateVersion other) {
    List<int> parts(String v) {
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v)) {
        throw const FormatException('Stable version required');
      }
      return v.split('.').map(int.parse).toList();
    }

    final a = parts(version), b = parts(other.version);
    for (var i = 0; i < 3; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  String toString() => version;
}

final class UpdatePackage {
  const UpdatePackage(this.platform, this.name, this.size, this.sha256);
  final String platform, name, sha256;
  final int size;
  factory UpdatePackage.fromJson(Map<String, dynamic> json) {
    final p = UpdatePackage(
      json['platform'] as String,
      json['file'] as String,
      json['size'] as int,
      json['sha256'] as String,
    );
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]+$').hasMatch(p.name) ||
        p.size <= 0 ||
        p.size > 2147483648 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(p.sha256) ||
        !const [
          'android',
          'windows-installed',
          'windows-portable',
        ].contains(p.platform) ||
        !p.name.endsWith(switch (p.platform) {
          'android' => '.apk',
          'windows-installed' => '.exe',
          _ => '.zip',
        })) {
      throw const FormatException('Invalid update package');
    }
    return p;
  }
  Future<void> validate(File file) async {
    if (await file.length() != size) {
      throw const FormatException('Package size mismatch');
    }
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = await sink.hash();
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (hex != sha256) throw const FormatException('Package hash mismatch');
  }
}

final class UpdateManifest {
  const UpdateManifest(this.version, this.tag, this.packages);
  final UpdateVersion version;
  final String tag;
  final List<UpdatePackage> packages;
  static Future<UpdateManifest> verify(
    List<int> bytes,
    List<int> signature,
    List<int> publicKey,
  ) async {
    if (bytes.length > 65536 ||
        signature.length != 64 ||
        publicKey.length != 32 ||
        !await Ed25519().verify(
          bytes,
          signature: Signature(
            signature,
            publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
          ),
        )) {
      throw const FormatException('Invalid manifest signature');
    }
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['format'] != 1 || j['applicationId'] != 'app.saga.equis') {
      throw const FormatException('Incompatible manifest');
    }
    final version = UpdateVersion(j['version'] as String, j['build'] as int);
    version.compareTo(version);
    if (version.build < 1 || j['tag'] != 'v${version.version}') {
      throw const FormatException('Invalid release identity');
    }
    final packages = (j['packages'] as List)
        .map((p) => UpdatePackage.fromJson(p as Map<String, dynamic>))
        .toList();
    if (packages.map((p) => p.platform).toSet().length != packages.length) {
      throw const FormatException('Duplicate platform');
    }
    return UpdateManifest(version, j['tag'] as String, packages);
  }
}
