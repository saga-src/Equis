import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secure_string_store.dart';
import 'vault_identity.dart';

enum VaultKeyPurpose {
  localDatabase('equis/local-database/v1'),
  syncRecords('equis/sync-records/v1'),
  attachments('equis/attachments/v1'),
  backups('equis/backups/v1');

  const VaultKeyPurpose(this.context);

  final String context;
}

final class VaultKeyManager {
  VaultKeyManager({
    SecureStringStore? store,
    Random? random,
    this.protocolVersion = 1,
  }) : _store = store ?? const FlutterSecureStringStore(),
       _random = random ?? Random.secure();

  static const masterKeyLength = 32;
  static const _currentVersionKey = 'equis.vault_master_key.current_version';
  static const _pendingVersionKey =
      'equis.vault_master_key.pending_recovery_version';
  static const _pendingMasterKey = 'equis.vault_master_key.pending_recovery';
  static const _derivationSalt = 'equis/vmk-derivation-salt/v1';

  final SecureStringStore _store;
  final Random _random;
  final int protocolVersion;

  Future<VaultIdentity?> vaultIdentity() async {
    final value =
        await _store.read('equis.vault.identity') ??
        await _store.read('equis.v2.identity');
    return value == null
        ? null
        : VaultIdentity.fromJson(
            Map<String, Object?>.from(jsonDecode(value) as Map),
          );
  }

  Future<VaultIdentity> requireVault(String vaultId) async {
    final identity = await vaultIdentity();
    if (identity == null || identity.vaultId != vaultId) {
      throw StateError('Vault key unavailable');
    }
    return identity;
  }

  Future<VaultIdentity> ensureVault(String vaultId) async {
    final identity = await vaultIdentity();
    if (identity != null) return requireVault(vaultId);
    final created = VaultIdentity.create(vaultId);
    await installVaultIdentity(created);
    return created;
  }

  Future<void> installVaultIdentity(VaultIdentity identity) async {
    final old = await vaultIdentity();
    if (old != null &&
        (old.vaultId != identity.vaultId ||
            await old.fingerprint() != await identity.fingerprint() ||
            (old.ownerId != null && old.ownerId != identity.ownerId))) {
      throw StateError('Vault identity mismatch');
    }
    await _store.write('equis.vault.identity', jsonEncode(identity.toJson()));
  }

