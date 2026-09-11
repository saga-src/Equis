import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'canonical_json.dart';
import 'encrypted_payload_cipher.dart';
import 'vault_key_manager.dart';

final class WrappedAttachmentKey {
  WrappedAttachmentKey({
    required this.vaultId,
    required this.attachmentId,
    required this.keyVersion,
    required List<int> nonce,
    required List<int> wrappedKey,
  }) : nonce = List<int>.unmodifiable(nonce),
       wrappedKey = List<int>.unmodifiable(wrappedKey) {
    _validateIdentity(vaultId, attachmentId);
    if (keyVersion < 1 ||
        this.nonce.length != EncryptedPayloadEnvelope.nonceLength ||
        this.wrappedKey.length != 32 + EncryptedPayloadEnvelope.macLength) {
      throw const AttachmentCipherFormatException();
    }
  }

  final String vaultId;
  final String attachmentId;
  final int keyVersion;
  final List<int> nonce;
  final List<int> wrappedKey;

  Map<String, Object> toCloudColumns() => {
    'vault_id': vaultId,
    'attachment_id': attachmentId,
    'key_version': keyVersion,
    'cipher_version': EncryptedPayloadEnvelope.cipherVersion1,
    'wrapped_key': Uint8List.fromList(wrappedKey),
    'key_nonce': Uint8List.fromList(nonce),
  };

  List<int> aad() => CanonicalJson.encodeUtf8({
    'attachment_id': attachmentId,
    'cipher_version': EncryptedPayloadEnvelope.cipherVersion1,
    'key_version': keyVersion,
    'purpose': 'attachment-key',
    'vault_id': vaultId,
  });
}

final class EncryptedAttachmentChunk {
  EncryptedAttachmentChunk({
    required this.index,
    required List<int> nonce,
    required List<int> cipherText,
    required List<int> mac,
  }) : nonce = List<int>.unmodifiable(nonce),
       cipherText = List<int>.unmodifiable(cipherText),
       mac = List<int>.unmodifiable(mac) {
    if (index < 0 ||
        this.nonce.length != EncryptedPayloadEnvelope.nonceLength ||
        this.mac.length != EncryptedPayloadEnvelope.macLength) {
      throw const AttachmentCipherFormatException();
    }
  }

  final int index;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Uint8List toCloudBytes() =>
      Uint8List.fromList([...nonce, ...cipherText, ...mac]);
}

final class EncryptedAttachment {
  EncryptedAttachment({
    required this.wrappedKey,
    required List<EncryptedAttachmentChunk> chunks,
  }) : chunks = List<EncryptedAttachmentChunk>.unmodifiable(chunks);

  final WrappedAttachmentKey wrappedKey;
  final List<EncryptedAttachmentChunk> chunks;
}

final class AttachmentCipher {
  AttachmentCipher({required this.keys, Cipher? cipher})
    : _cipher = cipher ?? Xchacha20.poly1305Aead();

  final VaultKeyManager keys;
  final Cipher _cipher;

