import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// Transport only inside an authenticated backup or explicit key export.
/// Never include this object in diagnostic events.
final class VaultIdentity {
  VaultIdentity({
    required this.vaultId,
    required List<int> masterKey,
    this.ownerId,
  }) : masterKey = List.unmodifiable(masterKey) {
    if (!_uuid.hasMatch(vaultId) ||
        masterKey.length != 32 ||
        (ownerId != null && !_uuid.hasMatch(ownerId!))) {
      throw const FormatException('Invalid vault identity');
    }
  }
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  final String vaultId;
  final List<int> masterKey;
  final String? ownerId;
  factory VaultIdentity.create(String vaultId) {
    final random = Random.secure();
    return VaultIdentity(
      vaultId: vaultId,
      masterKey: List.generate(32, (_) => random.nextInt(256)),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 2,
    'vault_id': vaultId,
    'master_key': base64UrlEncode(masterKey),
    'owner_id': ownerId,
  };
  factory VaultIdentity.fromJson(Map<String, Object?> value) {
    if (value['protocol'] != 2 ||
        value['vault_id'] is! String ||
        value['master_key'] is! String ||
        (value['owner_id'] != null && value['owner_id'] is! String)) {
      throw const FormatException('Invalid vault identity');
    }
    return VaultIdentity(
      vaultId: value['vault_id']! as String,
      masterKey: base64Url.decode(value['master_key']! as String),
      ownerId: value['owner_id'] as String?,
    );
  }
  String exportKey() => 'equis-vault:$vaultId:${base64UrlEncode(masterKey)}';
  factory VaultIdentity.fromKey(String key, {String? ownerId}) {
    final parts = key.trim().split(':');
    if (parts.length != 3 ||
        !{'equis-vault', 'equis-vault-v2'}.contains(parts.first)) {
      throw const FormatException('Invalid vault key');
    }
    return VaultIdentity(
      vaultId: parts[1],
      masterKey: base64Url.decode(parts[2]),
      ownerId: ownerId,
    );
  }
  Future<String> fingerprint() async => (await Sha256().hash([
    ...utf8.encode('equis/vault-identity/v2/$vaultId/'),
    ...masterKey,
  ])).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Future<SecretKey> derive(String purpose) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(masterKey),
        nonce: utf8.encode('equis/vault/v2/$vaultId'),
        info: utf8.encode(purpose),
      );
}
