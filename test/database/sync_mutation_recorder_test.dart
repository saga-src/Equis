import 'package:equis/application/services/sync_mutation_notifications.dart';
import 'package:drift/native.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_mutation_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftSyncMetadataStore metadata;
  late DriftSyncMutationRecorder recorder;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    metadata = DriftSyncMetadataStore(database);
    final aggregates = DriftSyncAggregateStore(
      database: database,
      metadata: metadata,
    );
    recorder = DriftSyncMutationRecorder(
      database: database,
      aggregates: aggregates,
      metadata: metadata,
    );
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
      [_vault],
    );
  });
  tearDown(() => database.close());

  test(
    'committed edits notify automatic sync and rolled-back edits do not',
    () async {
      await _binding(database, enabled: true);
      final notifications = SyncMutationNotifications();
      final observed = <String>[];
      final subscription = notifications.vaultIds.listen(observed.add);
      addTearDown(subscription.cancel);
      addTearDown(notifications.dispose);
      final notifying = DriftSyncMutationRecorder(
        database: database,
        metadata: metadata,
        aggregates: DriftSyncAggregateStore(
          database: database,
          metadata: metadata,
        ),
        notifications: notifications,
      );
      await notifying.run(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
        newRevision: 1,
        operation: SyncOperation.upsert,
        action: () => database.customStatement(
          "INSERT INTO tags (id, vault_id, name, revision, created_at, updated_at) VALUES (?, ?, 'Auto', 1, 1, 1)",
          [_tag, _vault],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(observed, [_vault]);
      expect((await metadata.diagnostics(_vault)).pending, 1);
      await expectLater(
        notifying.run<void>(
          vaultId: _vault,
          entityType: SyncEntityType.tag,
          recordId: _tag,
          newRevision: 2,
          operation: SyncOperation.upsert,
          action: () async => throw StateError('rollback'),
        ),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(observed, [_vault]);
    },
  );

  test('normalized mutation and outbox commit atomically when enabled', () async {
    await _binding(database, enabled: true);

    await recorder.run(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _tag,
      newRevision: 1,
      operation: SyncOperation.upsert,
      action: () => database.customStatement(
        "INSERT INTO tags (id, vault_id, name, revision, created_at, updated_at) VALUES (?, ?, 'Sync me', 1, 1, 1)",
        [_tag, _vault],
      ),
    );

    expect(
      await database.customSelect('SELECT * FROM tags').get(),
      hasLength(1),
    );
    final pending = await metadata.readyMutations(
      vaultId: _vault,
      nowMicros: 9999999999999999,
    );
    expect(pending.single.entityType, SyncEntityType.tag);
    expect(pending.single.baseSnapshot, isNull);
  });

  test('simulated crash rolls back both normalized row and outbox', () async {
    await _binding(database, enabled: true);

    await expectLater(
      recorder.run<void>(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
        newRevision: 1,
        operation: SyncOperation.upsert,
        action: () async {
          await database.customStatement(
            "INSERT INTO tags (id, vault_id, name, revision, created_at, updated_at) VALUES (?, ?, 'Transient', 1, 1, 1)",
            [_tag, _vault],
          );
          throw StateError('crash');
        },
      ),
      throwsStateError,
    );

    expect(await database.customSelect('SELECT * FROM tags').get(), isEmpty);
    expect(
      await database.customSelect('SELECT * FROM sync_outbox').get(),
      isEmpty,
    );
  });

  test('local-only vault never creates a cloud outbox', () async {
    await _binding(database, enabled: false);
    await recorder.run(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _tag,
      newRevision: 1,
      operation: SyncOperation.upsert,
      action: () => database.customStatement(
        "INSERT INTO tags (id, vault_id, name, revision, created_at, updated_at) VALUES (?, ?, 'Private', 1, 1, 1)",
        [_tag, _vault],
      ),
    );
    expect(
      await database.customSelect('SELECT * FROM tags').get(),
      hasLength(1),
    );
    expect(
      await database.customSelect('SELECT * FROM sync_outbox').get(),
      isEmpty,
    );
  });
}

Future<void> _binding(
  EquisDatabase database, {
  required bool enabled,
}) => database.customStatement(
  'INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, ?, ?, 1)',
  [_vault, _user, enabled ? 1 : 0],
);

const _vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const _tag = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
const _user = '11111111-1111-4111-8111-111111111111';
