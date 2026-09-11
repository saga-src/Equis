import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'canonical_json.dart';
import 'encrypted_payload_cipher.dart';
import 'vault_key_manager.dart';

final class RecoveryKdfParameters {
  const RecoveryKdfParameters({
    this.memoryKiB = 19 * 1024,
    this.iterations = 2,
    this.parallelism = 1,
    this.hashLength = 32,
    this.argonVersion = 19,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;
  final int argonVersion;

  void validate() {
    if (parallelism < 1 ||
        iterations < 1 ||
        memoryKiB < parallelism * 8 ||
        hashLength != 32 ||
        argonVersion != 19) {
      throw const RecoveryFormatException();
    }
  }

  Map<String, int> toJson() => {
    'argon_version': argonVersion,
    'hash_length': hashLength,
    'iterations': iterations,
    'memory_kib': memoryKiB,
    'parallelism': parallelism,
    'cipher_version': EncryptedPayloadEnvelope.cipherVersion1,
  };
}

final class RecoverySecret {
  RecoverySecret._(this._encoded);

  static const _prefix = 'equis-recovery-v1_';
  final String _encoded;

  factory RecoverySecret.fromRandomBytes(List<int> bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Must contain 32 bytes.',
      );
    }
    return RecoverySecret._(
      '$_prefix${base64UrlEncode(bytes).replaceAll('=', '')}',
    );
  }

  factory RecoverySecret.parse(String value) {
    if (!value.startsWith(_prefix)) throw const RecoveryFormatException();
    try {
      final encoded = value.substring(_prefix.length);
      final normalized = base64Url.normalize(encoded);
      if (base64Url.decode(normalized).length != 32) {
        throw const RecoveryFormatException();
      }
      return RecoverySecret._(value);
    } on FormatException {
      throw const RecoveryFormatException();
    }
  }

  String export() => _encoded;

  List<int> get _passwordBytes => utf8.encode(_encoded);

  @override
  String toString() => '[REDACTED RECOVERY SECRET]';
}

final class VaultRecoveryRecord {
  VaultRecoveryRecord({
    required this.vaultId,
    required List<int> wrappedVaultKey,
    required this.parameters,
    required List<int> salt,
    required List<int> nonce,
    required this.keyVersion,
  }) : wrappedVaultKey = List<int>.unmodifiable(wrappedVaultKey),
       salt = List<int>.unmodifiable(salt),
       nonce = List<int>.unmodifiable(nonce) {
    if (!_uuid.hasMatch(vaultId) ||
        wrappedVaultKey.length < EncryptedPayloadEnvelope.macLength ||
        salt.length < 16 ||
        nonce.length != EncryptedPayloadEnvelope.nonceLength ||
        keyVersion < 1) {
      throw const RecoveryFormatException();
    }
    parameters.validate();
  }

