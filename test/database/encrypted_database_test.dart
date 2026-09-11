import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/persistence/database/local_database_lifecycle.dart';
import 'package:equis/infrastructure/persistence/database/secure_storage_local_database_key_provider.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'encrypted background database round-trips and rejects the wrong key',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'equis-encrypted-db-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}vault.db');
      final key = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );
      final database = EquisDatabase(openEncryptedDatabase(file, key));
      await database.customStatement(
        "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('encrypted-vault', 'Sensitive marker', 'BRL', 'America/Sao_Paulo', 1, 1)",
      );
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM vaults WHERE id = 'encrypted-vault'",
                )
                .getSingle())
            .read<String>('name'),
        'Sensitive marker',
      );
      expect(
        (await database.customSelect('PRAGMA journal_mode').getSingle())
            .read<String>('journal_mode'),
        'wal',
      );
      await database.close();

      final bytes = await file.readAsBytes();
      expect(_contains(bytes, 'SQLite format 3'.codeUnits), isFalse);
      expect(_contains(bytes, 'Sensitive marker'.codeUnits), isFalse);

      final wrongKey = Uint8List.fromList(
        List<int>.generate(32, (index) => 255 - index),
      );
      final wronglyOpened = EquisDatabase(
        openEncryptedDatabase(file, wrongKey),
      );
      await expectLater(
        wronglyOpened.customSelect('SELECT * FROM vaults').get(),
        throwsA(anything),
      );
      await wronglyOpened.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('AES-256 opening rejects keys that are not 32 bytes', () {
    expect(
      () => openEncryptedDatabase(File('unused.db'), Uint8List(31)),
      throwsArgumentError,
    );
  });

  test(
    'empty encrypted database adopts a recovered vault key and reopens',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'equis-recovered-db-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}vault.db');
      final manager = VaultKeyManager(store: _MemorySecureStore());
      var lifecycle = EncryptedDriftDatabaseLifecycle(
        file: file,
        keyProvider: SecureStorageLocalDatabaseKeyProvider(keyManager: manager),
      );
      addTearDown(() async {
        if (lifecycle.state == LocalDatabaseState.ready) {
          await lifecycle.close();
        }
      });
      await lifecycle.initialize();

      await lifecycle.replaceKeyForEmptyDatabase(
        version: 1,
        masterKey: SecretKey(List<int>.filled(32, 9)),
      );
      await lifecycle.database.customStatement(
        "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('restored', 'Recovered', 'BRL', 'UTC', 1, 1)",
      );
      expect(
        (await lifecycle.database
                .customSelect("SELECT name FROM vaults WHERE id = 'restored'")
                .getSingle())
            .read<String>('name'),
        'Recovered',
      );
      await lifecycle.close();

      lifecycle = EncryptedDriftDatabaseLifecycle(
        file: file,
        keyProvider: SecureStorageLocalDatabaseKeyProvider(keyManager: manager),
      );
      await lifecycle.initialize();
      expect(
        (await lifecycle.database
                .customSelect("SELECT name FROM vaults WHERE id = 'restored'")
                .getSingle())
            .read<String>('name'),
        'Recovered',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

bool _contains(List<int> bytes, List<int> needle) {
  for (var start = 0; start <= bytes.length - needle.length; start++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (bytes[start + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
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
