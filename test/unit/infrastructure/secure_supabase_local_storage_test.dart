import 'package:equis/infrastructure/cloud/secure_supabase_local_storage.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const projectRef = 'abcdefghijklmnopqrst';
  const legacySessionKey = 'sb-$projectRef-auth-token';

  test(
    'migrates a legacy session to secure storage then removes plaintext',
    () async {
      final secure = _MemorySecureStore();
      final legacy = _MemoryLegacyStore({legacySessionKey: 'session-json'});
      final storage = SecureSupabaseLocalStorage(
        projectRef: projectRef,
        secureStore: secure,
        legacyStore: legacy,
      );

      await storage.initialize();

      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), 'session-json');
      expect(legacy.values, isNot(contains(legacySessionKey)));
      expect(
        secure.values['equis.supabase.session.$projectRef.v1'],
        'session-json',
      );
    },
  );

  test('never writes a new session to legacy preferences', () async {
    final secure = _MemorySecureStore();
    final legacy = _MemoryLegacyStore();
    final storage = SecureSupabaseLocalStorage(
      projectRef: projectRef,
      secureStore: secure,
      legacyStore: legacy,
    );

    await storage.initialize();
    await storage.persistSession('new-session');

    expect(await storage.accessToken(), 'new-session');
    expect(legacy.values, isEmpty);

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('secure PKCE storage migrates and removes a legacy verifier', () async {
    const verifierKey = 'supabase.auth.token-code-verifier';
    final secure = _MemorySecureStore();
    final legacy = _MemoryLegacyStore({verifierKey: 'verifier'});
    final storage = SecureSupabasePkceStorage(
      projectRef: projectRef,
      secureStore: secure,
      legacyStore: legacy,
    );

    expect(await storage.getItem(key: verifierKey), 'verifier');
    expect(legacy.values, isNot(contains(verifierKey)));
    expect(secure.values.values, contains('verifier'));

    await storage.removeItem(key: verifierKey);
    expect(secure.values, isEmpty);
  });

  test('rejects unsafe project references before constructing storage', () {
    expect(
      () => SecureSupabaseLocalStorage(projectRef: '../unsafe'),
      throwsArgumentError,
    );
  });
}

final class _MemorySecureStore implements SecureStringStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _MemoryLegacyStore implements LegacyPreferenceStore {
  _MemoryLegacyStore([Map<String, String>? initial]) {
    if (initial != null) values.addAll(initial);
  }

  final values = <String, String>{};
  bool initialized = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<String?> read(String key) async {
    if (!initialized) throw StateError('not initialized');
    return values[key];
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}
