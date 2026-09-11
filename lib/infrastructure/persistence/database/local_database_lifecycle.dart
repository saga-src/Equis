import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'equis_database.dart';

enum LocalDatabaseState { notInitialized, ready, closed }

abstract interface class LocalDatabaseLifecycle {
  LocalDatabaseState get state;

  Future<void> initialize();

  Future<void> close();
}

/// Phase 1 lifecycle seam. Phase 2 replaces this with the encrypted Drift
/// implementation without changing application callers.
final class PendingEncryptedDatabaseLifecycle
    implements LocalDatabaseLifecycle {
  LocalDatabaseState _state = LocalDatabaseState.notInitialized;

  @override
  LocalDatabaseState get state => _state;

  @override
  Future<void> initialize() async {
    _state = LocalDatabaseState.ready;
  }

  @override
  Future<void> close() async {
    _state = LocalDatabaseState.closed;
  }
}

abstract interface class LocalDatabaseKeyProvider {
  Future<Uint8List> loadOrCreateKey();
}

abstract interface class RecoverableLocalDatabaseKeyProvider
    implements LocalDatabaseKeyProvider {
  Future<Uint8List> stageRecoveredMasterKey({
    required int version,
    required SecretKey masterKey,
  });

  Future<Uint8List?> pendingLocalDatabaseKey();

  Future<void> resolvePendingAfterCurrentKeyOpened();

  Future<void> commitPendingRecovery();
}

final class EncryptedDriftDatabaseLifecycle implements LocalDatabaseLifecycle {
  EncryptedDriftDatabaseLifecycle({
    required this.file,
    required this.keyProvider,
  });

  final File file;
  final LocalDatabaseKeyProvider keyProvider;
  EquisDatabase? _database;
  LocalDatabaseState _state = LocalDatabaseState.notInitialized;

  EquisDatabase get database =>
      _database ??
      (throw StateError('The local database has not been initialized.'));

  @override
  LocalDatabaseState get state => _state;

  @override
  Future<void> initialize() async {
    if (_state == LocalDatabaseState.ready) return;
    final key = await keyProvider.loadOrCreateKey();
    final recoverable = keyProvider is RecoverableLocalDatabaseKeyProvider
        ? keyProvider as RecoverableLocalDatabaseKeyProvider
        : null;
    try {
      _database = await _open(key);
      await recoverable?.resolvePendingAfterCurrentKeyOpened();
    } catch (_) {
      final pending = await recoverable?.pendingLocalDatabaseKey();
      if (pending == null) rethrow;
      _database = await _open(pending);
      await recoverable!.commitPendingRecovery();
    }
    _state = LocalDatabaseState.ready;
  }

  Future<void> replaceKeyForEmptyDatabase({
    required int version,
    required SecretKey masterKey,
  }) async {
    final recoverable = keyProvider is RecoverableLocalDatabaseKeyProvider
        ? keyProvider as RecoverableLocalDatabaseKeyProvider
        : null;
    if (recoverable == null || _state != LocalDatabaseState.ready) {
      throw StateError('Secure database recovery is unavailable.');
    }
    final vaultCount = await database
        .customSelect('SELECT COUNT(*) AS amount FROM vaults')
        .getSingle();
    if (vaultCount.read<int>('amount') != 0) {
      throw StateError('An existing local vault cannot be replaced.');
    }
    final key = await recoverable.stageRecoveredMasterKey(
      version: version,
      masterKey: masterKey,
    );
    final keyHex = key
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await database.customStatement('PRAGMA journal_mode = DELETE');
    await database.customStatement("PRAGMA rekey = \"x'$keyHex'\"");
    await database.customStatement('PRAGMA journal_mode = WAL');
    await database.verifyIntegrity();
    await recoverable.commitPendingRecovery();
  }

  Future<EquisDatabase> _open(Uint8List key) async {
    final opened = EquisDatabase(openEncryptedDatabase(file, key));
    try {
      await opened.customSelect('SELECT 1').getSingle();
      await opened.verifyIntegrity();
      return opened;
    } catch (_) {
      await opened.close();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _state = LocalDatabaseState.closed;
  }
}
