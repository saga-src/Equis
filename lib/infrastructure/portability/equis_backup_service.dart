import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import '../persistence/database/equis_database.dart';

import '../../core/serialization/canonical_json.dart';
import '../files/encrypted_attachment_file_codec.dart';
import '../files/equis_file_layout.dart';
import '../security/vault_recovery_service.dart';
import '../security/vault_key_manager.dart';
import '../security/vault_identity.dart';
import '../../domain/shared/uuid_v7.dart';
import 'vault_logical_snapshot_store.dart';

final class EquisBackupService {
  EquisBackupService({
    required this.snapshots,
    required this.attachments,
    required this.layout,
    RecoveryKdfParameters parameters = const RecoveryKdfParameters(),
    Random? random,
    Cipher? cipher,
  }) : _parameters = parameters,
       _random = random ?? Random.secure(),
       _cipher = cipher ?? Xchacha20.poly1305Aead() {
    parameters.validate();
  }

  static const format = 'equis-backup';
  static const formatVersion = 2;
  static const compatibilityPolicy =
      'A versão atual restaura backups com formato 1 e schema local igual ou '
      'anterior, desde que todas as tabelas lógicas obrigatórias existam.';

  final VaultLogicalSnapshotStore snapshots;
  final EncryptedAttachmentFileCodec attachments;
  final EquisFileLayout layout;
  final RecoveryKdfParameters _parameters;
  final Random _random;
  final Cipher _cipher;

  Future<EquisBackupInspection> create({
    required String vaultId,
    required String password,
    required File destination,
  }) async {
    if (password.length < 12) throw const EquisBackupWeakPassword();
    if (await destination.exists()) throw const EquisBackupFileExists();
    final captured = await snapshots.capture(vaultId);
    final snapshot = VaultLogicalSnapshot(
      schemaVersion: captured.schemaVersion,
      createdAtMicros: captured.createdAtMicros,
      tables: captured.tables,
      portableKeys: attachments.cipher.keys.protocolVersion == 1
          ? await attachments.cipher.keys.exportPortableKeys(vaultId)
          : null,
      vaultIdentity: attachments.cipher.keys.protocolVersion == 2
          ? (await attachments.cipher.keys.ensureVault(vaultId)).toJson()
          : null,
    );
    return _write(
      snapshot: snapshot,
      password: password,
      destination: destination,
      readAttachment: (id) => attachments.decryptBytes(
        source: layout.encryptedAttachment(vaultId: vaultId, attachmentId: id),
        vaultId: vaultId,
        attachmentId: id,
      ),
    );
  }

