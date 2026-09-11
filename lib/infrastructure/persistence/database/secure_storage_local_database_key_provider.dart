import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../security/secure_string_store.dart';
import '../../security/vault_key_manager.dart';
import 'local_database_lifecycle.dart';

final class SecureStorageLocalDatabaseKeyProvider
    implements RecoverableLocalDatabaseKeyProvider {
  SecureStorageLocalDatabaseKeyProvider({
    FlutterSecureStorage? storage,
    Random? random,
    VaultKeyManager? keyManager,
  }) : _keyManager =
           keyManager ??
           VaultKeyManager(
             store: FlutterSecureStringStore(
               storage ?? const FlutterSecureStorage(),
             ),
             random: random,
           );

  final VaultKeyManager _keyManager;

  @override
  Future<Uint8List> loadOrCreateKey() async {
    final derived = await _keyManager.deriveKey(VaultKeyPurpose.localDatabase);
    return Uint8List.fromList(await derived.extractBytes());
  }

  @override
  Future<Uint8List> stageRecoveredMasterKey({
    required int version,
    required SecretKey masterKey,
  }) async => Uint8List.fromList(
    await _keyManager.stageRecoveredMasterKey(
      version: version,
      masterKey: masterKey,
    ),
  );

  @override
  Future<Uint8List?> pendingLocalDatabaseKey() async {
    final key = await _keyManager.pendingLocalDatabaseKey();
    return key == null ? null : Uint8List.fromList(key);
  }

  @override
  Future<void> resolvePendingAfterCurrentKeyOpened() =>
      _keyManager.resolvePendingAfterCurrentKeyOpened();

  @override
  Future<void> commitPendingRecovery() => _keyManager.commitPendingRecovery();
}
