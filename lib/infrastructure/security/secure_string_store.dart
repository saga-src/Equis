import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class PrefixedSecureStringStore implements SecureStringStore {
  const PrefixedSecureStringStore(this.store, this.prefix);
  final SecureStringStore store;
  final String prefix;
  @override
  Future<String?> read(String key) => store.read('$prefix$key');
  @override
  Future<void> write(String key, String value) =>
      store.write('$prefix$key', value);
  @override
  Future<void> delete(String key) => store.delete('$prefix$key');
}

abstract interface class SecureStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSecureStringStore implements SecureStringStore {
  const FlutterSecureStringStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