  Future<EquisBackupInspection> _write({
    required VaultLogicalSnapshot snapshot,
    required String password,
    required File destination,
    required Future<Uint8List> Function(String) readAttachment,
  }) async {
    if (password.length < 12) throw const EquisBackupWeakPassword();
    if (await destination.exists()) throw const EquisBackupFileExists();
    final createdAt = snapshot.createdAtMicros;
    final salt = _randomBytes(16);
    final keyNonce = _cipher.newNonce();
    final vaultNonce = _cipher.newNonce();
    final dataKeyBytes = Uint8List.fromList(_randomBytes(32));
    final dataKey = SecretKey(dataKeyBytes);
    final base = _baseManifest(
      version: snapshot.vaultIdentity == null ? 1 : 2,
      createdAtMicros: createdAt,
      schemaVersion: snapshot.schemaVersion,
      parameters: _parameters,
    );
    try {
      final wrapped = await _cipher.encrypt(
        dataKeyBytes,
        secretKey: await _deriveKek(password, salt, _parameters),
        nonce: keyNonce,
        aad: _aad(base, 'backup-data-key'),
      );
      final compressed = const ZLibEncoder().encodeBytes(
        snapshot.encode(),
        level: 9,
      );
      final vaultBox = await _cipher.encrypt(
        compressed,
        secretKey: dataKey,
        nonce: vaultNonce,
        aad: _aad(base, 'logical-vault'),
      );
      final vaultCipher = _boxBytes(vaultBox);
      final archive = Archive();
      archive.add(ArchiveFile.bytes('vault.enc', vaultCipher));
      final attachmentSpecs = <Map<String, Object>>[];
      final active = _activeAttachmentRows(snapshot);
      for (var index = 0; index < active.length; index++) {
        final row = active[index];
        final id = row['id']! as String;
        final entry =
            'attachments/${(index + 1).toString().padLeft(6, '0')}.enc';
        final clear = await readAttachment(id);
        final nonce = _cipher.newNonce();
        final box = await _cipher.encrypt(
          clear,
          secretKey: dataKey,
          nonce: nonce,
          aad: _aad(base, 'attachment:$entry'),
        );
        clear.fillRange(0, clear.length, 0);
        final encrypted = _boxBytes(box);
        archive.add(ArchiveFile.bytes(entry, encrypted));
        attachmentSpecs.add({
          'cipher_sha256': await _sha256(encrypted),
          'entry': entry,
          'nonce': base64UrlEncode(nonce),
        });
      }
      final manifest = <String, Object?>{
        ...base,
        'attachment_count': attachmentSpecs.length,
        'attachments': attachmentSpecs,
        'key_nonce': base64UrlEncode(keyNonce),
        'salt': base64UrlEncode(salt),
        'vault_cipher_sha256': await _sha256(vaultCipher),
        'vault_nonce': base64UrlEncode(vaultNonce),
        'wrapped_data_key': base64UrlEncode(_boxBytes(wrapped)),
      };
      archive.add(
        ArchiveFile.bytes('manifest.json', CanonicalJson.encodeUtf8(manifest)),
      );
      final encoded = ZipEncoder().encodeBytes(
        archive,
        level: 9,
        modified: DateTime.fromMicrosecondsSinceEpoch(createdAt, isUtc: true),
      );
      await destination.parent.create(recursive: true);
      final temporary = File('${destination.path}.part');
      if (await temporary.exists()) await temporary.delete();
      try {
        await temporary.writeAsBytes(encoded, flush: true);
        await temporary.rename(destination.path);
      } catch (_) {
        if (await temporary.exists()) await temporary.delete();
        rethrow;
      }
      return EquisBackupInspection(
        schemaVersion: snapshot.schemaVersion,
        createdAtMicros: createdAt,
        attachmentCount: active.length,
      );
    } finally {
      dataKeyBytes.fillRange(0, dataKeyBytes.length, 0);
    }
  }

  Future<EquisBackupInspection> validate({
    required File source,
    required String password,
  }) async {
    final decoded = await _readAndDecrypt(source, password);
    try {
      return decoded.inspection;
    } finally {
      _clear(decoded);
    }
  }

  Future<VaultIdentity> inspectIdentity({
    required File source,
    required String password,
  }) async {
    final decoded = await _readAndDecrypt(source, password);
    try {
      if (decoded.snapshot.vaultIdentity == null) {
        throw const LegacyBackupNeedsMigration();
      }
      return VaultIdentity.fromJson(decoded.snapshot.vaultIdentity!);
    } finally {
      _clear(decoded);
    }
  }

