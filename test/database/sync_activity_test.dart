import 'package:drift/native.dart';
import 'dart:async';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'update drain waits for active writes and rejects new transactions',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final started = Completer<void>();
      final finish = Completer<void>();
      final writing = db.transaction(() async {
        started.complete();
        await finish.future;
        await db.transaction(() async {
          await db.customStatement(
            "INSERT INTO sync_activity_events VALUES ('a','vault','a','sent',1,1,1)",
          );
        });
      });
      await started.future;
      var drained = false;
      final drain = db.drainForUpdate().then((_) => drained = true);
      await expectLater(db.transaction(() async {}), throwsStateError);
      expect(drained, false);
      finish.complete();
      await writing;
      await drain;
      expect(drained, true);
      expect(
        await db.customSelect('SELECT * FROM sync_activity_events').get(),
        hasLength(1),
      );
    },
  );
  test(
    'rolling UTC window, deduplication, vault isolation and retention',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var now = DateTime.utc(2026, 9, 11, 12);
      final store = DriftSyncMetadataStore(db, clock: () => now);
      Future<void> event(
        String id,
        String kind, {
        String vault = 'a',
        Duration age = Duration.zero,
      }) => store.recordActivity(
        vaultId: vault,
        entityType: 'transaction',
        recordId: id,
        kind: kind,
        localRevision: 7,
        remoteRevision: 6,
        nowMicros: now.subtract(age).microsecondsSinceEpoch,
      );
      await event('one', 'sent');
      await event('one', 'sent');
      await event('two', 'received', age: const Duration(hours: 23));
      await event('three', 'conflict');
      await event('three', 'conflict');
      await event('other', 'sent', vault: 'b');
      await event('boundary', 'sent', age: const Duration(hours: 24));
      await event('expired', 'sent', age: const Duration(days: 8));
      var result = await store.diagnostics('a');
      expect(result.sent24h, 1);
      expect(result.received24h, 1);
      expect(result.conflicts24h, 1);
      // Recreating the repository cannot reset persisted activity.
      expect(
        (await DriftSyncMetadataStore(
          db,
          clock: () => now,
        ).diagnostics('a')).sent24h,
        1,
      );
      expect((await store.diagnostics('b')).sent24h, 1);
      now = now.add(const Duration(hours: 2));
      result = await store.diagnostics('a');
      expect(result.received24h, 0);
      final old = await db
          .customSelect(
            "SELECT * FROM sync_activity_events WHERE record_id='expired'",
          )
          .get();
      expect(old, isEmpty);
    },
  );
  test('rolled-back local changes cannot leave activity behind', () async {
    final db = EquisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftSyncMetadataStore(db);
    await expectLater(
      db.transaction(() async {
        await store.recordActivity(
          vaultId: 'a',
          entityType: 'vault',
          recordId: 'a',
          kind: 'received',
          localRevision: 1,
          remoteRevision: 1,
        );
        throw StateError('apply failed');
      }),
      throwsStateError,
    );
    expect((await store.diagnostics('a')).received24h, 0);
  });
}
