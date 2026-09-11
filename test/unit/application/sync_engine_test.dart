import 'dart:convert';
import 'dart:math';

import 'package:equis/application/ports/cloud_sync_gateway.dart';
import 'package:equis/application/ports/sync_aggregate_store.dart';
import 'package:equis/application/ports/sync_metadata_store.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/infrastructure/security/encrypted_payload_cipher.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Metadata metadata;
  late _Aggregates aggregates;
  late _Cloud cloud;
  late SyncPayloadCipher cipher;
  late SyncEngine engine;

  setUp(() {
    metadata = _Metadata();
    aggregates = _Aggregates(metadata);
    cloud = _Cloud();
    cipher = SyncPayloadCipher(
      keys: VaultKeyManager(
        store: _Store(base64UrlEncode(List<int>.generate(32, (i) => i))),
      ),
    );
    engine = SyncEngine(
      cloud: cloud,
      metadata: metadata,
      aggregates: aggregates,
      cipher: cipher,
      clock: () => DateTime.utc(2026, 8, 22),
      random: Random(1),
    );
  });

  test('offline run preserves pending work for a later retry', () async {
    metadata.pending.add(_pending());
    aggregates.payloads[_record] = {'amount_minor': 100};
    cloud.failure = const CloudSyncFailure(CloudSyncFailureCode.network);

    final result = await engine.synchronize(vaultId: _vault, deviceId: _device);

    expect(result.status, SyncRunStatus.offline);
    expect(metadata.pending, hasLength(1));
  });

  test('idempotent accepted replay clears one outbox mutation', () async {
    metadata.pending.add(_pending());
    aggregates.payloads[_record] = {'amount_minor': 100};
    cloud.pushHandler = (mutations) => [
      CloudPushResult(
        operationId: mutations.single.operationId,
        status: CloudPushStatus.accepted,
        revision: 2,
        serverVersion: 7,
        idempotentReplay: true,
      ),
    ];

    final result = await engine.synchronize(vaultId: _vault, deviceId: _device);

    expect(result.status, SyncRunStatus.succeeded);
    expect(result.pushed, 1);
    expect(metadata.pending, isEmpty);
  });

  test(
    'equal revisions select one complete aggregate deterministically',
    () async {
      metadata.pending.add(
        _pending(base: const {'name': 'old', 'note': 'base'}),
      );
      aggregates.payloads[_record] = {'name': 'local', 'note': 'base'};
      cloud.pullRecords.add(
        await _cloudRecord(
          cipher,
          payload: const {'name': 'old', 'note': 'remote'},
          revision: 2,
          serverVersion: 8,
        ),
      );

      final result = await engine.synchronize(
        vaultId: _vault,
        deviceId: _device,
      );

      expect(result.conflicts, 0);
      expect(aggregates.payloads[_record], {'name': 'old', 'note': 'remote'});
      expect(aggregates.merged, 0);
      expect(metadata.cursorValue, 8);
    },
  );

  test('same field collision no longer waits for manual review', () async {
    metadata.pending.add(_pending(base: const {'amount_minor': 100}));
    aggregates.payloads[_record] = {'amount_minor': 200};
    cloud.pullRecords.add(
      await _cloudRecord(
        cipher,
        payload: const {'amount_minor': 300},
        revision: 2,
        serverVersion: 9,
      ),
    );

    final result = await engine.synchronize(vaultId: _vault, deviceId: _device);

    expect(result.conflicts, 0);
    expect(aggregates.conflicts, 0);
    expect(aggregates.payloads[_record], {'amount_minor': 300});
    expect(metadata.cursorValue, 9);
  });

  test('remote tombstone applies when there is no local mutation', () async {
    cloud.pullRecords.add(
      await _cloudRecord(
        cipher,
        payload: const {'deleted': true},
        revision: 3,
        serverVersion: 10,
        isDeleted: true,
      ),
    );

    final result = await engine.synchronize(vaultId: _vault, deviceId: _device);

    expect(result.pulled, 1);
    expect(aggregates.deleted, {_record});
    expect(metadata.cursorValue, 10);
  });

  test(
    'permanent push rejection is parked instead of retried forever',
    () async {
      metadata.pending.add(_pending());
      aggregates.payloads[_record] = {'amount_minor': 100};
      cloud.pushFailure = const CloudSyncFailure(
        CloudSyncFailureCode.invalidMutation,
      );

      final result = await engine.synchronize(
        vaultId: _vault,
        deviceId: _device,
      );

      expect(result.status, SyncRunStatus.permanentFailure);
      expect(metadata.permanentFailures, [_operation]);
    },
  );

  test(
    'malformed batch response is rejected without accepting outbox rows',
    () async {
      metadata.pending.add(_pending());
      aggregates.payloads[_record] = {'amount_minor': 100};
      cloud.pushHandler = (_) => const [];

      final result = await engine.synchronize(
        vaultId: _vault,
        deviceId: _device,
      );
      expect(result.failure, SyncFailureKind.incompatibleServer);
      expect(metadata.pending, hasLength(1));
    },
  );

  test('pulls and decrypts 250 records across bounded pages', () async {
    for (var index = 1; index <= 250; index++) {
      cloud.pullRecords.add(
        await _cloudRecord(
          cipher,
          recordId:
              '018f47c2-9b72-7cc1-8b83-${index.toRadixString(16).padLeft(12, '0')}',
          payload: {'amount_minor': index},
          revision: 1,
          serverVersion: index,
        ),
      );
    }

    final stopwatch = Stopwatch()..start();
    final result = await engine.synchronize(vaultId: _vault, deviceId: _device);
    stopwatch.stop();

    expect(result.status, SyncRunStatus.succeeded);
    expect(result.pulled, 250);
    expect(metadata.cursorValue, 250);
    expect(aggregates.payloads, hasLength(250));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

PendingSyncMutation _pending({Map<String, Object?>? base}) =>
    PendingSyncMutation(
      operationId: _operation,
      vaultId: _vault,
      entityType: SyncEntityType.transaction,
      recordId: _record,
      baseRevision: 1,
      baseSnapshot: base ?? const {'amount_minor': 50},
      newRevision: 2,
      operation: SyncOperation.upsert,
      createdAtMicros: 1,
      attemptCount: 0,
    );

Future<CloudSyncRecord> _cloudRecord(
  SyncPayloadCipher cipher, {
  required Map<String, Object?> payload,
  required int revision,
  required int serverVersion,
  String recordId = _record,
  bool isDeleted = false,
}) async {
  final identity = SyncRecordIdentity(
    vaultId: _vault,
    recordId: recordId,
    entityType: 'transaction',
    revision: revision,
  );
  return CloudSyncRecord(
    record: EncryptedSyncRecord(
      identity: identity,
      envelope: await cipher.encrypt(identity: identity, payload: payload),
      isDeleted: isDeleted,
    ),
    serverVersion: serverVersion,
  );
}

final class _Cloud implements CloudSyncGateway {
  CloudSyncFailure? failure;
  CloudSyncFailure? pushFailure;
  List<CloudSyncRecord> pullRecords = [];
  List<CloudPushResult> Function(List<CloudSyncMutation>)? pushHandler;

  @override
  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  }) async {}

  @override
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  }) async {
    if (failure case final value?) throw value;
  }

  @override
  Future<CloudSyncRecord?> fetch({
    required String vaultId,
    required String entityType,
    required String recordId,
  }) async => pullRecords
      .where((item) => item.record.identity.recordId == recordId)
      .firstOrNull;

  @override
  Future<List<CloudSyncRecord>> pull({
    required String vaultId,
    required int afterServerVersion,
    int limit = 100,
  }) async => pullRecords
      .where((item) => item.serverVersion > afterServerVersion)
      .take(limit)
      .toList();

  @override
  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  }) async {
    if (pushFailure case final value?) throw value;
    final handler = pushHandler;
    if (handler != null) return handler(mutations);
    return [
      for (final mutation in mutations)
        if (pullRecords.any(
          (item) =>
              item.record.identity.recordId ==
              mutation.record.identity.recordId,
        ))
          CloudPushResult(
            operationId: mutation.operationId,
            status: CloudPushStatus.conflict,
            remoteRevision: pullRecords
                .firstWhere(
                  (item) =>
                      item.record.identity.recordId ==
                      mutation.record.identity.recordId,
                )
                .record
                .identity
                .revision,
            serverVersion: null,
          ),
    ];
  }
}