  Future<AttachmentEncryptionSession> createEncryptionSession({
    required String vaultId,
    required String attachmentId,
    int? keyVersion,
  }) async {
    _validateIdentity(vaultId, attachmentId);
    if (keys.protocolVersion == 2) await keys.requireVault(vaultId);
    final version = keyVersion ?? await keys.currentVersion();
    final attachmentKey = await _cipher.newSecretKey();
    final wrappingKey = await keys.deriveKey(
      VaultKeyPurpose.attachments,
      version: version,
    );
    final keyNonce = _cipher.newNonce();
    final draft = WrappedAttachmentKey(
      vaultId: vaultId,
      attachmentId: attachmentId,
      keyVersion: version,
      nonce: keyNonce,
      wrappedKey: List<int>.filled(48, 0),
    );
    final keyBytes = Uint8List.fromList(await attachmentKey.extractBytes());
    try {
      final wrapped = await _cipher.encrypt(
        keyBytes,
        secretKey: wrappingKey,
        nonce: keyNonce,
        aad: draft.aad(),
      );
      return AttachmentEncryptionSession._(
        cipher: _cipher,
        attachmentKey: attachmentKey,
        wrappedKey: WrappedAttachmentKey(
          vaultId: vaultId,
          attachmentId: attachmentId,
          keyVersion: version,
          nonce: keyNonce,
          wrappedKey: [...wrapped.cipherText, ...wrapped.mac.bytes],
        ),
      );
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  Future<AttachmentDecryptionSession> createDecryptionSession(
    WrappedAttachmentKey wrappedKey,
  ) async => AttachmentDecryptionSession._(
    cipher: _cipher,
    attachmentKey: await _unwrap(wrappedKey),
    wrappedKey: wrappedKey,
  );

  Future<EncryptedAttachment> encrypt({
    required String vaultId,
    required String attachmentId,
    required Stream<List<int>> clearChunks,
    int? keyVersion,
  }) async {
    final session = await createEncryptionSession(
      vaultId: vaultId,
      attachmentId: attachmentId,
      keyVersion: keyVersion,
    );
    final chunks = <EncryptedAttachmentChunk>[];
    var index = 0;
    await for (final clear in clearChunks) {
      chunks.add(await session.encryptChunk(index: index, clearText: clear));
      index++;
    }
    return EncryptedAttachment(wrappedKey: session.wrappedKey, chunks: chunks);
  }

  Future<Uint8List> decryptChunk({
    required WrappedAttachmentKey wrappedKey,
    required EncryptedAttachmentChunk chunk,
  }) async {
    try {
      return (await createDecryptionSession(wrappedKey)).decryptChunk(chunk);
    } on SecretBoxAuthenticationError {
      throw const AttachmentCipherAuthenticationException();
    }
  }

  Future<SecretKey> _unwrap(WrappedAttachmentKey wrappedKey) async {
    final macStart =
        wrappedKey.wrappedKey.length - EncryptedPayloadEnvelope.macLength;
    for (final candidate in await keys.decryptionKeys(
      wrappedKey.vaultId,
      VaultKeyPurpose.attachments,
      wrappedKey.keyVersion,
    )) {
      try {
        final bytes = await _cipher.decrypt(
          SecretBox(
            wrappedKey.wrappedKey.sublist(0, macStart),
            nonce: wrappedKey.nonce,
            mac: Mac(wrappedKey.wrappedKey.sublist(macStart)),
          ),
          secretKey: candidate,
          aad: wrappedKey.aad(),
        );
        if (bytes.length != 32) throw const AttachmentCipherFormatException();
        return SecretKey(bytes);
      } on SecretBoxAuthenticationError {
        continue;
      }
    }
    throw SecretBoxAuthenticationError();
  }

  static List<int> _chunkAad(WrappedAttachmentKey key, int index) =>
      CanonicalJson.encodeUtf8({
        'attachment_id': key.attachmentId,
        'chunk_index': index,
        'cipher_version': EncryptedPayloadEnvelope.cipherVersion1,
        'key_version': key.keyVersion,
        'purpose': 'attachment-chunk',
        'vault_id': key.vaultId,
      });
}

final class AttachmentEncryptionSession {
  const AttachmentEncryptionSession._({
    required this._cipher,
    required this._attachmentKey,
    required this.wrappedKey,
  });

  final Cipher _cipher;
  final SecretKey _attachmentKey;
  final WrappedAttachmentKey wrappedKey;

  Future<EncryptedAttachmentChunk> encryptChunk({
    required int index,
    required List<int> clearText,
  }) async {
    if (index < 0) throw const AttachmentCipherFormatException();
    final box = await _cipher.encrypt(
      clearText,
      secretKey: _attachmentKey,
      aad: AttachmentCipher._chunkAad(wrappedKey, index),
    );
    return EncryptedAttachmentChunk(
      index: index,
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
    );
  }
}

final class AttachmentDecryptionSession {
  const AttachmentDecryptionSession._({
    required this._cipher,
    required this._attachmentKey,
    required this.wrappedKey,
  });

  final Cipher _cipher;
  final SecretKey _attachmentKey;
  final WrappedAttachmentKey wrappedKey;

  Future<Uint8List> decryptChunk(EncryptedAttachmentChunk chunk) async {
    try {
      return Uint8List.fromList(
        await _cipher.decrypt(
          SecretBox(chunk.cipherText, nonce: chunk.nonce, mac: Mac(chunk.mac)),
          secretKey: _attachmentKey,
          aad: AttachmentCipher._chunkAad(wrappedKey, chunk.index),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const AttachmentCipherAuthenticationException();
    }
  }
}

void _validateIdentity(String vaultId, String attachmentId) {
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  if (!uuid.hasMatch(vaultId) || !uuid.hasMatch(attachmentId)) {
    throw const AttachmentCipherFormatException();
  }
}

final class AttachmentCipherAuthenticationException implements Exception {
  const AttachmentCipherAuthenticationException();

  @override
  String toString() => 'Attachment authentication failed.';
}

final class AttachmentCipherFormatException implements Exception {
  const AttachmentCipherFormatException();

  @override
  String toString() => 'Encrypted attachment data is invalid.';
}