  Future<EquisBackupInspection> migrate({
    required File source,
    required String password,
    required File destination,
    required String newPassword,
  }) async {
    final decoded = await _readAndDecrypt(source, password);
    try {
      if (decoded.snapshot.vaultIdentity != null) {
        throw const BackupAlreadyMigrated();
      }
      final oldId = decoded.snapshot.tables['vaults']!.single['id'];
      final identity = VaultIdentity.create(EntityId.generate().value);
      final tables = <String, List<Map<String, Object?>>>{
        for (final entry in decoded.snapshot.tables.entries)
          entry.key: [
            for (final row in entry.value)
              {
                for (final field in row.entries)
                  field.key:
                      ((entry.key == 'vaults' && field.key == 'id') ||
                              field.key == 'vault_id') &&
                          field.value == oldId
                      ? identity.vaultId
                      : field.value,
              },
          ],
      };
      final snapshot = VaultLogicalSnapshot(
        schemaVersion: decoded.snapshot.schemaVersion,
        createdAtMicros: DateTime.now().toUtc().microsecondsSinceEpoch,
        tables: tables,
        vaultIdentity: identity.toJson(),
      );
      final validationDatabase = EquisDatabase(NativeDatabase.memory());
      try {
        await VaultLogicalSnapshotStore(validationDatabase).restore(snapshot);
        await validationDatabase.verifyIntegrity();
      } finally {
        await validationDatabase.close();
      }
      final inspection = await _write(
        snapshot: snapshot,
        password: newPassword,
        destination: destination,
        readAttachment: (id) async =>
            Uint8List.fromList(decoded.clearAttachments[id]!),
      );
      final checked = await _readAndDecrypt(destination, newPassword);
      try {
        if (CanonicalJson.encode(checked.snapshot.toJson()) !=
            CanonicalJson.encode(snapshot.toJson())) {
          throw const EquisBackupFormatException();
        }
      } finally {
        _clear(checked);
      }
      return inspection;
    } finally {
      _clear(decoded);
    }
  }