final class _Metadata implements SyncMetadataStore {
  final List<PendingSyncMutation> pending = [];
  final List<String> permanentFailures = [];
  int cursorValue = 0;

  @override
  Future<void> advanceCursor({
    required String vaultId,
    required int serverVersion,
    required int nowMicros,
  }) async => cursorValue = serverVersion;

  @override
  Future<SyncCursorValue> cursor(String vaultId) async =>
      SyncCursorValue(vaultId: vaultId, lastServerVersion: cursorValue);

  @override
  Future<void> enqueue({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int? baseRevision,
    required Map<String, Object?>? baseSnapshot,
    required int newRevision,
    required SyncOperation operation,
  }) async {}

  @override
  Future<void> markAccepted({
    required String operationId,
    required int revision,
    required int serverVersion,
    required int nowMicros,
  }) async => pending.removeWhere(
    (item) => item.operationId == operationId && item.newRevision == revision,
  );

  @override
  Future<void> markFailed({
    required String operationId,
    required int nextRetryAtMicros,
    required String errorCode,
  }) async {}

  @override
  Future<void> markPermanentFailure({
    required String operationId,
    required String errorCode,
  }) async => permanentFailures.add(operationId);

  @override
  Future<PendingSyncMutation?> pendingFor({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  }) async => pending.where((item) => item.recordId == recordId).firstOrNull;

