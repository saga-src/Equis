import 'dart:io';
import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'schema_versions.dart';

part 'equis_database.g.dart';

@DriftDatabase(include: {'schema.drift'})
final class EquisDatabase extends _$EquisDatabase {
  EquisDatabase(super.executor);

  bool _acceptTransactions = true;
  int _transactions = 0;
  Completer<void>? _drained;

  /// Stop accepting new root mutations while allowing already-running and
  /// nested transactions to finish before the update closes the connection.
  Future<void> drainForUpdate() async {
    _acceptTransactions = false;
    if (_transactions > 0) {
      _drained ??= Completer<void>();
      await _drained!.future;
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    if (Zone.current[this] == true) {
      return super.transaction(action, requireNew: requireNew);
    }
    if (!_acceptTransactions) {
      throw StateError('Application update in progress');
    }
    _transactions++;
    try {
      return await runZoned(
        () => super.transaction(action, requireNew: requireNew),
        zoneValues: {this: true},
      );
    } finally {
      _transactions--;
      if (_transactions == 0 && _drained != null && !_drained!.isCompleted) {
        _drained!.complete();
      }
    }
  }

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => transaction(migrator.createAll),
    onUpgrade: (migrator, from, to) {
      if (from > to) {
        throw StateError(
          'Database downgrades are not supported ($from -> $to).',
        );
      }
      return transaction(
        () => stepByStep(
          from1To2: (migrator, schema) async {
            await migrator.create(schema.idxTransactionsVaultHistory);
            await migrator.create(schema.idxTransactionsVaultTypeStatusDate);
            await migrator.create(schema.idxMovementsAmount);
            await migrator.create(schema.idxSplitsCategory);
            await migrator.create(schema.idxTransactionTagsTag);
            await migrator.create(schema.idxPocketsCurrency);
          },
          from2To3: (migrator, schema) async {
            await migrator.create(schema.idxTransactionsRecurrence);
            await migrator.create(schema.idxRecurringRulesVaultNext);
          },
          from3To4: (migrator, schema) async {
            await migrator.addColumn(
              schema.syncOutbox,
              schema.syncOutbox.baseSnapshot,
            );
          },
          from4To5: (migrator, schema) async {
            await migrator.addColumn(
              schema.categories,
              schema.categories.customNameEnUs,
            );
            await migrator.addColumn(
              schema.categories,
              schema.categories.customNamePtBr,
            );
            await migrator.addColumn(schema.tags, schema.tags.nameEnUs);
            await migrator.addColumn(schema.tags, schema.tags.namePtBr);
          },
          from5To6: (migrator, schema) async {
            await migrator.create(schema.syncActivityEvents);
            await migrator.create(schema.idxSyncActivityTime);
          },
        )(migrator, from, to),
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<void> verifyIntegrity() async {
    final quickCheck = await customSelect('PRAGMA quick_check').get();
    if (quickCheck.length != 1 ||
        quickCheck.single.read<String>('quick_check') != 'ok') {
      throw StateError('Local database integrity check failed.');
    }
    final foreignKeyFailures = await customSelect(
      'PRAGMA foreign_key_check',
    ).get();
    if (foreignKeyFailures.isNotEmpty) {
      throw StateError('Local database relationship check failed.');
    }
  }
}

QueryExecutor openEncryptedDatabase(File file, Uint8List key) {
  if (key.length != 32) {
    throw ArgumentError.value(
      key.length,
      'key',
      'AES-256 requires exactly 32 bytes.',
    );
  }
  final keyHex = key
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return NativeDatabase.createInBackground(
    file,
    setup: (rawDatabase) {
      if (rawDatabase.select('PRAGMA cipher;').isEmpty) {
        throw StateError('SQLite3MultipleCiphers is not active.');
      }
      rawDatabase.execute("PRAGMA cipher = 'sqlcipher';");
      rawDatabase.execute('PRAGMA legacy = 4;');
      rawDatabase.execute("PRAGMA key = \"x'$keyHex'\";");
      rawDatabase.execute('PRAGMA foreign_keys = ON;');
      rawDatabase.execute('PRAGMA journal_mode = WAL;');
      rawDatabase.execute('PRAGMA busy_timeout = 5000;');
    },
  );
}
