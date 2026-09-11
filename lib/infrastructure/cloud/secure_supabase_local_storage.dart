import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/secure_string_store.dart';

abstract interface class LegacyPreferenceStore {
  Future<void> initialize();

  Future<String?> read(String key);

  Future<void> remove(String key);
}

final class SharedPreferencesLegacyPreferenceStore
    implements LegacyPreferenceStore {
  SharedPreferences? _preferences;

  @override
  Future<void> initialize() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _ready =>
      _preferences ??
      (throw StateError('Legacy preferences were not initialized.'));

  @override
  Future<String?> read(String key) async => _ready.getString(key);

  @override
  Future<void> remove(String key) async {
    await _ready.remove(key);
  }
}

final class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage({
    required String projectRef,
    SecureStringStore? secureStore,
    LegacyPreferenceStore? legacyStore,
  }) : _projectRef = _validatedProjectRef(projectRef),
       _secureStore = secureStore ?? const FlutterSecureStringStore(),
       _legacyStore = legacyStore ?? SharedPreferencesLegacyPreferenceStore();

  final String _projectRef;
  final SecureStringStore _secureStore;
  final LegacyPreferenceStore _legacyStore;
  bool _initialized = false;

  String get _secureKey => 'equis.supabase.session.$_projectRef.v1';

  String get _legacyKey => 'sb-$_projectRef-auth-token';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _legacyStore.initialize();
    final secureValue = await _secureStore.read(_secureKey);
    final legacyValue = await _legacyStore.read(_legacyKey);
    if (secureValue == null && legacyValue != null) {
      await _secureStore.write(_secureKey, legacyValue);
    }
    if (legacyValue != null) {
      await _legacyStore.remove(_legacyKey);
    }
    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  @override
  Future<bool> hasAccessToken() async {
    await _ensureInitialized();
    return await _secureStore.read(_secureKey) != null;
  }

  @override
  Future<String?> accessToken() async {
    await _ensureInitialized();
    return _secureStore.read(_secureKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _ensureInitialized();
    await _secureStore.write(_secureKey, persistSessionString);
    await _legacyStore.remove(_legacyKey);
  }

  @override
  Future<void> removePersistedSession() async {
    await _ensureInitialized();
    await _secureStore.delete(_secureKey);
    await _legacyStore.remove(_legacyKey);
  }
}

final class SecureSupabasePkceStorage extends GotrueAsyncStorage {
  SecureSupabasePkceStorage({
    required String projectRef,
    SecureStringStore? secureStore,
    LegacyPreferenceStore? legacyStore,
  }) : _projectRef = _validatedProjectRef(projectRef),
       _secureStore = secureStore ?? const FlutterSecureStringStore(),
       _legacyStore = legacyStore ?? SharedPreferencesLegacyPreferenceStore();

  final String _projectRef;
  final SecureStringStore _secureStore;
  final LegacyPreferenceStore _legacyStore;
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    await _legacyStore.initialize();
    _initialized = true;
  }

  String _secureKey(String key) =>
      'equis.supabase.pkce.$_projectRef.${base64UrlEncode(utf8.encode(key))}';

  @override
  Future<String?> getItem({required String key}) async {
    await _initialize();
    final secureKey = _secureKey(key);
    var value = await _secureStore.read(secureKey);
    final legacyValue = await _legacyStore.read(key);
    if (value == null && legacyValue != null) {
      await _secureStore.write(secureKey, legacyValue);
      value = legacyValue;
    }
    if (legacyValue != null) {
      await _legacyStore.remove(key);
    }
    return value;
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    await _initialize();
    await _secureStore.write(_secureKey(key), value);
    await _legacyStore.remove(key);
  }

  @override
  Future<void> removeItem({required String key}) async {
    await _initialize();
    await _secureStore.delete(_secureKey(key));
    await _legacyStore.remove(key);
  }
}

String _validatedProjectRef(String value) {
  if (!RegExp(r'^[a-z0-9-]{3,80}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'projectRef', 'Invalid Supabase project.');
  }
  return value;
}
