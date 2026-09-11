import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/application/ports/sync_conflict_resolver.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/security/canonical_json.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (7, 6, 100, 200, true, false),
    (6, 7, 200, 100, false, false),
    (7, 7, 200, 100, true, false),
    (7, 7, 100, 200, false, false),
    (7, 6, 200, 100, true, true),
  ]) {
    test('automatic revision winner $scenario converges in one run', () async {
      final local = EquisDatabase(NativeDatabase.memory());
      final remote = EquisDatabase(NativeDatabase.memory());
      addTearDown(local.close);
      addTearDown(remote.close);
      await _seedDependencies(local);
      await _seedDependencies(remote);
      final cloud = _MemorySyncCloud();
      final keys = VaultKeyManager(store: _SyncSecrets());
      await keys.loadOrCreateMasterKey();
      final cipher = SyncPayloadCipher(keys: keys);
      SyncEngine engine(EquisDatabase db) => SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(db),
        aggregates: _store(db),
        cipher: cipher,
      );
      final first = engine(local);
      final second = engine(remote);
      Future<Map<String, Object?>> payload(EquisDatabase db) async =>
          (await _store(db).loadPayload(
            vaultId: _vault,
            entityType: SyncEntityType.tag,
            recordId: _tag,
          ))!;
      final base = await payload(local);
      await remote.customStatement(
        'UPDATE tags SET name = ?, revision = ?, updated_at = ? WHERE id = ?',
        ['Remote', scenario.$2, scenario.$4, _tag],
      );
      await second.metadata.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
        baseRevision: null,
        baseSnapshot: null,
        newRevision: scenario.$2,
        operation: SyncOperation.upsert,
      );
      expect(
        (await second.synchronize(vaultId: _vault, deviceId: 'remote')).status,
        SyncRunStatus.succeeded,
      );
      final remotePayload = await payload(remote);
      await local.customStatement(
        'UPDATE tags SET name = ?, revision = ?, updated_at = ?, deleted_at = ? WHERE id = ?',
        [
          'Local',
          scenario.$1,
          scenario.$3,
          scenario.$6 ? scenario.$3 : null,
          _tag,
        ],
      );
      await first.metadata.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
        baseRevision: 1,
        baseSnapshot: base,
        newRevision: scenario.$1,
        operation: scenario.$6 ? SyncOperation.delete : SyncOperation.upsert,
      );
      // Reproduce a review saved by an earlier app. Its snapshots must not
      // prevent automatic repair, including with an already advanced cursor.
      await _store(local).preserveConflict(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
        baseRevision: 1,
        localRevision: scenario.$1,
        remoteRevision: scenario.$2,
        serverVersion: cloud.version,
        baseSnapshot: base,
        localSnapshot: await payload(local),
        remoteSnapshot: remotePayload,
      );
      await first.metadata.advanceCursor(
        vaultId: _vault,
        serverVersion: cloud.version,
        nowMicros: 1,
      );
      final result = await first.synchronize(
        vaultId: _vault,
        deviceId: 'local',
      );
      expect(result.status, SyncRunStatus.succeeded);
      expect(result.conflicts, 0);
      expect((await first.diagnostics(_vault)).pending, 0);
      await second.synchronize(vaultId: _vault, deviceId: 'remote');
      final expectedName = scenario.$5 ? 'Local' : 'Remote';
      expect((await payload(local))['root'], (await payload(remote))['root']);
      expect(((await payload(local))['root'] as Map)['name'], expectedName);
      expect(cloud.records[_tag]!.record.isDeleted, scenario.$6);
      final version = cloud.version;
      await first.synchronize(vaultId: _vault, deviceId: 'local');
      await second.synchronize(vaultId: _vault, deviceId: 'remote');
      expect(cloud.version, version);
      expect(cloud.records, hasLength(1));
    });
  }

  test('edit committed during push survives conflict resolution', () async {
    final db = EquisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedDependencies(db);
    final store = _store(db);
    final metadata = DriftSyncMetadataStore(db);
    final keys = VaultKeyManager(store: _SyncSecrets());
    await keys.loadOrCreateMasterKey();
    final cloud = _MemorySyncCloud();
    final engine = SyncEngine(
      cloud: cloud,
      metadata: metadata,
      aggregates: store,
      cipher: SyncPayloadCipher(keys: keys),
    );
    Future<void> edit(int revision, String name) async {
      final base = (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
      ))!;
      await db.customStatement(
        'UPDATE tags SET name = ?, revision = ? WHERE id = ?',
        [name, revision, _tag],
      );
      await metadata.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _tag,
        baseRevision: cloud.records[_tag]?.record.identity.revision,
        baseSnapshot: base,
        newRevision: revision,
        operation: SyncOperation.upsert,
      );
    }

    await edit(6, 'Base');
    await engine.synchronize(vaultId: _vault, deviceId: 'first');
    await edit(7, 'First edit');
    cloud.beforePush = () async {
      cloud.beforePush = null;
      await edit(9, 'Edited while sending');
    };
    final result = await engine.synchronize(vaultId: _vault, deviceId: 'first');
    expect(result.status, SyncRunStatus.succeeded);
    expect(result.conflicts, 0);
    expect((await engine.diagnostics(_vault)).pending, 0);
    final saved = cloud.records[_tag]!.record;
    expect(saved.identity.revision, 9);
    final decrypted = await engine.cipher.decrypt(
      identity: saved.identity,
      envelope: saved.envelope,
    );
    expect((decrypted['root'] as Map)['name'], 'Edited while sending');
  });

  test(
    'two local databases synchronize encrypted records and reconnect without duplicates',
    () async {
      final source = EquisDatabase(NativeDatabase.memory());
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(target.close);
      await _seedDependencies(source);
      await _seedTransaction(source);
      await _seedDependencies(target);
      final keys = VaultKeyManager(store: _SyncSecrets());
      await keys.loadOrCreateMasterKey();
      final cloud = _MemorySyncCloud();
      SyncEngine engine(EquisDatabase db) => SyncEngine(
        cloud: cloud,
        metadata: DriftSyncMetadataStore(db),
        aggregates: _store(db),
        cipher: SyncPayloadCipher(keys: keys),
      );
      final first = engine(source);
      final second = engine(target);
      final account = await source
          .customSelect('SELECT id FROM accounts LIMIT 1')
          .getSingle();
      for (final entry in [
        (SyncEntityType.account, account.read<String>('id')),
        (SyncEntityType.transaction, _transaction),
      ]) {
        final payload = (await _store(source).loadPayload(
          vaultId: _vault,
          entityType: entry.$1,
          recordId: entry.$2,
        ))!;
        await first.metadata.enqueue(
          vaultId: _vault,
          entityType: entry.$1,
          recordId: entry.$2,
          baseRevision: null,
          baseSnapshot: null,
          newRevision: (payload['root'] as Map)['revision'] as int,
          operation: SyncOperation.upsert,
        );
      }
      expect(
        (await first.synchronize(vaultId: _vault, deviceId: 'first')).status,
        SyncRunStatus.succeeded,
      );
      expect(
        (await second.synchronize(vaultId: _vault, deviceId: 'second')).status,
        SyncRunStatus.succeeded,
      );
      final base = (await _store(source).loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
      ))!;
      final revision = (base['root'] as Map)['revision'] as int;
      await source.customStatement(
        'UPDATE transactions SET title = ?, revision = ? WHERE id = ?',
        ['Edited offline', revision + 2, _transaction],
      );
      await first.metadata.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
        baseRevision: revision,
        baseSnapshot: base,
        newRevision: revision + 2,
        operation: SyncOperation.upsert,
      );
      cloud.offline = true;
      expect(
        (await first.synchronize(vaultId: _vault, deviceId: 'first')).status,
        SyncRunStatus.offline,
      );
      expect((await first.diagnostics(_vault)).pending, 1);
      cloud.offline = false;
      await first.retryPending(_vault);
      expect(
        (await first.synchronize(vaultId: _vault, deviceId: 'first')).status,
        SyncRunStatus.succeeded,
      );
      expect(
        (await second.synchronize(vaultId: _vault, deviceId: 'second')).status,
        SyncRunStatus.succeeded,
      );
      expect(
        (await second.synchronize(vaultId: _vault, deviceId: 'second')).pulled,
        0,
      );
      final restored = await target
          .customSelect(
            'SELECT title FROM transactions WHERE id = ?',
            variables: [Variable(_transaction)],
          )
          .getSingle();
      expect(restored.read<String>('title'), 'Edited offline');
      expect(
        (await target
                .customSelect('SELECT COUNT(*) AS n FROM account_movements')
                .getSingle())
            .read<int>('n'),
        2,
      );
      expect((await first.diagnostics(_vault)).pending, 0);
      expect((await first.diagnostics(_vault)).lastSuccess, isNotNull);
    },
  );

  test(
    'reapplying an account preserves pockets referenced by transactions',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedDependencies(database);
      await _seedTransaction(database);
      final store = _store(database);
      final account = await database
          .customSelect('SELECT id FROM accounts LIMIT 1')
          .getSingle();
      final id = account.read<String>('id');
      final payload = (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: id,
      ))!;
      final root = payload['root'] as Map;
      await store.applyRemote(
        vaultId: _vault,
        entityType: SyncEntityType.account,
        recordId: id,
        revision: root['revision'] as int,
        serverVersion: 1,
        isDeleted: false,
        payload: payload,
      );
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM account_movements')
                .getSingle())
            .read<int>('n'),
        2,
      );
    },
  );

  test('transaction aggregate round-trips every atomic child row', () async {
    final source = EquisDatabase(NativeDatabase.memory());
    await _seedDependencies(source);
    await _seedTransaction(source);
    final sourceStore = _store(source);

    final payload = await sourceStore.loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.transaction,
      recordId: _transaction,
    );
    expect(payload, isNotNull);
    final children = payload!['children'] as Map<String, Object?>;
    expect(children['account_movements'], hasLength(2));
    expect(children['transaction_splits'], hasLength(1));
    expect(children['transaction_tags'], hasLength(1));
    expect(children['fx_conversions'], hasLength(1));
    expect(children['investment_events'], hasLength(2));
    expect(children['investment_lots'], hasLength(1));
    expect(children['investment_lot_disposals'], hasLength(1));
    await source.close();

    final target = EquisDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    await _seedDependencies(target);
    final targetStore = _store(target);

    await targetStore.applyRemote(
      vaultId: _vault,
      entityType: SyncEntityType.transaction,
      recordId: _transaction,
      revision: 2,
      serverVersion: 8,
      isDeleted: false,
      payload: payload,
    );
    final restored = await targetStore.loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.transaction,
      recordId: _transaction,
    );

    expect(CanonicalJson.encode(restored), CanonicalJson.encode(payload));
    final state = await target
        .customSelect(
          "SELECT * FROM sync_entity_state WHERE entity_type = 'transaction' AND record_id = ?",
          variables: [Variable(_transaction)],
        )
        .getSingle();
    expect(state.read<int>('last_synced_revision'), 2);
    expect(state.read<int>('server_version'), 8);
    expect(state.read<String>('sync_state'), 'synced');
  });

  test(
    'attachment payload never exports or overwrites a device local path',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedDependencies(database);
      await database.customStatement(
        'INSERT INTO attachments (id, vault_id, original_filename, byte_size, '
        'local_path, sha256, upload_state, revision, created_at, updated_at) '
        "VALUES (?, ?, 'receipt.jpg', 10, 'C:/private/local.jpg', 'abc', 'uploaded', 1, 1, 1)",
        [_attachment, _vault],
      );
      final store = _store(database);
      final payload = (await store.loadPayload(
        vaultId: _vault,
        entityType: SyncEntityType.attachment,
        recordId: _attachment,
      ))!;
      final root = payload['root'] as Map<String, Object?>;
      expect(root, isNot(contains('local_path')));
      expect(root, isNot(contains('upload_state')));

      final changed = Map<String, Object?>.from(root)
        ..['original_filename'] = 'renamed.jpg'
        ..['revision'] = 2;
      await store.applyRemote(
        vaultId: _vault,
        entityType: SyncEntityType.attachment,
        recordId: _attachment,
        revision: 2,
        serverVersion: 2,
        isDeleted: false,
        payload: {...payload, 'root': changed},
      );
      final row = await database
          .customSelect(
            'SELECT * FROM attachments WHERE id = ?',
            variables: [Variable(_attachment)],
          )
          .getSingle();
      expect(row.read<String>('local_path'), 'C:/private/local.jpg');
      expect(row.read<String>('upload_state'), 'uploaded');
      expect(row.read<String>('original_filename'), 'renamed.jpg');
    },
  );

  test(
    'conflict snapshots remain only inside encrypted local metadata',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = _store(database);
      await store.preserveConflict(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
        baseRevision: 1,
        localRevision: 2,
        remoteRevision: 2,
        serverVersion: 4,
        baseSnapshot: const {'amount_minor': 100},
        localSnapshot: const {'amount_minor': 200},
        remoteSnapshot: const {'amount_minor': 300},
      );

      final row = await database
          .customSelect('SELECT * FROM sync_conflicts')
          .getSingle();
      expect(row.read<String>('base_snapshot'), '{"amount_minor":100}');
      expect(row.read<String>('local_snapshot'), '{"amount_minor":200}');
      expect(row.read<String>('remote_snapshot'), '{"amount_minor":300}');
      final state = await database
          .customSelect('SELECT * FROM sync_entity_state')
          .getSingle();
      expect(state.read<String>('sync_state'), 'conflict');

      await store.preserveConflict(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _transaction,
        baseRevision: 1,
        localRevision: 3,
        remoteRevision: 2,
        serverVersion: 4,
        baseSnapshot: const {'amount_minor': 100},
        localSnapshot: const {'amount_minor': 250},
        remoteSnapshot: const {'amount_minor': 300},
      );
      expect(
        await database.customSelect('SELECT * FROM sync_conflicts').get(),
        hasLength(1),
      );
    },
  );

  test('conflict resolution accepts the remote aggregate atomically', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedDependencies(database);
    await database.customStatement(
      "UPDATE tags SET name = 'Base', revision = 1, updated_at = 1 WHERE id = ?",
      [_tag],
    );
    final store = _store(database);
    final base = (await store.loadPayload(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _tag,
    ))!;
    Map<String, Object?> changed(String name) {
      final root = Map<String, Object?>.from(base['root']! as Map)
        ..['name'] = name
        ..['revision'] = 2
        ..['updated_at'] = 2;
      return {...base, 'root': root};
    }

    final local = changed('Local');
    final remote = changed('Remote');
    await database.customStatement(
      "UPDATE tags SET name = 'Local', revision = 2, updated_at = 2 WHERE id = ?",
      [_tag],
    );
    await store.preserveConflict(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _tag,
      baseRevision: 1,
      localRevision: 2,
      remoteRevision: 2,
      serverVersion: 5,
      baseSnapshot: base,
      localSnapshot: local,
      remoteSnapshot: remote,
    );
    final conflict = (await store.unresolved(_vault)).single;

    await store.resolve(
      conflictId: conflict.id,
      resolution: SyncConflictResolution.keepRemote,
    );

    expect(await store.unresolved(_vault), isEmpty);
    final tag = await database
        .customSelect(
          'SELECT name, revision FROM tags WHERE id = ?',
          variables: [Variable(_tag)],
        )
        .getSingle();
    expect(tag.read<String>('name'), 'Remote');
    expect(tag.read<int>('revision'), 2);
    expect(
      await database.customSelect('SELECT * FROM sync_outbox').get(),
      isEmpty,
    );
  });
}

