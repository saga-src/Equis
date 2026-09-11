import 'dart:math';

import '../ports/cloud_sync_gateway.dart';
import '../ports/sync_aggregate_store.dart';
import '../ports/sync_metadata_store.dart';
import '../ports/sync_conflict_resolver.dart';
import '../ports/sync_payload_cryptography.dart';
import '../sync/sync_models.dart';
import '../sync/encrypted_sync_models.dart';

enum SyncFailureKind {
  keyMismatch,
  clientObsolete,
  network,
  sessionExpired,
  accessDenied,
  incompatibleServer,
  invalidPayload,
  cryptography,
  localData,
  remote,
}

enum SyncStage { registration, push, pull, acknowledgement }

enum SyncRunStatus { succeeded, offline, permanentFailure }

final class SyncRunResult {
  const SyncRunResult({
    required this.status,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.failure,
    this.stage,
  });

  final SyncRunStatus status;
  final int pushed;
  final int pulled;
  final int conflicts;
  final SyncFailureKind? failure;
  final SyncStage? stage;
}

abstract interface class SyncRunner {
  Future<SyncRunResult> synchronize({
    required String vaultId,
    required String deviceId,
  });
}

final class SyncEngine implements SyncRunner {
  SyncEngine({
    required this.cloud,
    required this.metadata,
    required this.aggregates,
    required this.cipher,
    this.beforePush,
    this.afterPull,
    this.pullTransaction,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final CloudSyncGateway cloud;
  final SyncMetadataStore metadata;
  final SyncAggregateStore aggregates;
  final SyncPayloadCryptography cipher;
  final Future<void> Function(String vaultId)? beforePush;
  final Future<void> Function(String vaultId)? afterPull;
  final Future<void> Function(Future<void> Function() action)? pullTransaction;
  final DateTime Function() _clock;
  final Random _random;

  SyncStage _stage = SyncStage.registration;
  final Set<int> _reconciledVersions = {};

  Future<SyncDiagnostics> diagnostics(String vaultId) async =>
      metadata is SyncDiagnosticsStore
      ? (metadata as SyncDiagnosticsStore).diagnostics(vaultId)
      : const SyncDiagnostics();

  Future<void> retryPending(String vaultId) async {
    if (metadata is SyncDiagnosticsStore) {
      await (metadata as SyncDiagnosticsStore).retryPending(vaultId);
    }
  }

  Future<void> retryTransient(String vaultId) async {
    if (metadata is SyncDiagnosticsStore) {
      await (metadata as SyncDiagnosticsStore).retryTransient(vaultId);
    }
  }

  @override
  Future<SyncRunResult> synchronize({
    required String vaultId,
    required String deviceId,
  }) async {
    _reconciledVersions.clear();
    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;
    try {
      _stage = SyncStage.registration;
      await cloud.ensureVaultAndDevice(vaultId: vaultId, deviceId: deviceId);
      // Receive related records together before resolving upload conflicts.
      // The production transaction defers foreign keys across all pull pages.
      _stage = SyncStage.pull;
      late (int, int) pullResult;
      final transaction = pullTransaction;
      if (transaction == null) {
        pullResult = await _pull(vaultId, deviceId);
      } else {
        await transaction(() async {
          pullResult = await _pull(vaultId, deviceId);
        });
      }
      pulled += pullResult.$1;
      conflicts += pullResult.$2;
      _stage = SyncStage.push;
      await beforePush?.call(vaultId);
      // Revisit persisted reviews against fresh cloud data, never stale snapshots.
      if (aggregates is SyncConflictResolver) {
        for (final conflict
            in await (aggregates as SyncConflictResolver).unresolved(vaultId)) {
          final remote = await cloud.fetch(
            vaultId: vaultId,
            entityType: conflict.entityType.wireName,
            recordId: conflict.recordId,
          );
          if (remote != null) {
            if (remote.record.identity.vaultId != vaultId ||
                remote.record.identity.recordId != conflict.recordId ||
                remote.record.identity.entityType !=
                    conflict.entityType.wireName) {
              throw const CloudSyncFormatException();
            }
            await _reconcile(remote);
          }
        }
      }
      _stage = SyncStage.push;
      pushed += await _drainPush(vaultId);
      _stage = SyncStage.pull;
      await afterPull?.call(vaultId);
      if (aggregates is SyncConflictResolver) {
        conflicts = (await (aggregates as SyncConflictResolver).unresolved(
          vaultId,
        )).length;
      }
      if (metadata is SyncDiagnosticsStore &&
          (await diagnostics(vaultId)).pending == 0 &&
          conflicts == 0) {
        await (metadata as SyncDiagnosticsStore).recordSuccess(
          vaultId,
          _nowMicros,
        );
      }
      return SyncRunResult(
        status: SyncRunStatus.succeeded,
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
      );
    } on CloudSyncFailure catch (error) {
      final failure = switch (error.code) {
        CloudSyncFailureCode.keyMismatch => SyncFailureKind.keyMismatch,
        CloudSyncFailureCode.clientObsolete => SyncFailureKind.clientObsolete,
        CloudSyncFailureCode.network => SyncFailureKind.network,
        CloudSyncFailureCode.sessionExpired => SyncFailureKind.sessionExpired,
        CloudSyncFailureCode.accessDenied => SyncFailureKind.accessDenied,
        CloudSyncFailureCode.invalidMutation => SyncFailureKind.invalidPayload,
        CloudSyncFailureCode.incompatibleServer =>
          SyncFailureKind.incompatibleServer,
        CloudSyncFailureCode.remote => SyncFailureKind.remote,
      };
      return SyncRunResult(
        status: failure == SyncFailureKind.network
            ? SyncRunStatus.offline
            : SyncRunStatus.permanentFailure,
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
        failure: failure,
        stage: _stage,
      );
    } on PayloadAuthenticationException {
      return SyncRunResult(
        status: SyncRunStatus.permanentFailure,
        failure: SyncFailureKind.cryptography,
        stage: _stage,
        pushed: pushed,
        pulled: pulled,
      );
    } on UnsupportedCipherVersionException {
      return SyncRunResult(
        status: SyncRunStatus.permanentFailure,
        failure: SyncFailureKind.incompatibleServer,
        stage: _stage,
        pushed: pushed,
        pulled: pulled,
      );
    } on CloudSyncFormatException {
      return SyncRunResult(
        status: SyncRunStatus.permanentFailure,
        failure: SyncFailureKind.incompatibleServer,
        stage: _stage,
        pushed: pushed,
        pulled: pulled,
      );
    } on PayloadFormatException {
      return SyncRunResult(
        status: SyncRunStatus.permanentFailure,
        failure: SyncFailureKind.invalidPayload,
        stage: _stage,
        pushed: pushed,
        pulled: pulled,
      );
    } on Object {
      return SyncRunResult(
        status: SyncRunStatus.permanentFailure,
        failure: SyncFailureKind.localData,
        stage: _stage,
        pushed: pushed,
        pulled: pulled,
      );
    }
  }

  Future<int> _drainPush(String vaultId) async {
    var pushed = 0;
    var retries = 0;
    while (true) {
      final result = await _push(vaultId);
      pushed += result.$1;
      if (result.$1 > 0) {
        retries = 0;
        continue;
      }
      // Bound contention with another active writer; remaining work stays queued.
      if (!result.$2 || ++retries >= 8) break;
    }
    return pushed;
  }

  Future<(int, bool)> _push(String vaultId) async {
    final now = _nowMicros;
    final pending = await metadata.readyMutations(
      vaultId: vaultId,
      nowMicros: now,
    );
    if (pending.isEmpty) return (0, false);
    final cloudMutations = <CloudSyncMutation>[];
    var snapshotChanged = false;
    for (final mutation in pending) {
      final payload = await aggregates.loadPayload(
        vaultId: vaultId,
        entityType: mutation.entityType,
        recordId: mutation.recordId,
      );
      if (payload == null) {
        await _scheduleFailure(mutation, 'aggregate_missing');
        throw const PayloadFormatException();
      }
      final root = payload['root'];
      if (root is Map && root['revision'] != mutation.newRevision) {
        // An edit committed after the queue snapshot. Recapture it next pass;
        // never encrypt a newer payload under an older revision identity.
        snapshotChanged = true;
        continue;
      }
      final identity = SyncRecordIdentity(
        vaultId: vaultId,
        recordId: mutation.recordId,
        entityType: mutation.entityType.wireName,
        revision: mutation.newRevision,
      );
      cloudMutations.add(
        CloudSyncMutation(
          operationId: mutation.operationId,
          expectedRevision: mutation.baseRevision,
          record: EncryptedSyncRecord(
            identity: identity,
            envelope: await cipher.encrypt(
              identity: identity,
              payload: payload,
            ),
            isDeleted: mutation.operation == SyncOperation.delete,
          ),
        ),
      );
    }
    if (cloudMutations.isEmpty) return (0, snapshotChanged);

    List<CloudPushResult> results;
    try {
      results = await cloud.pushBatch(
        vaultId: vaultId,
        mutations: cloudMutations,
      );
    } on CloudSyncFailure catch (error) {
      final permanent =
          error.code == CloudSyncFailureCode.invalidMutation ||
          error.code == CloudSyncFailureCode.accessDenied;
      for (final mutation in pending) {
        if (permanent) {
          await metadata.markPermanentFailure(
            operationId: mutation.operationId,
            errorCode: error.code.name,
          );
        } else {
          await _scheduleFailure(mutation, error.code.name);
        }
      }
      rethrow;
    }
    final byOperation = {
      for (final mutation in pending)
        if (cloudMutations.any(
          (cloudMutation) => cloudMutation.operationId == mutation.operationId,
        ))
          mutation.operationId: mutation,
    };
    if (results.length != byOperation.length ||
        results.map((item) => item.operationId).toSet().length !=
            results.length ||
        !results.every((item) => byOperation.containsKey(item.operationId))) {
      throw const CloudSyncFormatException();
    }
    var accepted = 0;
    var changed = snapshotChanged;
    for (final result in results) {
      final mutation = byOperation[result.operationId];
      if (mutation == null) throw const CloudSyncFormatException();
      if (result.status == CloudPushStatus.accepted) {
        if (result.revision != mutation.newRevision ||
            result.serverVersion == null) {
          throw const CloudSyncFormatException();
        }
        await metadata.markAccepted(
          operationId: mutation.operationId,
          revision: result.revision!,
          serverVersion: result.serverVersion!,
          nowMicros: _nowMicros,
        );
        accepted++;
      } else {
        final remote = await cloud.fetch(
          vaultId: vaultId,
          entityType: mutation.entityType.wireName,
          recordId: mutation.recordId,
        );
        if (remote != null) {
          if (remote.record.identity.vaultId != vaultId ||
              remote.record.identity.entityType !=
                  mutation.entityType.wireName ||
              remote.record.identity.recordId != mutation.recordId) {
            throw const CloudSyncFormatException();
          }
          changed = (await _reconcile(remote)).outboxChanged || changed;
          _reconciledVersions.add(remote.serverVersion);
        }
      }
    }
    return (accepted, changed);
  }

  Future<(int, int)> _pull(String vaultId, String deviceId) async {
    var pulled = 0;
    var conflicts = 0;
    while (true) {
      final cursor = await metadata.cursor(vaultId);
      final records = await cloud.pull(
        vaultId: vaultId,
        afterServerVersion: cursor.lastServerVersion,
      );
      if (records.isEmpty) {
        if (cursor.lastServerVersion > 0) {
          _stage = SyncStage.acknowledgement;
          await cloud.acknowledgeCursor(
            vaultId: vaultId,
            deviceId: deviceId,
            serverVersion: cursor.lastServerVersion,
          );
        }
        break;
      }
      var lastSeen = cursor.lastServerVersion;
      for (final record in records) {
        if (record.record.identity.vaultId != vaultId ||
            record.serverVersion <= lastSeen) {
          throw const CloudSyncFormatException();
        }
        lastSeen = record.serverVersion;
      }
      for (final record in records) {
        if (!_reconciledVersions.contains(record.serverVersion)) {
          final result = await _reconcile(record);
          if (result.remoteApplied) pulled++;
        }
        await metadata.advanceCursor(
          vaultId: vaultId,
          serverVersion: record.serverVersion,
          nowMicros: _nowMicros,
        );
      }
      _stage = SyncStage.acknowledgement;
      await cloud.acknowledgeCursor(
        vaultId: vaultId,
        deviceId: deviceId,
        serverVersion: lastSeen,
      );
      _stage = SyncStage.pull;
      if (records.length < 100) break;
    }
    return (pulled, conflicts);
  }

  Future<SyncReconciliation> _reconcile(CloudSyncRecord cloudRecord) async {
    final record = cloudRecord.record;
    final remote = await cipher.decrypt(
      identity: record.identity,
      envelope: record.envelope,
    );
    return aggregates.reconcileRemote(
      vaultId: record.identity.vaultId,
      entityType: SyncEntityType.parse(record.identity.entityType),
      recordId: record.identity.recordId,
      revision: record.identity.revision,
      serverVersion: cloudRecord.serverVersion,
      isDeleted: record.isDeleted,
      payload: remote,
    );
  }

  Future<void> _scheduleFailure(
    PendingSyncMutation mutation,
    String errorCode,
  ) => metadata.markFailed(
    operationId: mutation.operationId,
    nextRetryAtMicros: _nowMicros + _backoffMicros(mutation.attemptCount),
    errorCode: errorCode,
  );

  int _backoffMicros(int attempt) {
    final exponent = min(attempt, 10);
    final seconds = min(5 * (1 << exponent), 3600);
    return seconds * Duration.microsecondsPerSecond +
        _random.nextInt(1001) * Duration.microsecondsPerMillisecond;
  }

  int get _nowMicros => _clock().toUtc().microsecondsSinceEpoch;
}
