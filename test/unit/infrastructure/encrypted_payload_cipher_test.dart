import 'dart:convert';

import 'package:equis/infrastructure/security/canonical_json.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final identity = SyncRecordIdentity(
    vaultId: '018f47c2-9b72-7cc1-8b83-5d0fead0a001',
    recordId: '018f47c2-9b72-7cc1-8b83-5d0fead0a002',
    entityType: 'transaction',
    revision: 7,
  );
  const payload = <String, Object?>{
    'schema': 1,
    'merchant': 'Synthetic Coffee',
    'amountMinor': 7290,
    'currency': 'BRL',
    'nested': <String, Object?>{'z': true, 'a': null},
  };
  final nonce = List<int>.generate(24, (index) => index);

  test('canonical JSON is independent of map insertion order', () {
    expect(
      CanonicalJson.encode({
        'z': 2,
        'a': {'b': 1, 'a': 0},
      }),
      '{"a":{"a":0,"b":1},"z":2}',
    );
    expect(
      CanonicalJson.encode({'a': 1, 'b': 2}),
      CanonicalJson.encode({'b': 2, 'a': 1}),
    );
  });

  test(
    'known vector and round trip use XChaCha20-Poly1305 with bound AAD',
    () async {
      final cipher = _cipher(List<int>.generate(32, (index) => index));

      final envelope = await cipher.encrypt(
        identity: identity,
        payload: payload,
        nonce: nonce,
      );

      expect(envelope.nonce, nonce);
      expect(envelope.mac, hasLength(16));
      expect(
        _hex(envelope.cloudCiphertext),
        '00000001235ed23ab5a9deebaa8f20fcbaa0ce0b9adcde6c1243b9438e155f2951fb201d622d6cd85de963b681a529e9b742d48e52d61ca08d357edbc6a0dc6228fcaa4894c245a650b3eb7f5faae759bda19e101142d767e1d4be8b0ccadf2a7b8896f1f98b35bbd3f2f693343ad6f70bf07aac8d382378597b32ac3710a6',
      );
      expect(
        await cipher.decrypt(identity: identity, envelope: envelope),
        payload,
      );
    },
  );

  test(
    'cloud columns expose metadata and ciphertext but no financial fields',
    () async {
      final envelope = await _cipher(
        List<int>.filled(32, 5),
      ).encrypt(identity: identity, payload: payload, nonce: nonce);
      final columns = EncryptedSyncRecord(
        identity: identity,
        envelope: envelope,
      ).toCloudColumns();

      expect(columns.keys, {
        'vault_id',
        'entity_type',
        'record_id',
        'revision',
        'cipher_version',
        'nonce',
        'ciphertext',
        'is_deleted',
      });
      expect(columns, isNot(contains('merchant')));
      expect(columns, isNot(contains('amountMinor')));
      final encodedCiphertext = base64Encode(
        columns['ciphertext']! as List<int>,
      );
      expect(encodedCiphertext, isNot(contains('Synthetic Coffee')));
      expect(encodedCiphertext, isNot(contains('7290')));

      final restored = EncryptedPayloadEnvelope.fromCloud(
        cipherVersion: columns['cipher_version']! as int,
        nonce: columns['nonce']! as List<int>,
        ciphertext: columns['ciphertext']! as List<int>,
      );
      expect(restored.keyVersion, envelope.keyVersion);
    },
  );

  test(
    'tampering ciphertext, MAC, nonce, or record AAD fails authentication',
    () async {
      final cipher = _cipher(List<int>.filled(32, 8));
      final envelope = await cipher.encrypt(
        identity: identity,
        payload: payload,
        nonce: nonce,
      );

      final variants = [
        _copy(envelope, cipherText: _flip(envelope.cipherText)),
        _copy(envelope, mac: _flip(envelope.mac)),
        _copy(envelope, nonce: _flip(envelope.nonce)),
      ];
      for (final tampered in variants) {
        await expectLater(
          cipher.decrypt(identity: identity, envelope: tampered),
          throwsA(isA<PayloadAuthenticationException>()),
        );
      }

      final moved = SyncRecordIdentity(
        vaultId: identity.vaultId,
        recordId: '018f47c2-9b72-7cc1-8b83-5d0fead0a003',
        entityType: identity.entityType,
        revision: identity.revision,
      );
      await expectLater(
        cipher.decrypt(identity: moved, envelope: envelope),
        throwsA(isA<PayloadAuthenticationException>()),
      );
    },
  );

  test('wrong VMK cannot decrypt an otherwise valid envelope', () async {
    final envelope = await _cipher(
      List<int>.filled(32, 3),
    ).encrypt(identity: identity, payload: payload, nonce: nonce);

    await expectLater(
      _cipher(
        List<int>.filled(32, 4),
      ).decrypt(identity: identity, envelope: envelope),
      throwsA(isA<PayloadAuthenticationException>()),
    );
  });
}

SyncPayloadCipher _cipher(List<int> masterKey) => SyncPayloadCipher(
  keys: VaultKeyManager(
    store: _MemorySecureStore({
      'equis.vault_master_key.v1': base64UrlEncode(masterKey),
    }),
  ),
);

EncryptedPayloadEnvelope _copy(
  EncryptedPayloadEnvelope value, {
  List<int>? nonce,
  List<int>? cipherText,
  List<int>? mac,
}) => EncryptedPayloadEnvelope(
  cipherVersion: value.cipherVersion,
  keyVersion: value.keyVersion,
  nonce: nonce ?? value.nonce,
  cipherText: cipherText ?? value.cipherText,
  mac: mac ?? value.mac,
);

List<int> _flip(List<int> bytes) {
  final result = List<int>.from(bytes);
  result[0] ^= 1;
  return result;
}

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _MemorySecureStore implements SecureStringStore {
  _MemorySecureStore(this.values);
  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