DriftSyncAggregateStore _store(EquisDatabase database) =>
    DriftSyncAggregateStore(
      database: database,
      metadata: DriftSyncMetadataStore(database),
    );

Future<void> _seedDependencies(EquisDatabase db) async {
  await db.customStatement(
    "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
    [_vault],
  );
  await db.customStatement(
    "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'brl', 'BRL', 2)",
  );
  await db.customStatement(
    "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Account', 'checking', 'asset', 1, 1)",
    [_account, _vault],
  );
  await db.customStatement(
    "INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, 'BRL', 1)",
    [_pocket, _account],
  );
  await db.customStatement(
    "INSERT INTO categories (id, vault_id, category_type, custom_name, created_at, updated_at) VALUES (?, ?, 'expense', 'Food', 1, 1)",
    [_category, _vault],
  );
  await db.customStatement(
    "INSERT INTO tags (id, vault_id, name, created_at, updated_at) VALUES (?, ?, 'Test', 1, 1)",
    [_tag, _vault],
  );
  await db.customStatement(
    "INSERT INTO investment_instruments (id, vault_id, name, asset_class, currency_code, created_at, updated_at) VALUES (?, ?, 'Fund', 'fund', 'BRL', 1, 1)",
    [_instrument, _vault],
  );
}

Future<void> _seedTransaction(EquisDatabase db) async {
  await db.customStatement(
    "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, revision, created_at, updated_at) VALUES (?, ?, 'investment_buy', '2026-08-22', 2, 1, 2)",
    [_transaction, _vault],
  );
  await db.customStatement(
    'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor, sort_order) VALUES (?, ?, ?, -100, 0), (?, ?, ?, 100, 1)',
    [_movement1, _transaction, _pocket, _movement2, _transaction, _pocket],
  );
  await db.customStatement(
    "INSERT INTO transaction_splits (id, transaction_id, category_id, currency_code, amount_minor) VALUES (?, ?, ?, 'BRL', 100)",
    [_split, _transaction, _category],
  );
  await db.customStatement(
    'INSERT INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)',
    [_transaction, _tag],
  );
  await db.customStatement(
    "INSERT INTO fx_conversions (id, transaction_id, from_movement_id, to_movement_id, exchange_rate, rate_source) VALUES (?, ?, ?, ?, '1', 'manual')",
    [_fx, _transaction, _movement1, _movement2],
  );
  await db.customStatement(
    "INSERT INTO investment_events (id, transaction_id, instrument_id, event_type, quantity) VALUES (?, ?, ?, 'buy', '2'), (?, ?, ?, 'sell', '1')",
    [_event1, _transaction, _instrument, _event2, _transaction, _instrument],
  );
  await db.customStatement(
    "INSERT INTO investment_lots (id, acquisition_event_id, instrument_id, acquired_on, original_quantity, cost_basis_minor, cost_currency_code) VALUES (?, ?, ?, '2026-08-22', '2', 100, 'BRL')",
    [_lot, _event1, _instrument],
  );
  await db.customStatement(
    "INSERT INTO investment_lot_disposals (id, disposal_event_id, lot_id, quantity, allocated_cost_minor) VALUES (?, ?, ?, '1', 50)",
    [_disposal, _event2, _lot],
  );
}