  factory VaultRecoveryRecord.fromCloudColumns(Map<String, Object> columns) {
    try {
      final rawParameters = columns['kdf_parameters'];
      if (columns['kdf'] != 'argon2id' || rawParameters is! Map) {
        throw const RecoveryFormatException();
      }
      int readInt(String key) {
        final value = rawParameters[key];
        if (value is! num || value.toInt() != value) {
          throw const RecoveryFormatException();
        }
        return value.toInt();
      }

      List<int> readBytes(String key) {
        final value = columns[key];
        if (value is! List<int>) throw const RecoveryFormatException();
        return value;
      }

      return VaultRecoveryRecord(
        vaultId: columns['vault_id'] as String,
        wrappedVaultKey: readBytes('wrapped_vault_key'),
        parameters: RecoveryKdfParameters(
          memoryKiB: readInt('memory_kib'),
          iterations: readInt('iterations'),
          parallelism: readInt('parallelism'),
          hashLength: readInt('hash_length'),
          argonVersion: readInt('argon_version'),
        ),
        salt: readBytes('salt'),
        nonce: readBytes('nonce'),
        keyVersion: columns['key_version'] as int,
      );
    } on RecoveryFormatException {
      rethrow;
    } on Object {
      throw const RecoveryFormatException();
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final String vaultId;
  final List<int> wrappedVaultKey;
  final RecoveryKdfParameters parameters;
  final List<int> salt;
  final List<int> nonce;
  final int keyVersion;

  Map<String, Object> toCloudColumns() => {
    'vault_id': vaultId,
    'wrapped_vault_key': Uint8List.fromList(wrappedVaultKey),
    'kdf': 'argon2id',
    'kdf_parameters': parameters.toJson(),
    'salt': Uint8List.fromList(salt),
    'nonce': Uint8List.fromList(nonce),
    'key_version': keyVersion,
  };

  List<int> aad() => CanonicalJson.encodeUtf8({
    'cipher': 'xchacha20-poly1305',
    'cipher_version': EncryptedPayloadEnvelope.cipherVersion1,
    'kdf': 'argon2id',
    'kdf_parameters': parameters.toJson(),
    'key_version': keyVersion,
    'vault_id': vaultId,
  });
}

final class VaultRecoveryPackage {
  const VaultRecoveryPackage({required this.secret, required this.record});

  final RecoverySecret secret;
  final VaultRecoveryRecord record;
}

final class VaultRecoveryService {
  VaultRecoveryService({
    required this.keys,
    RecoveryKdfParameters parameters = const RecoveryKdfParameters(),
    Random? random,
    Cipher? cipher,
    this.nonceGenerator,
  }) : _parameters = parameters,
       _random = random ?? Random.secure(),
       _cipher = cipher ?? Xchacha20.poly1305Aead() {
    parameters.validate();
  }

  final VaultKeyManager keys;
  final RecoveryKdfParameters _parameters;
  final Random _random;
  final Cipher _cipher;
  final List<int> Function()? nonceGenerator;

  Future<VaultRecoveryPackage> create({
    required String vaultId,
    int? keyVersion,
  }) async {
    final version = keyVersion ?? await keys.currentVersion();
    final secret = RecoverySecret.fromRandomBytes(_randomBytes(32));
    final salt = _randomBytes(16);
    final nonce = nonceGenerator?.call() ?? _cipher.newNonce();
    final draft = VaultRecoveryRecord(
      vaultId: vaultId,
      wrappedVaultKey: List<int>.filled(EncryptedPayloadEnvelope.macLength, 0),
      parameters: _parameters,
      salt: salt,
      nonce: nonce,
      keyVersion: version,
    );
    final kek = await _deriveKek(secret, salt, _parameters);
    final masterBytes = Uint8List.fromList(
      await (await keys.loadMasterKey(version)).extractBytes(),
    );
    try {
      final box = await _cipher.encrypt(
        masterBytes,
        secretKey: kek,
        nonce: nonce,
        aad: draft.aad(),
      );
      return VaultRecoveryPackage(
        secret: secret,
        record: VaultRecoveryRecord(
          vaultId: vaultId,
          wrappedVaultKey: [...box.cipherText, ...box.mac.bytes],
          parameters: _parameters,
          salt: salt,
          nonce: nonce,
          keyVersion: version,
        ),
      );
    } finally {
      masterBytes.fillRange(0, masterBytes.length, 0);
    }
  }

  Future<SecretKey> recover({
    required VaultRecoveryRecord record,
    required String recoverySecret,
  }) async {
    final secret = RecoverySecret.parse(recoverySecret);
    final macStart =
        record.wrappedVaultKey.length - EncryptedPayloadEnvelope.macLength;
    try {
      final clearText = await _cipher.decrypt(
        SecretBox(
          record.wrappedVaultKey.sublist(0, macStart),
          nonce: record.nonce,
          mac: Mac(record.wrappedVaultKey.sublist(macStart)),
        ),
        secretKey: await _deriveKek(secret, record.salt, record.parameters),
        aad: record.aad(),
      );
      if (clearText.length != VaultKeyManager.masterKeyLength) {
        throw const RecoveryFormatException();
      }
      return SecretKey(clearText);
    } on SecretBoxAuthenticationError {
      throw const RecoveryAuthenticationException();
    }
  }

  Future<void> restoreToSecureStorage({
    required VaultRecoveryRecord record,
    required String recoverySecret,
    bool makeCurrent = true,
  }) async {
    await keys.importRecoveredMasterKey(
      version: record.keyVersion,
      masterKey: await recover(record: record, recoverySecret: recoverySecret),
      makeCurrent: makeCurrent,
    );
  }

  Future<SecretKey> _deriveKek(
    RecoverySecret secret,
    List<int> salt,
    RecoveryKdfParameters parameters,
  ) => Argon2id(
    parallelism: parameters.parallelism,
    memory: parameters.memoryKiB,
    iterations: parameters.iterations,
    hashLength: parameters.hashLength,
  ).deriveKey(secretKey: SecretKey(secret._passwordBytes), nonce: salt);

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);
}

final class RecoveryAuthenticationException implements Exception {
  const RecoveryAuthenticationException();

  @override
  String toString() => 'Vault recovery authentication failed.';
}

final class RecoveryFormatException implements Exception {
  const RecoveryFormatException();

  @override
  String toString() => 'Vault recovery data is invalid.';
}
