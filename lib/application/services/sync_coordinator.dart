import 'dart:async';
import '../ports/sync_metadata_store.dart';

import '../ports/cloud_sync_gateway.dart';
import '../ports/network_reachability.dart';
import 'sync_engine.dart';

final class SyncCoordinator {
  SyncCoordinator({
    required this.engine,
    this.wakeups,
    this.mutations = const Stream.empty(),
    this.reachability,
    this.mutationDebounce = const Duration(seconds: 2),
    this.periodicInterval = const Duration(minutes: 15),
    this.automaticRetryInterval = const Duration(seconds: 30),
  });

  final SyncRunner engine;
  final CloudSyncWakeupGateway? wakeups;
  final Stream<String> mutations;
  final NetworkReachability? reachability;
  final Duration mutationDebounce;
  final Duration periodicInterval;
  final Duration automaticRetryInterval;
  final StreamController<SyncRunResult> _results =
      StreamController<SyncRunResult>.broadcast();

  StreamSubscription<void>? _wakeupSubscription;
  StreamSubscription<String>? _mutationSubscription;
  StreamSubscription<bool>? _reachabilitySubscription;
  Timer? _mutationTimer;
  Timer? _periodicTimer;
  Timer? _retryTimer;
  Future<SyncRunResult>? _activeRun;
  bool _runAgain = false;
  String? _vaultId;
  String? _deviceId;
  bool? _online;

  Stream<SyncRunResult> get results => _results.stream;

  Future<SyncDiagnostics> diagnostics(String vaultId) async =>
      engine is SyncEngine
      ? (engine as SyncEngine).diagnostics(vaultId)
      : const SyncDiagnostics();

  Future<SyncRunResult> retry({
    required String vaultId,
    required String deviceId,
  }) async {
    final active = _activeRun;
    if (active != null) await active;
    if (engine is SyncEngine) {
      await (engine as SyncEngine).retryPending(vaultId);
    }
    return start(vaultId: vaultId, deviceId: deviceId);
  }

  Future<SyncRunResult> start({
    required String vaultId,
    required String deviceId,
  }) async {
    if (_vaultId != vaultId || _deviceId != deviceId) {
      await _cancelTriggers();
      _vaultId = vaultId;
      _deviceId = deviceId;
      _wakeupSubscription = wakeups
          ?.wakeups(vaultId: vaultId)
          .listen((_) => unawaited(synchronize()));
      _mutationSubscription = mutations
          .where((changedVaultId) => changedVaultId == vaultId)
          .listen((_) => _scheduleMutationSync());
      final network = reachability;
      if (network != null) {
        _online = await network.isOnline;
        _reachabilitySubscription = network.changes.listen((online) {
          final restored = _online == false && online;
          _online = online;
          if (restored) unawaited(_onReconnected(vaultId));
        });
      }
      _periodicTimer = Timer.periodic(
        periodicInterval,
        (_) => unawaited(synchronize()),
      );
    }
    return synchronize();
  }

  void _scheduleMutationSync() {
    _mutationTimer?.cancel();
    _mutationTimer = Timer(mutationDebounce, () => unawaited(synchronize()));
  }

  Future<void> _onReconnected(String vaultId) async {
    await _activeRun;
    if (_vaultId != vaultId) return;
    if (engine is SyncEngine) {
      await (engine as SyncEngine).retryTransient(vaultId);
    }
    if (_vaultId == vaultId) await synchronize();
  }

  Future<SyncRunResult?> onResume() async {
    if (_vaultId == null || _deviceId == null) return null;
    return synchronize();
  }

  Future<SyncRunResult> synchronize() {
    final active = _activeRun;
    if (active != null) {
      _runAgain = true;
      return active;
    }
    final vaultId = _vaultId;
    final deviceId = _deviceId;
    if (vaultId == null || deviceId == null) {
      throw StateError('The synchronization coordinator is not started.');
    }
    final run = _run(vaultId: vaultId, deviceId: deviceId);
    _activeRun = run;
    return run.whenComplete(() => _activeRun = null);
  }

  Future<SyncRunResult> _run({
    required String vaultId,
    required String deviceId,
  }) async {
    late SyncRunResult result;
    do {
      _runAgain = false;
      result = await engine.synchronize(vaultId: vaultId, deviceId: deviceId);
      if (!_results.isClosed) _results.add(result);
    } while (_runAgain && _vaultId == vaultId && _deviceId == deviceId);
    _retryTimer?.cancel();
    if (_vaultId == vaultId &&
        _deviceId == deviceId &&
        (result.status == SyncRunStatus.offline ||
            (result.status == SyncRunStatus.succeeded &&
                (await diagnostics(vaultId)).pending > 0))) {
      _retryTimer = Timer(automaticRetryInterval, () {
        if (_vaultId == vaultId && _deviceId == deviceId) {
          unawaited(synchronize());
        }
      });
    }
    return result;
  }

  Future<void> stop() async {
    _vaultId = null;
    _deviceId = null;
    _online = null;
    _runAgain = false;
    await _cancelTriggers();
    await _activeRun;
  }

  Future<void> _cancelTriggers() async {
    _mutationTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _mutationTimer = null;
    _periodicTimer = null;
    await _wakeupSubscription?.cancel();
    await _mutationSubscription?.cancel();
    await _reachabilitySubscription?.cancel();
    _wakeupSubscription = null;
    _mutationSubscription = null;
    _reachabilitySubscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _results.close();
  }
}
