import 'dart:convert';
import 'dart:math';

import 'package:equis/infrastructure/persistence/database/secure_storage_local_database_key_provider.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'derives the stable v1 database key without changing existing VMK',
    () async {
      final master = List<int>.generate(32, (index) => index);
      final store = _MemorySecureStore({
        'equis.vault_master_key.v1': base64UrlEncode(master),
      });
      final provider = SecureStorageLocalDatabaseKeyProvider(
        keyManager: VaultKeyManager(store: store),
      );

      final first = await provider.loadOrCreateKey();
      final second = await provider.loadOrCreateKey();

      expect(
        _hex(first),
        'e553554298bacc9e0bb342a147a90dbba029d863df0f026ae7f5205b89e9369e',
      );
      expect(first, second);
      expect(first, isNot(master));
      expect(
        base64Url.decode(store.values['equis.vault_master_key.v1']!),
        master,
      );
    },
  );

  test(
    'creates one random 256-bit VMK when the secure store is empty',
    () async {
      final store = _MemorySecureStore();
      final provider = SecureStorageLocalDatabaseKeyProvider(
        keyManager: VaultKeyManager(store: store, random: _FixedRandom(7)),
      );

      final key = await provider.loadOrCreateKey();

      expect(key, hasLength(32));
      expect(
        base64Url.decode(store.values['equis.vault_master_key.v1']!),
        everyElement(7),
      );
      expect(store.values['equis.vault_master_key.current_version'], '1');
    },
  );
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