  void _clear(_DecodedBackup decoded) {
    for (final bytes in decoded.clearAttachments.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<EquisBackupInspection> restore({
    required File source,
    required String password,
  }) async {
    final decoded = await _readAndDecrypt(source, password);
    final vaultId = decoded.snapshot.tables['vaults']!.single['id']! as String;
    final existing = await snapshots.database
        .customSelect('SELECT id FROM vaults LIMIT 1')
        .getSingleOrNull();
    if (existing != null) {
      _clear(decoded);
      throw const VaultRestoreRequiresCleanProfile();
    }
    try {
      if (attachments.cipher.keys.protocolVersion == 2) {
        if (decoded.snapshot.vaultIdentity == null) {
          throw const LegacyBackupNeedsMigration();
        }
        await attachments.cipher.keys.installVaultIdentity(
          VaultIdentity.fromJson(decoded.snapshot.vaultIdentity!),
        );
      }
    } catch (_) {
      _clear(decoded);
      rethrow;
    }
    final localPaths = <String, String>{};
    final createdFiles = <File>[];
    try {
      for (final entry in decoded.clearAttachments.entries) {
        final destination = layout.encryptedAttachment(
          vaultId: vaultId,
          attachmentId: entry.key,
        );
        final result = await attachments.encryptBytes(
          clearBytes: entry.value,
          destination: destination,
          vaultId: vaultId,
          attachmentId: entry.key,
        );
        entry.value.fillRange(0, entry.value.length, 0);
        localPaths[entry.key] = result.file.path;
        createdFiles.add(result.file);
      }
      if (decoded.snapshot.portableKeys != null) {
        await attachments.cipher.keys.importPortableKeys(
          vaultId,
          decoded.snapshot.portableKeys,
        );
      }
      await snapshots.restore(
        decoded.snapshot,
        attachmentLocalPaths: localPaths,
      );
      return decoded.inspection;
    } catch (_) {
      for (final file in createdFiles.reversed) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    } finally {
      for (final bytes in decoded.clearAttachments.values) {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  Future<_DecodedBackup> _readAndDecrypt(File source, String password) async {
    if (password.isEmpty) throw const EquisBackupAuthenticationException();
    if (!await source.exists()) throw const EquisBackupNotFound();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        await source.readAsBytes(),
        verify: true,
      );
    } catch (_) {
      throw const EquisBackupFormatException();
    }
    final manifestFile = archive.find('manifest.json');
    final vaultFile = archive.find('vault.enc');
    if (manifestFile == null ||
        vaultFile == null ||
        manifestFile.size > 65536) {
      throw const EquisBackupFormatException();
    }
    Map<String, Object?> manifest;
    try {
      final decoded = jsonDecode(utf8.decode(manifestFile.readBytes()!));
      if (decoded is! Map<String, dynamic>) {
        throw const EquisBackupFormatException();
      }
      manifest = Map<String, Object?>.from(decoded);
    } catch (_) {
      throw const EquisBackupFormatException();
    }
    final parsed = _parseManifest(manifest);
    final expectedNames = {'manifest.json', 'vault.enc', ...parsed.entries};
    if (archive.length != expectedNames.length ||
        archive.any((file) => !expectedNames.contains(file.name))) {
      throw const EquisBackupFormatException();
    }
    final base = _baseManifest(
      version: parsed.version,
      createdAtMicros: parsed.createdAtMicros,
      schemaVersion: parsed.schemaVersion,
      parameters: parsed.parameters,
    );
    final vaultCipher = vaultFile.readBytes();
    if (vaultCipher == null ||
        await _sha256(vaultCipher) != parsed.vaultCipherSha256) {
      throw const EquisBackupFormatException();
    }
    SecretKey dataKey;
    try {
      dataKey = SecretKey(
        await _decryptBox(
          parsed.wrappedDataKey,
          nonce: parsed.keyNonce,
          key: await _deriveKek(password, parsed.salt, parsed.parameters),
          aad: _aad(base, 'backup-data-key'),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const EquisBackupAuthenticationException();
    }
    VaultLogicalSnapshot snapshot;
    try {
      final compressed = await _decryptBox(
        vaultCipher,
        nonce: parsed.vaultNonce,
        key: dataKey,
        aad: _aad(base, 'logical-vault'),
      );
      final clear = const ZLibDecoder().decodeBytes(compressed, verify: true);
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map) throw const EquisBackupFormatException();
      snapshot = VaultLogicalSnapshot.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (parsed.version == 2) {
        final identity = VaultIdentity.fromJson(snapshot.vaultIdentity!);
        if (identity.vaultId != snapshot.tables['vaults']!.single['id'] ||
            snapshot.portableKeys != null) {
          throw const EquisBackupFormatException();
        }
      }
      if (snapshot.portableKeys != null) {
        VaultKeyManager.validatePortableKeys(snapshot.portableKeys);
      }
    } on SecretBoxAuthenticationError {
      throw const EquisBackupAuthenticationException();
    } on EquisBackupFormatException {
      rethrow;
    } catch (_) {
      throw const EquisBackupFormatException();
    }
    if (snapshot.schemaVersion != parsed.schemaVersion) {
      throw const EquisBackupFormatException();
    }
    final rows = _activeAttachmentRows(snapshot);
    if (rows.length != parsed.attachmentSpecs.length) {
      throw const EquisBackupFormatException();
    }
    final clearAttachments = <String, Uint8List>{};
    for (var index = 0; index < rows.length; index++) {
      final spec = parsed.attachmentSpecs[index];
      final file = archive.find(spec.entry);
      final encrypted = file?.readBytes();
      if (encrypted == null || await _sha256(encrypted) != spec.cipherSha256) {
        throw const EquisBackupFormatException();
      }
      Uint8List clear;
      try {
        clear = Uint8List.fromList(
          await _decryptBox(
            encrypted,
            nonce: spec.nonce,
            key: dataKey,
            aad: _aad(base, 'attachment:${spec.entry}'),
          ),
        );
      } on SecretBoxAuthenticationError {
        throw const EquisBackupAuthenticationException();
      }
      final row = rows[index];
      if (clear.length != row['byte_size'] ||
          await _sha256(clear) != row['sha256']) {
        clear.fillRange(0, clear.length, 0);
        throw const EquisBackupFormatException();
      }
      clearAttachments[row['id']! as String] = clear;
    }
    return _DecodedBackup(
      snapshot: snapshot,
      clearAttachments: clearAttachments,
      inspection: EquisBackupInspection(
        schemaVersion: parsed.schemaVersion,
        createdAtMicros: parsed.createdAtMicros,
        attachmentCount: rows.length,
      ),
    );
  }

  Future<SecretKey> _deriveKek(
    String password,
    List<int> salt,
    RecoveryKdfParameters parameters,
  ) => Argon2id(
    parallelism: parameters.parallelism,
    memory: parameters.memoryKiB,
    iterations: parameters.iterations,
    hashLength: parameters.hashLength,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);

  Future<List<int>> _decryptBox(
    List<int> encrypted, {
    required List<int> nonce,
    required SecretKey key,
    required List<int> aad,
  }) {
    if (encrypted.length < 16) throw const EquisBackupFormatException();
    final macStart = encrypted.length - 16;
    return _cipher.decrypt(
      SecretBox(
        encrypted.sublist(0, macStart),
        nonce: nonce,
        mac: Mac(encrypted.sublist(macStart)),
      ),
      secretKey: key,
      aad: aad,
    );
  }
}

Map<String, Object?> _baseManifest({
  int version = 2,
  required int createdAtMicros,
  required int schemaVersion,
  required RecoveryKdfParameters parameters,
}) => {
  'archive': 'zip-deflate',
  'cipher': 'xchacha20-poly1305',
  'cipher_version': 1,
  'compression': 'zlib-deflate',
  'created_at_micros': createdAtMicros,
  'format': EquisBackupService.format,
  'format_version': version,
  'kdf': 'argon2id',
  'kdf_parameters': parameters.toJson(),
  'schema_version': schemaVersion,
};

List<int> _aad(Map<String, Object?> base, String purpose) =>
    CanonicalJson.encodeUtf8({...base, 'purpose': purpose});

Uint8List _boxBytes(SecretBox box) =>
    Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);

Future<String> _sha256(List<int> bytes) async =>
    _hex((await Sha256().hash(bytes)).bytes);

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<Map<String, Object?>> _activeAttachmentRows(
  VaultLogicalSnapshot snapshot,
) => [
  for (final row in snapshot.tables['attachments']!)
    if (row['deleted_at'] == null) row,
];

_ParsedManifest _parseManifest(Map<String, Object?> value) {
  try {
    if (value['format'] != EquisBackupService.format ||
        ![1, 2].contains(value['format_version']) ||
        value['archive'] != 'zip-deflate' ||
        value['compression'] != 'zlib-deflate' ||
        value['cipher'] != 'xchacha20-poly1305' ||
        value['cipher_version'] != 1 ||
        value['kdf'] != 'argon2id' ||
        value['schema_version'] is! int ||
        value['created_at_micros'] is! int ||
        value['attachment_count'] is! int ||
        value['attachments'] is! List ||
        value['kdf_parameters'] is! Map) {
      throw const EquisBackupFormatException();
    }
    final kdf = Map<String, Object?>.from(value['kdf_parameters']! as Map);
    final parameters = RecoveryKdfParameters(
      memoryKiB: kdf['memory_kib']! as int,
      iterations: kdf['iterations']! as int,
      parallelism: kdf['parallelism']! as int,
      hashLength: kdf['hash_length']! as int,
      argonVersion: kdf['argon_version']! as int,
    );
    parameters.validate();
    final specs = <_AttachmentSpec>[];
    for (final raw in value['attachments']! as List) {
      final map = Map<String, Object?>.from(raw as Map);
      final entry = map['entry']! as String;
      if (!RegExp(r'^attachments/[0-9]{6}\.enc$').hasMatch(entry)) {
        throw const EquisBackupFormatException();
      }
      specs.add(
        _AttachmentSpec(
          entry: entry,
          nonce: _base64(map['nonce']),
          cipherSha256: map['cipher_sha256']! as String,
        ),
      );
    }
    if (specs.length != value['attachment_count'] ||
        specs.map((spec) => spec.entry).toSet().length != specs.length) {
      throw const EquisBackupFormatException();
    }
    return _ParsedManifest(
      version: value['format_version']! as int,
      schemaVersion: value['schema_version']! as int,
      createdAtMicros: value['created_at_micros']! as int,
      parameters: parameters,
      salt: _base64(value['salt']),
      keyNonce: _base64(value['key_nonce']),
      wrappedDataKey: _base64(value['wrapped_data_key']),
      vaultNonce: _base64(value['vault_nonce']),
      vaultCipherSha256: value['vault_cipher_sha256']! as String,
      attachmentSpecs: specs,
    )..validate();
  } catch (error) {
    if (error is EquisBackupFormatException) rethrow;
    throw const EquisBackupFormatException();
  }
}

List<int> _base64(Object? value) {
  if (value is! String) throw const EquisBackupFormatException();
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    throw const EquisBackupFormatException();
  }
}

final class _ParsedManifest {
  const _ParsedManifest({
    required this.version,
    required this.schemaVersion,
    required this.createdAtMicros,
    required this.parameters,
    required this.salt,
    required this.keyNonce,
    required this.wrappedDataKey,
    required this.vaultNonce,
    required this.vaultCipherSha256,
    required this.attachmentSpecs,
  });

  final int version;
  final int schemaVersion;
  final int createdAtMicros;
  final RecoveryKdfParameters parameters;
  final List<int> salt;
  final List<int> keyNonce;
  final List<int> wrappedDataKey;
  final List<int> vaultNonce;
  final String vaultCipherSha256;
  final List<_AttachmentSpec> attachmentSpecs;
  List<String> get entries => [for (final spec in attachmentSpecs) spec.entry];

  void validate() {
    if (schemaVersion < 1 ||
        createdAtMicros < 0 ||
        salt.length < 16 ||
        keyNonce.length != 24 ||
        wrappedDataKey.length != 48 ||
        vaultNonce.length != 24 ||
        !_shaPattern.hasMatch(vaultCipherSha256) ||
        attachmentSpecs.any(
          (spec) =>
              spec.nonce.length != 24 ||
              !_shaPattern.hasMatch(spec.cipherSha256),
        )) {
      throw const EquisBackupFormatException();
    }
  }
}

final class _AttachmentSpec {
  const _AttachmentSpec({
    required this.entry,
    required this.nonce,
    required this.cipherSha256,
  });

  final String entry;
  final List<int> nonce;
  final String cipherSha256;
}

final _shaPattern = RegExp(r'^[0-9a-f]{64}$');

final class _DecodedBackup {
  const _DecodedBackup({
    required this.snapshot,
    required this.clearAttachments,
    required this.inspection,
  });

  final VaultLogicalSnapshot snapshot;
  final Map<String, Uint8List> clearAttachments;
  final EquisBackupInspection inspection;
}

final class EquisBackupInspection {
  const EquisBackupInspection({
    required this.schemaVersion,
    required this.createdAtMicros,
    required this.attachmentCount,
  });

  final int schemaVersion;
  final int createdAtMicros;
  final int attachmentCount;
}

final class EquisBackupWeakPassword implements Exception {
  const EquisBackupWeakPassword();
}

final class EquisBackupAuthenticationException implements Exception {
  const EquisBackupAuthenticationException();
}

final class EquisBackupFormatException implements Exception {
  const EquisBackupFormatException();
}

final class EquisBackupFileExists implements Exception {
  const EquisBackupFileExists();
}

final class EquisBackupNotFound implements Exception {
  const EquisBackupNotFound();
}

final class LegacyBackupNeedsMigration implements Exception {
  const LegacyBackupNeedsMigration();
}

final class BackupAlreadyMigrated implements Exception {
  const BackupAlreadyMigrated();
}