const _vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const _account = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
const _pocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
const _category = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
const _tag = '018f47c2-9b72-7cc1-8b83-5d0fead0a005';
const _instrument = '018f47c2-9b72-7cc1-8b83-5d0fead0a006';
const _transaction = '018f47c2-9b72-7cc1-8b83-5d0fead0a007';
const _movement1 = '018f47c2-9b72-7cc1-8b83-5d0fead0a008';
const _movement2 = '018f47c2-9b72-7cc1-8b83-5d0fead0a009';
const _split = '018f47c2-9b72-7cc1-8b83-5d0fead0a00a';
const _fx = '018f47c2-9b72-7cc1-8b83-5d0fead0a00b';
const _event1 = '018f47c2-9b72-7cc1-8b83-5d0fead0a00c';
const _event2 = '018f47c2-9b72-7cc1-8b83-5d0fead0a00d';
const _lot = '018f47c2-9b72-7cc1-8b83-5d0fead0a00e';
const _disposal = '018f47c2-9b72-7cc1-8b83-5d0fead0a00f';
const _attachment = '018f47c2-9b72-7cc1-8b83-5d0fead0a010';

class _SyncSecrets implements SecureStringStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _MemorySyncCloud implements CloudSyncGateway {
  final records = <String, CloudSyncRecord>{};
  int version = 0;
  bool offline = false;
  Future<void> Function()? beforePush;
  @override
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  }) async {
    if (offline) throw const CloudSyncFailure(CloudSyncFailureCode.network);
  }

  @override
  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  }) async {
    await beforePush?.call();
    return [for (final mutation in mutations) _push(mutation)];
  }

  CloudPushResult _push(CloudSyncMutation mutation) {
    final identity = mutation.record.identity;
    final current = records[identity.recordId];
    if ((current?.record.identity.revision ?? 0) !=
        (mutation.expectedRevision ?? 0)) {
      return CloudPushResult(
        operationId: mutation.operationId,
        status: CloudPushStatus.conflict,
        remoteRevision: current?.record.identity.revision,
        serverVersion: current?.serverVersion,
      );
    }
    final saved = CloudSyncRecord(
      record: mutation.record,
      serverVersion: ++version,
    );
    records[identity.recordId] = saved;
    return CloudPushResult(
      operationId: mutation.operationId,
      status: CloudPushStatus.accepted,
      revision: identity.revision,
      serverVersion: saved.serverVersion,
    );
  }

  @override
  Future<List<CloudSyncRecord>> pull({
    required String vaultId,
    required int afterServerVersion,
    int limit = 100,
  }) async =>
      (records.values
              .where((r) => r.serverVersion > afterServerVersion)
              .toList()
            ..sort((a, b) => a.serverVersion.compareTo(b.serverVersion)))
          .take(limit)
          .toList();
  @override
  Future<CloudSyncRecord?> fetch({
    required String vaultId,
    required String entityType,
    required String recordId,
  }) async => records[recordId];
  @override
  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  }) async {}
}
