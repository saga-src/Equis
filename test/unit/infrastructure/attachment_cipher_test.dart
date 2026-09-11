import 'dart:convert';

import 'package:equis/infrastructure/security/attachment_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vaultId = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const attachmentId = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
  final clearChunks = [
    utf8.encode('private receipt'),
    List<int>.generate(64, (i) => i),
  ];

  test('encrypts every attachment chunk before cloud storage', () async {
    final cipher = _cipher(7);
    final encrypted = await cipher.encrypt(
      vaultId: vaultId,
      attachmentId: attachmentId,
      clearChunks: Stream.fromIterable(clearChunks),
    );

    expect(encrypted.chunks, hasLength(2));
    expect(encrypted.wrappedKey.toCloudColumns().keys, {
      'vault_id',
      'attachment_id',
      'key_version',
      'cipher_version',
      'wrapped_key',
      'key_nonce',
    });
    expect(
      encrypted.chunks.first.toCloudBytes(),
      isNot(containsAll(clearChunks.first)),
    );
    expect(
      await cipher.decryptChunk(
        wrappedKey: encrypted.wrappedKey,
        chunk: encrypted.chunks[0],
      ),
      clearChunks[0],
    );
    expect(
      await cipher.decryptChunk(
        wrappedKey: encrypted.wrappedKey,
        chunk: encrypted.chunks[1],
      ),
      clearChunks[1],
    );
  });

  test('uses independent attachment keys and random nonces', () async {
    final cipher = _cipher(11);
    final first = await cipher.encrypt(
      vaultId: vaultId,
      attachmentId: attachmentId,
      clearChunks: Stream.value(clearChunks.first),
    );
    final second = await cipher.encrypt(
      vaultId: vaultId,
      attachmentId: attachmentId,
      clearChunks: Stream.value(clearChunks.first),
    );

    expect(second.wrappedKey.wrappedKey, isNot(first.wrappedKey.wrappedKey));
    expect(second.chunks.single.nonce, isNot(first.chunks.single.nonce));
    expect(
      second.chunks.single.cipherText,
      isNot(first.chunks.single.cipherText),
    );
  });

  test('tampering or binding to another attachment fails closed', () async {
    final cipher = _cipher(19);
    final encrypted = await cipher.encrypt(
      vaultId: vaultId,
      attachmentId: attachmentId,
      clearChunks: Stream.value(clearChunks.first),
    );
    final changed = List<int>.from(encrypted.chunks.single.cipherText)
      ..[0] ^= 1;
    final tampered = EncryptedAttachmentChunk(
      index: 0,
      nonce: encrypted.chunks.single.nonce,
      cipherText: changed,
      mac: encrypted.chunks.single.mac,
    );
    await expectLater(
      cipher.decryptChunk(wrappedKey: encrypted.wrappedKey, chunk: tampered),
      throwsA(isA<AttachmentCipherAuthenticationException>()),
    );

    final rebound = WrappedAttachmentKey(
      vaultId: vaultId,
      attachmentId: '018f47c2-9b72-7cc1-8b83-5d0fead0a003',
      keyVersion: encrypted.wrappedKey.keyVersion,
      nonce: encrypted.wrappedKey.nonce,
      wrappedKey: encrypted.wrappedKey.wrappedKey,
    );
    await expectLater(
      cipher.decryptChunk(wrappedKey: rebound, chunk: encrypted.chunks.single),
      throwsA(isA<AttachmentCipherAuthenticationException>()),
    );
  });
}

AttachmentCipher _cipher(int seed) => AttachmentCipher(
  keys: VaultKeyManager(
    store: _Store(base64UrlEncode(List<int>.generate(32, (i) => i + seed))),
  ),
);

final class _Store implements SecureStringStore {
  _Store(String master) : values = {'equis.vault_master_key.v1': master};
  final Map<String, String> values;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
