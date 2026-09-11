import 'dart:async';

import 'package:equis/application/ports/network_reachability.dart';
import 'package:equis/application/services/sync_coordinator.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncCoordinator', () {
    test(
      'automatically retries a network failure without another mutation',
      () async {
        final runner = _OfflineOnceRunner();
        final coordinator = SyncCoordinator(
          engine: runner,
          automaticRetryInterval: const Duration(milliseconds: 15),
        );
        addTearDown(coordinator.dispose);
        final recovered = coordinator.results.firstWhere(
          (result) => result.status == SyncRunStatus.succeeded,
        );
        await coordinator.start(vaultId: 'vault-1', deviceId: 'device-1');
        await recovered.timeout(const Duration(seconds: 2));
        expect(runner.calls, 2);
      },
    );

    test('manual retry initializes an unstarted coordinator', () async {
      final runner = _RecordingRunner();
      final coordinator = SyncCoordinator(engine: runner);
      addTearDown(coordinator.dispose);
      await coordinator.retry(vaultId: 'vault-1', deviceId: 'device-1');
      expect(runner.calls, 1);
      expect(runner.lastIdentity, ('vault-1', 'device-1'));
    });

    test('runs immediately, manually, on resume, and periodically', () async {
      final runner = _RecordingRunner();
      final coordinator = SyncCoordinator(
        engine: runner,
        periodicInterval: const Duration(milliseconds: 30),
      );

      await coordinator.start(vaultId: 'vault-1', deviceId: 'device-1');
      await coordinator.synchronize();
      await coordinator.onResume();
      await Future<void>.delayed(const Duration(milliseconds: 45));

      expect(runner.calls, greaterThanOrEqualTo(4));
      expect(runner.lastIdentity, ('vault-1', 'device-1'));
      await coordinator.dispose();
    });

    test('debounces mutations and ignores other vaults', () async {
      final mutations = StreamController<String>.broadcast(sync: true);
      final runner = _RecordingRunner();
      final coordinator = SyncCoordinator(
        engine: runner,
        mutations: mutations.stream,
        mutationDebounce: const Duration(milliseconds: 20),
        periodicInterval: const Duration(hours: 1),
      );
      await coordinator.start(vaultId: 'vault-1', deviceId: 'device-1');

      mutations.add('vault-1');
      mutations.add('vault-1');
      mutations.add('vault-2');
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(runner.calls, 2);
      await coordinator.dispose();
      await mutations.close();
    });

    test('runs when connectivity is restored', () async {
      final network = _FakeReachability(false);
      final runner = _RecordingRunner();
      final coordinator = SyncCoordinator(
        engine: runner,
        reachability: network,
        periodicInterval: const Duration(hours: 1),
      );
      await coordinator.start(vaultId: 'vault-1', deviceId: 'device-1');

      network.setOnline(true);
      await Future<void>.delayed(Duration.zero);

      expect(runner.calls, 2);
      await coordinator.dispose();
      await network.close();
    });

    test('coalesces overlapping requests into one follow-up run', () async {
      final runner = _ControlledRunner();
      final coordinator = SyncCoordinator(
        engine: runner,
        periodicInterval: const Duration(hours: 1),
      );

      final initial = coordinator.start(
        vaultId: 'vault-1',
        deviceId: 'device-1',
      );
      await runner.started.first;
      final second = coordinator.synchronize();
      final third = coordinator.synchronize();
      runner.completeNext();
      await runner.started.first;
      runner.completeNext();

      await Future.wait([initial, second, third]);
      expect(runner.calls, 2);
      await coordinator.dispose();
    });

    test('resume before enrollment is a no-op', () async {
      final coordinator = SyncCoordinator(engine: _RecordingRunner());
      expect(await coordinator.onResume(), isNull);
      await coordinator.dispose();
    });
  });
}

final class _OfflineOnceRunner implements SyncRunner {
  int calls = 0;
  @override
  Future<SyncRunResult> synchronize({
    required String vaultId,
    required String deviceId,
  }) async => SyncRunResult(
    status: ++calls == 1 ? SyncRunStatus.offline : SyncRunStatus.succeeded,
  );
}

final class _RecordingRunner implements SyncRunner {
  int calls = 0;
  (String, String)? lastIdentity;

  @override
  Future<SyncRunResult> synchronize({
    required String vaultId,
    required String deviceId,
  }) async {
    calls++;
    lastIdentity = (vaultId, deviceId);
    return const SyncRunResult(status: SyncRunStatus.succeeded);
  }
}

final class _ControlledRunner implements SyncRunner {
  final StreamController<void> _started = StreamController<void>.broadcast();
  final List<Completer<SyncRunResult>> _pending = [];
  int calls = 0;

  Stream<void> get started => _started.stream;

  @override
  Future<SyncRunResult> synchronize({
    required String vaultId,
    required String deviceId,
  }) {
    calls++;
    final completer = Completer<SyncRunResult>();
    _pending.add(completer);
    _started.add(null);
    return completer.future;
  }

  void completeNext() {
    _pending
        .removeAt(0)
        .complete(const SyncRunResult(status: SyncRunStatus.succeeded));
  }
}

final class _FakeReachability implements NetworkReachability {
  _FakeReachability(this._online);

  bool _online;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<bool> get isOnline async => _online;

  void setOnline(bool value) {
    _online = value;
    _changes.add(value);
  }

  Future<void> close() => _changes.close();
}
