import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftSyncMetadataStore store;

  setUp(() {
    database = EquisDatabase(NativeDatabase.memory());
    store = DriftSyncMetadataStore(database);
  });
  tearDown(() => database.close());

  test('editing an unsent creation keeps its absent remote base', () async {
    await store.enqueue(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _record,
      baseRevision: null,
      baseSnapshot: null,
      newRevision: 1,
      operation: SyncOperation.upsert,
    );
    await store.enqueue(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _record,
      baseRevision: 1,
      baseSnapshot: const {'amount_minor': 100},
      newRevision: 2,
      operation: SyncOperation.upsert,
    );
    final pending = (await store.readyMutations(
      vaultId: _vault,
      nowMicros: _future,
    )).single;
    expect(pending.baseRevision, isNull);
    expect(pending.baseSnapshot, isNull);
    expect(pending.newRevision, 2);
  });

  test('coalesces mutations and retains the oldest merge base', () async {
    await store.enqueue(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _record,
      baseRevision: 1,
      baseSnapshot: const {'amount_minor': 100},
      newRevision: 2,
      operation: SyncOperation.upsert,
    );
    final first = (await store.readyMutations(
      vaultId: _vault,
      nowMicros: _future,
    )).single;

    await store.enqueue(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _record,
      baseRevision: 2,
      baseSnapshot: const {'amount_minor': 200},
      newRevision: 3,
      operation: SyncOperation.delete,
    );
    final coalesced = (await store.readyMutations(
      vaultId: _vault,
      nowMicros: _future,
    )).single;

    expect(coalesced.operationId, first.operationId);
    expect(coalesced.baseRevision, 1);
    expect(coalesced.baseSnapshot, {'amount_minor': 100});
    expect(coalesced.newRevision, 3);
    expect(coalesced.operation, SyncOperation.delete);
  });

  test('transaction rollback cannot leave an orphan outbox row', () async {
    await expectLater(
      database.transaction(() async {
        await database.customStatement(
          "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Local', 'BRL', 'UTC', 1, 1)",
          [_vault],
        );
        await store.enqueue(
          vaultId: _vault,
          entityType: SyncEntityType.vault,
          recordId: _vault,
          baseRevision: null,
          baseSnapshot: null,
          newRevision: 1,
          operation: SyncOperation.upsert,
        );
        throw StateError('crash-before-commit');
      }),
      throwsStateError,
    );

    expect(
      await store.readyMutations(vaultId: _vault, nowMicros: _future),
      isEmpty,
    );
    expect(await database.customSelect('SELECT * FROM vaults').get(), isEmpty);
  });

  test('retry survives restart and acceptance is revision-safe', () async {
    await store.enqueue(
      vaultId: _vault,
      entityType: SyncEntityType.tag,
      recordId: _record,
      baseRevision: null,
      baseSnapshot: null,
      newRevision: 1,
      operation: SyncOperation.upsert,
    );
    final mutation = (await store.readyMutations(
      vaultId: _vault,
      nowMicros: _future,
    )).single;
    await store.markFailed(
      operationId: mutation.operationId,
      nextRetryAtMicros: 500,
      errorCode: 'network',
    );
    expect(
      await store.readyMutations(vaultId: _vault, nowMicros: 499),
      isEmpty,
    );
    final retried = (await store.readyMutations(
      vaultId: _vault,
      nowMicros: 500,
    )).single;
    expect(retried.attemptCount, 1);
    expect(retried.lastErrorCode, 'network');

    await store.markAccepted(
      operationId: retried.operationId,
      revision: 1,
      serverVersion: 9,
      nowMicros: 600,
    );
    expect(
      await store.readyMutations(vaultId: _vault, nowMicros: _future),
      isEmpty,
    );
    expect((await store.cursor(_vault)).lastPushAtMicros, 600);
  });

  test(
    'manual retry restores parked work without deleting mutations',
    () async {
      await store.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.tag,
        recordId: _record,
        baseRevision: null,
        baseSnapshot: null,
        newRevision: 1,
        operation: SyncOperation.upsert,
      );
      final pending = (await store.readyMutations(
        vaultId: _vault,
        nowMicros: 100,
      )).single;
      await store.markPermanentFailure(
        operationId: pending.operationId,
        errorCode: 'accessDenied',
      );
      expect(
        await store.readyMutations(vaultId: _vault, nowMicros: 200),
        isEmpty,
      );
      expect((await store.diagnostics(_vault)).pending, 1);
      await store.retryPending(_vault);
      expect(
        (await store.readyMutations(
          vaultId: _vault,
          nowMicros: 200,
        )).single.operationId,
        pending.operationId,
      );
      expect((await store.diagnostics(_vault)).lastSuccess, isNull);
      await store.recordSuccess(_vault, 300);
      expect(
        (await store.diagnostics(_vault)).lastSuccess!.microsecondsSinceEpoch,
        300,
      );
    },
  );

  test('cursor is monotonic', () async {
    await store.advanceCursor(
      vaultId: _vault,
      serverVersion: 10,
      nowMicros: 100,
    );
    expect((await store.cursor(_vault)).lastServerVersion, 10);
    await expectLater(
      store.advanceCursor(vaultId: _vault, serverVersion: 9, nowMicros: 200),
      throwsStateError,
    );
  });

  test('transaction dependencies are persisted and pauses survive restart', () async {
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Vault', 'BRL', 'UTC', 1, 1)",
      [_vault],
    );
    await database.customStatement(
      "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'brl', 'BRL', 2)",
    );
    await database.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES (?, ?, 'Account', 'checking', 'asset', 1, 1)",
      [_account, _vault],
    );
    await database.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code) VALUES (?, ?, 'BRL')",
      [_pocket, _account],
    );
    await database.customStatement(
      "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, created_at, updated_at) VALUES (?, ?, 'expense', '2026-09-28', 1, 1)",
      [_record, _vault],
    );
    await database.customStatement(
      'INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor, sort_order) VALUES (?, ?, ?, -10, 0)',
      [_movement, _record, _pocket],
    );
    await store.enqueue(
      vaultId: _vault,
      entityType: SyncEntityType.transaction,
      recordId: _record,
      baseRevision: null,
      baseSnapshot: null,
      newRevision: 1,
      operation: SyncOperation.upsert,
    );
    final mutation = (await store.readyMutations(
      vaultId: _vault,
      nowMicros: _future,
    )).single;
    final dependency = await database
        .customSelect(
          'SELECT account_id FROM sync_outbox_dependencies WHERE operation_id = ?',
          variables: [Variable(mutation.operationId)],
        )
        .getSingle();
    expect(dependency.read<String>('account_id'), _account);
    await database.customStatement(
      "INSERT INTO sync_quarantine (event_id, vault_id, server_version, entity_type, entity_id, entity_revision, authenticated_envelope, reason, detected_at) VALUES (?, ?, 1, 'account', ?, 2, '{}', 'account_tombstone_has_movements', 1)",
      [_event, _vault, _account],
    );
    await database.customStatement(
      'INSERT INTO sync_dependency_pause (vault_id, account_id, blocking_event_id, created_at) VALUES (?, ?, ?, 1)',
      [_vault, _account, _event],
    );
    expect(
      await DriftSyncMetadataStore(
        database,
      ).readyMutations(vaultId: _vault, nowMicros: _future),
      isEmpty,
    );
  });

  test('unresolved transaction dependencies roll back the outbox', () async {
    await expectLater(
      store.enqueue(
        vaultId: _vault,
        entityType: SyncEntityType.transaction,
        recordId: _record,
        baseRevision: null,
        baseSnapshot: null,
        newRevision: 1,
        operation: SyncOperation.upsert,
      ),
      throwsStateError,
    );
    expect(
      await database.customSelect('SELECT * FROM sync_outbox').get(),
      isEmpty,
    );
  });
}

const _vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const _record = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
const _account = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
const _pocket = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
const _movement = '018f47c2-9b72-7cc1-8b83-5d0fead0a005';
const _event = '018f47c2-9b72-7cc1-8b83-5d0fead0a006';
const _future = 9999999999999999;