  @override
  Future<List<PendingSyncMutation>> readyMutations({
    required String vaultId,
    required int nowMicros,
    int limit = 50,
  }) async => pending.take(limit).toList();
}

final class _Aggregates implements SyncAggregateStore {
  _Aggregates(this.metadata);
  final _Metadata metadata;
  final Map<String, Map<String, Object?>> payloads = {};
  final Set<String> deleted = {};
  int conflicts = 0;
  int merged = 0;

  @override
  Future<SyncReconciliation> reconcileRemote({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
    required int serverVersion,
    required bool isDeleted,
    required Map<String, Object?> payload,
  }) async {
    metadata.pending.removeWhere((item) => item.recordId == recordId);
    await applyRemote(
      vaultId: vaultId,
      entityType: entityType,
      recordId: recordId,
      revision: revision,
      serverVersion: serverVersion,
      isDeleted: isDeleted,
      payload: payload,
    );
    return const SyncReconciliation(remoteApplied: true);
  }

  @override
  Future<Map<String, Object?>?> loadPayload({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
  }) async => payloads[recordId];

  @override
  Future<void> applyMerged({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int remoteRevision,
    required int serverVersion,
    required Map<String, Object?> remoteSnapshot,
    required Map<String, Object?> mergedSnapshot,
  }) async {
    payloads[recordId] = mergedSnapshot;
    merged++;
  }

  @override
  Future<void> applyRemote({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int revision,
    required int serverVersion,
    required bool isDeleted,
    required Map<String, Object?> payload,
  }) async {
    payloads[recordId] = payload;
    if (isDeleted) deleted.add(recordId);
  }

  @override
  Future<void> preserveConflict({
    required String vaultId,
    required SyncEntityType entityType,
    required String recordId,
    required int baseRevision,
    required int localRevision,
    required int remoteRevision,
    required int serverVersion,
    required Map<String, Object?> baseSnapshot,
    required Map<String, Object?> localSnapshot,
    required Map<String, Object?> remoteSnapshot,
  }) async => conflicts++;
}

final class _Store implements SecureStringStore {
  _Store(String master) : values = {'equis.vault_master_key.v1': master};
  final Map<String, String> values;
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _vault = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
const _record = '018f47c2-9b72-7cc1-8b83-5d0fead0a002';
const _operation = '018f47c2-9b72-7cc1-8b83-5d0fead0a003';
const _device = '018f47c2-9b72-7cc1-8b83-5d0fead0a004';
