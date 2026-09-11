import 'dart:typed_data';

import '../../core/serialization/canonical_json.dart';

final class SyncRecordIdentity {
  SyncRecordIdentity({
    required this.vaultId,
    required this.recordId,
    required this.entityType,
    required this.revision,
  }) {
    if (!_uuid.hasMatch(vaultId) || !_uuid.hasMatch(recordId)) {
      throw ArgumentError('Sync identities must be canonical UUID strings.');
    }
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entityType)) {
      throw ArgumentError.value(entityType, 'entityType', 'Invalid type.');
    }
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'Must not be negative.');
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final String vaultId;
  final String recordId;
  final String entityType;
  final int revision;

  List<int> aad({required int cipherVersion, required int keyVersion}) =>
      CanonicalJson.encodeUtf8({
        'cipher_version': cipherVersion,
        'entity_type': entityType,
        'key_version': keyVersion,
        'record_id': recordId,
        'revision': revision,
        'vault_id': vaultId,
      });
}

final class EncryptedPayloadEnvelope {
  EncryptedPayloadEnvelope({
    required this.cipherVersion,
    required this.keyVersion,
    required List<int> nonce,
    required List<int> cipherText,
    required List<int> mac,
  }) : nonce = List<int>.unmodifiable(nonce),
       cipherText = List<int>.unmodifiable(cipherText),
       mac = List<int>.unmodifiable(mac) {
    if (cipherVersion < 1 || keyVersion < 1) {
      throw ArgumentError('Cipher and key versions must be positive.');
    }
    if (nonce.length != nonceLength || mac.length != macLength) {
      throw ArgumentError('The encrypted payload envelope is malformed.');
    }
  }

  static const cipherVersion1 = 1;
  static const nonceLength = 24;
  static const macLength = 16;
  static const _keyVersionPrefixLength = 4;

  final int cipherVersion;
  final int keyVersion;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Uint8List get cloudCiphertext {
    final result = Uint8List(
      _keyVersionPrefixLength + cipherText.length + mac.length,
    );
    ByteData.sublistView(result).setUint32(0, keyVersion, Endian.big);
    result.setRange(
      _keyVersionPrefixLength,
      _keyVersionPrefixLength + cipherText.length,
      cipherText,
    );
    result.setRange(
      _keyVersionPrefixLength + cipherText.length,
      result.length,
      mac,
    );
    return result;
  }

  factory EncryptedPayloadEnvelope.fromCloud({
    required int cipherVersion,
    required List<int> nonce,
    required List<int> ciphertext,
  }) {
    if (ciphertext.length < _keyVersionPrefixLength + macLength) {
      throw const PayloadFormatException();
    }
    final bytes = Uint8List.fromList(ciphertext);
    final keyVersion = ByteData.sublistView(bytes).getUint32(0, Endian.big);
    final macStart = bytes.length - macLength;
    return EncryptedPayloadEnvelope(
      cipherVersion: cipherVersion,
      keyVersion: keyVersion,
      nonce: nonce,
      cipherText: bytes.sublist(_keyVersionPrefixLength, macStart),
      mac: bytes.sublist(macStart),
    );
  }
}

final class EncryptedSyncRecord {
  const EncryptedSyncRecord({
    required this.identity,
    required this.envelope,
    this.isDeleted = false,
  });

  final SyncRecordIdentity identity;
  final EncryptedPayloadEnvelope envelope;
  final bool isDeleted;

  Map<String, Object> toCloudColumns() => {
    'vault_id': identity.vaultId,
    'entity_type': identity.entityType,
    'record_id': identity.recordId,
    'revision': identity.revision,
    'cipher_version': envelope.cipherVersion,
    'nonce': Uint8List.fromList(envelope.nonce),
    'ciphertext': envelope.cloudCiphertext,
    'is_deleted': isDeleted,
  };
}

final class PayloadAuthenticationException implements Exception {
  const PayloadAuthenticationException();

  @override
  String toString() => 'Payload authentication failed.';
}

final class PayloadFormatException implements Exception {
  const PayloadFormatException();

  @override
  String toString() => 'Encrypted payload format is invalid.';
}

final class UnsupportedCipherVersionException implements Exception {
  const UnsupportedCipherVersionException();

  @override
  String toString() => 'Encrypted payload cipher version is unsupported.';
}
