import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../application/ports/sync_payload_cryptography.dart';
import '../../application/sync/encrypted_sync_models.dart';
import 'canonical_json.dart';
import 'vault_key_manager.dart';

export '../../application/ports/sync_payload_cryptography.dart';
export '../../application/sync/encrypted_sync_models.dart';

final class SyncPayloadCipher implements SyncPayloadCryptography {
  SyncPayloadCipher({required this.keys, Cipher? cipher})
    : _cipher = cipher ?? Xchacha20.poly1305Aead();

  final VaultKeyManager keys;
  final Cipher _cipher;

  @override
  Future<EncryptedPayloadEnvelope> encrypt({
    required SyncRecordIdentity identity,
    required Map<String, Object?> payload,
    int? keyVersion,
    List<int>? nonce,
  }) async {
    if (keys.protocolVersion == 2) await keys.requireVault(identity.vaultId);
    final version = keyVersion ?? await keys.currentVersion();
    final selectedNonce = nonce ?? _cipher.newNonce();
    if (selectedNonce.length != EncryptedPayloadEnvelope.nonceLength) {
      throw ArgumentError.value(selectedNonce.length, 'nonce', 'Must be 24.');
    }
    final box = await _cipher.encrypt(
      CanonicalJson.encodeUtf8(payload),
      secretKey: await keys.deriveKey(
        VaultKeyPurpose.syncRecords,
        version: version,
      ),
      nonce: selectedNonce,
      aad: identity.aad(
        cipherVersion: EncryptedPayloadEnvelope.cipherVersion1,
        keyVersion: version,
      ),
    );
    return EncryptedPayloadEnvelope(
      cipherVersion: EncryptedPayloadEnvelope.cipherVersion1,
      keyVersion: version,
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  @override
  Future<Map<String, Object?>> decrypt({
    required SyncRecordIdentity identity,
    required EncryptedPayloadEnvelope envelope,
  }) async {
    if (envelope.cipherVersion != EncryptedPayloadEnvelope.cipherVersion1) {
      throw const UnsupportedCipherVersionException();
    }
    for (final candidate in await keys.decryptionKeys(
      identity.vaultId,
      VaultKeyPurpose.syncRecords,
      envelope.keyVersion,
    )) {
      try {
        final clearText = await _cipher.decrypt(
          SecretBox(
            envelope.cipherText,
            nonce: envelope.nonce,
            mac: Mac(envelope.mac),
          ),
          secretKey: candidate,
          aad: identity.aad(
            cipherVersion: envelope.cipherVersion,
            keyVersion: envelope.keyVersion,
          ),
        );
        final value = jsonDecode(utf8.decode(clearText));
        if (value is! Map<String, dynamic>) {
          throw const PayloadFormatException();
        }
        return Map<String, Object?>.from(value);
      } on SecretBoxAuthenticationError {
        continue;
      } on FormatException {
        throw const PayloadFormatException();
      }
    }
    throw const PayloadAuthenticationException();
  }
}
