import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HKDF separates all four approved key purposes', () async {
    final store = _MemorySecureStore({
      'equis.vault_master_key.v1': base64UrlEncode(
        List<int>.generate(32, (index) => index),
      ),
    });
    final manager = VaultKeyManager(store: store);

    final derived = <String>{};
    for (final purpose in VaultKeyPurpose.values) {
      derived.add(
        _hex(await (await manager.deriveKey(purpose)).extractBytes()),
      );
    }

    expect(derived, hasLength(VaultKeyPurpose.values.length));
    expect(
      _hex(
        await (await manager.deriveKey(
          VaultKeyPurpose.localDatabase,
        )).extractBytes(),
      ),
      'e553554298bacc9e0bb342a147a90dbba029d863df0f026ae7f5205b89e9369e',
    );
  });

  test('prepares a new version without activating it prematurely', () async {
    final store = _MemorySecureStore();
    final manager = VaultKeyManager(store: store, random: _FixedRandom(11));
    await manager.loadOrCreateMasterKey();

    final next = await manager.createNextVersion();

    expect(next, 2);
    expect(await manager.currentVersion(), 1);
    expect(store.values, contains('equis.vault_master_key.v2'));

    await manager.activateVersion(next);
    expect(await manager.currentVersion(), 2);
  });

  test('recovery import cannot overwrite a different key version', () async {
    final store = _MemorySecureStore({
      'equis.vault_master_key.v1': base64UrlEncode(List<int>.filled(32, 1)),
    });
    final manager = VaultKeyManager(store: store);

    await expectLater(
      manager.importRecoveredMasterKey(
        version: 1,
        masterKey: SecretKey(List<int>.filled(32, 2)),
      ),
      throwsStateError,
    );
  });

  test('invalid secure-storage data fails closed', () async {
    final manager = VaultKeyManager(
      store: _MemorySecureStore({'equis.vault_master_key.v1': 'bad'}),
    );

    await expectLater(manager.loadOrCreateMasterKey(), throwsStateError);
  });

  test('staged recovery commits atomically over the bootstrap key', () async {
    final store = _MemorySecureStore({
      'equis.vault_master_key.v1': base64UrlEncode(List<int>.filled(32, 1)),
      'equis.vault_master_key.current_version': '1',
    });
    final manager = VaultKeyManager(store: store);

    final pendingDatabaseKey = await manager.stageRecoveredMasterKey(
      version: 1,
      masterKey: SecretKey(List<int>.filled(32, 2)),
    );

    expect(pendingDatabaseKey, hasLength(32));
    expect(await manager.pendingLocalDatabaseKey(), pendingDatabaseKey);
    await manager.commitPendingRecovery();
    expect(
      await (await manager.loadMasterKey(1)).extractBytes(),
      List<int>.filled(32, 2),
    );
    expect(await manager.pendingLocalDatabaseKey(), isNull);
  });

  test('unrekeyed recovery is discarded after the current key opens', () async {
    final original = base64UrlEncode(List<int>.filled(32, 1));
    final store = _MemorySecureStore({
      'equis.vault_master_key.v1': original,
      'equis.vault_master_key.current_version': '1',
    });
    final manager = VaultKeyManager(store: store);
    await manager.stageRecoveredMasterKey(
      version: 1,
      masterKey: SecretKey(List<int>.filled(32, 2)),
    );

    await manager.resolvePendingAfterCurrentKeyOpened();

    expect(store.values['equis.vault_master_key.v1'], original);
    expect(await manager.pendingLocalDatabaseKey(), isNull);
  });
}

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _MemorySecureStore implements SecureStringStore {
  _MemorySecureStore([Map<String, String>? initial]) {
    if (initial != null) values.addAll(initial);
  }

  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _FixedRandom implements Random {
  const _FixedRandom(this.value);
  final int value;

  @override
  bool nextBool() => value.isOdd;

  @override
  double nextDouble() => value / 256;

  @override
  int nextInt(int max) => value % max;
}