  // Only purpose-derived keys cross devices. Database keys and master keys
  // remain local. One atomic secure-storage value contains each vault's ring.
  Future<List<Map<String, Object?>>> exportPortableKeys(String vaultId) async {
    final result = await _portableKeys(vaultId);
    final version = await currentVersion();
    for (final purpose in [
      VaultKeyPurpose.syncRecords,
      VaultKeyPurpose.attachments,
    ]) {
      final encoded = base64UrlEncode(
        await (await deriveKey(purpose, version: version)).extractBytes(),
      );
      if (!result.any(
        (row) =>
            row['purpose'] == purpose.name &&
            row['version'] == version &&
            row['key'] == encoded,
      )) {
        result.add({
          'purpose': purpose.name,
          'version': version,
          'key': encoded,
        });
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _portableKeys(String vaultId) async {
    final raw = await _store.read('equis.portable_keys.$vaultId');
    return raw == null ? [] : validatePortableKeys(jsonDecode(raw));
  }

  static List<Map<String, Object?>> validatePortableKeys(Object? value) {
    if (value is! List || value.length > 64) {
      throw const FormatException('Invalid portable keys');
    }
    return value.map((item) {
      if (item is! Map ||
          !['syncRecords', 'attachments'].contains(item['purpose']) ||
          item['version'] is! int ||
          (item['version'] as int) < 1 ||
          item['key'] is! String ||
          base64Url.decode(item['key'] as String).length != 32) {
        throw const FormatException('Invalid portable keys');
      }
      return <String, Object?>{
        'purpose': item['purpose'],
        'version': item['version'],
        'key': item['key'],
      };
    }).toList();
  }

  Future<void> importPortableKeys(String vaultId, Object? value) async {
    final incoming = validatePortableKeys(value);
    final combined = await _portableKeys(vaultId);
    for (final row in incoming) {
      if (!combined.any(
        (old) =>
            old['purpose'] == row['purpose'] &&
            old['version'] == row['version'] &&
            old['key'] == row['key'],
      )) {
        combined.add(row);
      }
    }
    validatePortableKeys(combined);
    await _store.write('equis.portable_keys.$vaultId', jsonEncode(combined));
  }

  Future<List<SecretKey>> decryptionKeys(
    String vaultId,
    VaultKeyPurpose purpose,
    int version,
  ) async {
    if (protocolVersion == 2) {
      if (version != 1) return [];
      return [await (await requireVault(vaultId)).derive(purpose.context)];
    }
    final result = <SecretKey>[];
    // Reading ciphertext must not silently generate a missing key version.
    try {
      result.add(await _derive(await loadMasterKey(version), purpose));
    } on StateError {
      /* Imported versions can still be available. */
    }
    for (final row in await _portableKeys(vaultId)) {
      if (row['purpose'] == purpose.name && row['version'] == version) {
        result.add(SecretKey(base64Url.decode(row['key'] as String)));
      }
    }
    return result;
  }

  Future<int> currentVersion() async {
    final encoded = await _store.read(_currentVersionKey);
    if (encoded == null) return 1;
    final version = int.tryParse(encoded);
    if (version == null || version < 1) {
      throw StateError('The stored vault key version is invalid.');
    }
    return version;
  }

  Future<SecretKey> loadOrCreateMasterKey({int? version}) async {
    final selectedVersion = version ?? await currentVersion();
    _validateVersion(selectedVersion);
    final storageKey = _storageKey(selectedVersion);
    var encoded = await _store.read(storageKey);
    if (encoded == null) {
      final generated = List<int>.generate(
        masterKeyLength,
        (_) => _random.nextInt(256),
        growable: false,
      );
      encoded = base64UrlEncode(generated);
      await _store.write(storageKey, encoded);
      if (selectedVersion == 1 &&
          await _store.read(_currentVersionKey) == null) {
        await _store.write(_currentVersionKey, '1');
      }
    }
    return SecretKey(_decodeMasterKey(encoded));
  }

  Future<SecretKey> loadMasterKey(int version) async {
    _validateVersion(version);
    final encoded = await _store.read(_storageKey(version));
    if (encoded == null) {
      throw StateError('The requested vault key version is unavailable.');
    }
    return SecretKey(_decodeMasterKey(encoded));
  }

  Future<SecretKey> deriveKey(VaultKeyPurpose purpose, {int? version}) async {
    if (protocolVersion == 2) {
      final identity = await vaultIdentity();
      if (identity == null ||
          (version != null && version != 1) ||
          purpose == VaultKeyPurpose.localDatabase) {
        throw StateError('Vault key unavailable');
      }
      return identity.derive(purpose.context);
    }
    final selectedVersion = version ?? await currentVersion();
    final masterKey = await loadOrCreateMasterKey(version: selectedVersion);
    return _derive(masterKey, purpose);
  }

  Future<SecretKey> _derive(SecretKey masterKey, VaultKeyPurpose purpose) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: masterKey,
        nonce: utf8.encode(_derivationSalt),
        info: utf8.encode(purpose.context),
      );

  Future<List<int>> stageRecoveredMasterKey({
    required int version,
    required SecretKey masterKey,
  }) async {
    _validateVersion(version);
    final bytes = await masterKey.extractBytes();
    if (bytes.length != masterKeyLength) {
      throw ArgumentError.value(bytes.length, 'masterKey');
    }
    await _store.write(_pendingMasterKey, base64UrlEncode(bytes));
    await _store.write(_pendingVersionKey, version.toString());
    return (await _derive(
      SecretKey(bytes),
      VaultKeyPurpose.localDatabase,
    )).extractBytes();
  }

  Future<List<int>?> pendingLocalDatabaseKey() async {
    final encoded = await _store.read(_pendingMasterKey);
    final version = int.tryParse(await _store.read(_pendingVersionKey) ?? '');
    if (encoded == null || version == null || version < 1) return null;
    return (await _derive(
      SecretKey(_decodeMasterKey(encoded)),
      VaultKeyPurpose.localDatabase,
    )).extractBytes();
  }

  Future<void> resolvePendingAfterCurrentKeyOpened() async {
    final pending = await _store.read(_pendingMasterKey);
    final version = int.tryParse(await _store.read(_pendingVersionKey) ?? '');
    if (pending == null || version == null) return;
    final current = await _store.read(_storageKey(version));
    if (current == pending) {
      await commitPendingRecovery();
    } else {
      await discardPendingRecovery();
    }
  }

  Future<void> commitPendingRecovery() async {
    final pending = await _store.read(_pendingMasterKey);
    final version = int.tryParse(await _store.read(_pendingVersionKey) ?? '');
    if (pending == null || version == null || version < 1) {
      throw StateError('No valid pending vault recovery exists.');
    }
    _decodeMasterKey(pending);
    await _store.write(_storageKey(version), pending);
    await _store.write(_currentVersionKey, version.toString());
    await discardPendingRecovery();
  }

  Future<void> discardPendingRecovery() async {
    await _store.delete(_pendingMasterKey);
    await _store.delete(_pendingVersionKey);
  }

  Future<int> createNextVersion() async {
    final next = await currentVersion() + 1;
    if (next > 0x7fffffff) {
      throw StateError('The vault key version range is exhausted.');
    }
    if (await _store.read(_storageKey(next)) != null) {
      throw StateError('The next vault key version already exists.');
    }
    await loadOrCreateMasterKey(version: next);
    return next;
  }

  Future<void> activateVersion(int version) async {
    _validateVersion(version);
    if (await _store.read(_storageKey(version)) == null) {
      throw StateError('Cannot activate an unavailable vault key version.');
    }
    await _store.write(_currentVersionKey, version.toString());
  }

  Future<void> importRecoveredMasterKey({
    required int version,
    required SecretKey masterKey,
    bool makeCurrent = false,
  }) async {
    _validateVersion(version);
    final bytes = await masterKey.extractBytes();
    if (bytes.length != masterKeyLength) {
      throw ArgumentError.value(
        bytes.length,
        'masterKey',
        'A vault master key must contain 32 bytes.',
      );
    }
    final key = _storageKey(version);
    final existing = await _store.read(key);
    final encoded = base64UrlEncode(bytes);
    if (existing != null && existing != encoded) {
      throw StateError('A different vault key already exists at this version.');
    }
    if (existing == null) await _store.write(key, encoded);
    if (makeCurrent) await activateVersion(version);
  }

  List<int> _decodeMasterKey(String encoded) {
    try {
      final bytes = base64Url.decode(encoded);
      if (bytes.length != masterKeyLength) {
        throw const FormatException('invalid length');
      }
      return bytes;
    } on FormatException {
      throw StateError('The stored vault master key is invalid.');
    }
  }

  static String _storageKey(int version) => 'equis.vault_master_key.v$version';

  static void _validateVersion(int version) {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
  }
}
