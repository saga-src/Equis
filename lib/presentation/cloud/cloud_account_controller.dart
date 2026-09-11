import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/cloud_account_service.dart';
import '../../application/services/existing_vault_restore_service.dart';
import '../../application/services/sync_coordinator.dart';
import '../../application/services/sync_engine.dart';
import '../../application/ports/sync_conflict_resolver.dart';
import '../../application/ports/cloud_sync_gateway.dart';
import '../../application/sync/encrypted_sync_models.dart';
import '../../domain/cloud/cloud_identity_models.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../infrastructure/sync/cloud_sync_enrollment_service.dart';

final class CloudAccountState {
  const CloudAccountState({
    this.snapshot,
    this.loading = false,
    this.errorCode,
    this.pendingEmail,
    this.syncBusy = false,
    this.syncRunStatus,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts24h = 0,
    this.conflicts = const [],
    this.recoverySecret,
    this.syncError = false,
    this.syncFailure,
    this.syncStage,
    this.pending = 0,
    this.lastSuccess,
    this.restoreError,
  });

  final CloudAccountSnapshot? snapshot;
  final bool loading;
  final CloudAuthFailureCode? errorCode;
  final String? pendingEmail;
  final bool syncBusy;
  final SyncRunStatus? syncRunStatus;
  final int pushed;
  final int pulled;
  final int conflicts24h;
  final List<SyncConflictSummary> conflicts;
  final String? recoverySecret;
  final bool syncError;
  final SyncFailureKind? syncFailure;
  final SyncStage? syncStage;
  final int pending;
  final DateTime? lastSuccess;
  final ExistingVaultRestoreFailureCode? restoreError;
}

final class CloudAccountController extends StateNotifier<CloudAccountState> {
  CloudAccountController({
    required CloudAccountService? service,
    required EntityId? vaultId,
    CloudSyncEnrollmentService? enrollment,
    SyncCoordinator? syncCoordinator,
    SyncConflictResolver? conflictResolver,
    ExistingVaultRestoreService? restore,
    Future<void> Function()? onRestored,
  }) : this._(
         service,
         vaultId,
         enrollment,
         syncCoordinator,
         conflictResolver,
         restore,
         onRestored,
       );

  CloudAccountController._(
    this._service,
    this._vaultId,
    this._enrollment,
    this._syncCoordinator,
    this._conflictResolver,
    this._restore,
    this._onRestored,
  ) : super(const CloudAccountState()) {
    _subscription = _service?.identityChanges.listen(
      (_) => unawaited(reload()),
    );
    _syncSubscription = _syncCoordinator?.results.listen(_applySyncResult);
  }

  final CloudAccountService? _service;
  final EntityId? _vaultId;
  final CloudSyncEnrollmentService? _enrollment;
  final SyncCoordinator? _syncCoordinator;
  final SyncConflictResolver? _conflictResolver;
  final ExistingVaultRestoreService? _restore;
  final Future<void> Function()? _onRestored;
  StreamSubscription<Object?>? _subscription;
  StreamSubscription<SyncRunResult>? _syncSubscription;
  PreparedCloudSyncEnrollment? _preparedEnrollment;

  Future<void> reload() => _mutate(
    (service, vaultId) => service.load(vaultId: vaultId, now: UtcInstant.now()),
  );

  Future<void> createAccount({
    required String email,
    required String password,
  }) => _mutate(
    (service, vaultId) => service.createAccount(
      vaultId: vaultId,
      email: email,
      password: password,
      now: UtcInstant.now(),
    ),
    pendingEmail: email.trim(),
  );

  Future<void> signIn({required String email, required String password}) =>
      _mutate(
        (service, vaultId) => service.signIn(
          vaultId: vaultId,
          email: email,
          password: password,
          now: UtcInstant.now(),
        ),
        pendingEmail: email.trim(),
      );

  Future<void> restoreExisting({
    required String email,
    required String password,
    required String recoverySecret,
  }) async {
    final restore = _restore;
    if (state.loading) return;
    if (restore == null) {
      _replace(
        restoreError: ExistingVaultRestoreFailureCode.unavailable,
        clearAuthError: true,
      );
      return;
    }
    state = CloudAccountState(
      snapshot: state.snapshot,
      loading: true,
      pendingEmail: email.trim(),
    );
    try {
      await restore.restore(
        email: email,
        password: password,
        recoverySecret: recoverySecret,
        now: UtcInstant.now(),
      );
      _replace(loading: false, clearAuthError: true, clearRestoreError: true);
      await _onRestored?.call();
    } on ExistingVaultRestoreFailure catch (error) {
      _replace(loading: false, restoreError: error.code);
    } on CloudAuthFailure catch (error) {
      _replace(loading: false, errorCode: error.code, clearRestoreError: true);
    } on Exception {
      _replace(
        loading: false,
        restoreError: ExistingVaultRestoreFailureCode.unavailable,
      );
    }
  }

  Future<void> resendVerification() async {
    final service = _service;
    final email = state.pendingEmail;
    if (service == null || email == null || state.loading) return;
    state = CloudAccountState(
      snapshot: state.snapshot,
      loading: true,
      pendingEmail: email,
    );
    try {
      await service.resendVerification(email);
      state = CloudAccountState(snapshot: state.snapshot, pendingEmail: email);
    } on CloudAuthFailure catch (error) {
      state = CloudAccountState(
        snapshot: state.snapshot,
        errorCode: error.code,
        pendingEmail: email,
      );
    } on Exception {
      state = CloudAccountState(
        snapshot: state.snapshot,
        errorCode: CloudAuthFailureCode.unknown,
        pendingEmail: email,
      );
    }
  }

  Future<void> signOut() => _mutate(
    (service, vaultId) =>
        service.signOut(vaultId: vaultId, now: UtcInstant.now()),
  );

  Future<void> prepareSynchronization() async {
    final enrollment = _enrollment;
    final snapshot = state.snapshot;
    final identity = snapshot?.identity;
    if (enrollment == null ||
        snapshot == null ||
        identity == null ||
        snapshot.status != CloudAccountStatus.signedIn ||
        state.syncBusy) {
      return;
    }
    _replace(syncBusy: true, clearSyncError: true);
    try {
      if (await enrollment.resumeExisting(
        vaultId: snapshot.device.vaultId.value,
        deviceId: snapshot.device.id.value,
        authUserId: identity.authUserId,
      )) {
        _replace(syncBusy: false, clearRecoverySecret: true);
        await reload();
        return;
      }
      final prepared = await enrollment.prepare(
        vaultId: snapshot.device.vaultId.value,
        deviceId: snapshot.device.id.value,
        authUserId: identity.authUserId,
      );
      _preparedEnrollment = prepared;
      _replace(
        syncBusy: false,
        recoverySecret: prepared.recoverySecret.export(),
      );
    } on CloudSyncFailure catch (error) {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: switch (error.code) {
          CloudSyncFailureCode.keyMismatch => SyncFailureKind.keyMismatch,
          CloudSyncFailureCode.clientObsolete => SyncFailureKind.clientObsolete,
          CloudSyncFailureCode.accessDenied => SyncFailureKind.accessDenied,
          CloudSyncFailureCode.sessionExpired => SyncFailureKind.sessionExpired,
          CloudSyncFailureCode.network => SyncFailureKind.network,
          CloudSyncFailureCode.invalidMutation =>
            SyncFailureKind.invalidPayload,
          CloudSyncFailureCode.incompatibleServer =>
            SyncFailureKind.incompatibleServer,
          CloudSyncFailureCode.remote => SyncFailureKind.remote,
        },
      );
    } on PayloadAuthenticationException {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: SyncFailureKind.cryptography,
      );
    } on Exception {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: SyncFailureKind.localData,
      );
    }
  }

  Future<void> confirmRecoverySaved() async {
    final enrollment = _enrollment;
    final prepared = _preparedEnrollment;
    if (enrollment == null || prepared == null || state.syncBusy) return;
    _replace(syncBusy: true, clearSyncError: true);
    try {
      await enrollment.confirmRecoverySaved(prepared);
      _preparedEnrollment = null;
      _replace(syncBusy: false, clearRecoverySecret: true);
      await reload();
    } on Exception {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: SyncFailureKind.localData,
      );
    }
  }

  Future<void> retrySynchronization() async {
    final coordinator = _syncCoordinator;
    final snapshot = state.snapshot;
    if (coordinator == null ||
        snapshot?.binding?.syncEnabled != true ||
        state.syncBusy) {
      return;
    }
    _replace(syncBusy: true, clearSyncError: true);
    try {
      _applySyncResult(
        await coordinator.retry(
          vaultId: snapshot!.device.vaultId.value,
          deviceId: snapshot.device.id.value,
        ),
      );
    } on Exception {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: SyncFailureKind.localData,
      );
    }
  }

  Future<void> resolveConflict({
    required String conflictId,
    required SyncConflictResolution resolution,
  }) async {
    final resolver = _conflictResolver;
    if (resolver == null || state.syncBusy) return;
    _replace(syncBusy: true, clearSyncError: true);
    try {
      await resolver.resolve(conflictId: conflictId, resolution: resolution);
      await _reloadConflicts();
      _replace(syncBusy: false);
      await retrySynchronization();
    } on Exception {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: SyncFailureKind.localData,
      );
    }
  }

  Future<void> _mutate(
    Future<CloudAccountSnapshot> Function(
      CloudAccountService service,
      EntityId vaultId,
    )
    action, {
    String? pendingEmail,
  }) async {
    final service = _service;
    final vaultId = _vaultId;
    if (service == null || vaultId == null || state.loading) return;
    state = CloudAccountState(
      snapshot: state.snapshot,
      loading: true,
      pendingEmail: pendingEmail ?? state.pendingEmail,
    );
    try {
      final snapshot = await action(service, vaultId);
      _replace(
        snapshot: snapshot,
        loading: false,
        pendingEmail: pendingEmail ?? state.pendingEmail,
        clearAuthError: true,
      );
      unawaited(_configureSync(snapshot));
    } on CloudAuthFailure catch (error) {
      state = CloudAccountState(
        snapshot: state.snapshot,
        errorCode: error.code,
        pendingEmail: pendingEmail ?? state.pendingEmail,
      );
    } on Exception {
      state = CloudAccountState(
        snapshot: state.snapshot,
        errorCode: CloudAuthFailureCode.unknown,
        pendingEmail: pendingEmail ?? state.pendingEmail,
      );
    }
  }

  Future<void> _configureSync(CloudAccountSnapshot snapshot) async {
    final coordinator = _syncCoordinator;
    if (snapshot.status != CloudAccountStatus.signedIn ||
        snapshot.binding?.syncEnabled != true ||
        coordinator == null) {
      await coordinator?.stop();
      await _reloadConflicts();
      return;
    }
    _replace(syncBusy: true, clearSyncError: true);
    try {
      _applySyncResult(
        await coordinator.start(
          vaultId: snapshot.device.vaultId.value,
          deviceId: snapshot.device.id.value,
        ),
      );
      await _reloadConflicts();
    } on Exception {
      _replace(
        syncBusy: false,
        syncError: true,
        syncFailure: SyncFailureKind.localData,
      );
    }
  }

  Future<void> _reloadConflicts() async {
    final resolver = _conflictResolver;
    final vaultId = _vaultId;
    if (resolver == null || vaultId == null) return;
    try {
      _replace(conflicts: await resolver.unresolved(vaultId.value));
    } on Exception {
      _replace(syncError: true);
    }
  }

  void _applySyncResult(SyncRunResult result) {
    _replace(
      syncBusy: false,
      syncRunStatus: result.status,
      syncFailure: result.failure,
      syncStage: result.stage,
      clearSyncError: result.failure == null,
      syncError: result.status == SyncRunStatus.permanentFailure,
    );
    unawaited(_reloadConflicts());
    unawaited(refreshDiagnostics());
  }

  Future<void> refreshDiagnostics() async {
    final vaultId = _vaultId;
    final coordinator = _syncCoordinator;
    if (vaultId == null || coordinator == null) return;
    try {
      final diagnostics = await coordinator.diagnostics(vaultId.value);
      if (mounted) {
        _replace(
          pending: diagnostics.pending,
          pushed: diagnostics.sent24h,
          pulled: diagnostics.received24h,
          conflicts24h: diagnostics.conflicts24h,
          lastSuccess: diagnostics.lastSuccess,
        );
      }
    } on Exception {
      /* Keep the last known diagnostics. */
    }
  }

  void _replace({
    CloudAccountSnapshot? snapshot,
    bool? loading,
    CloudAuthFailureCode? errorCode,
    String? pendingEmail,
    bool? syncBusy,
    SyncRunStatus? syncRunStatus,
    int? pushed,
    int? pulled,
    int? conflicts24h,
    List<SyncConflictSummary>? conflicts,
    String? recoverySecret,
    bool? syncError,
    SyncFailureKind? syncFailure,
    SyncStage? syncStage,
    int? pending,
    DateTime? lastSuccess,
    bool clearAuthError = false,
    bool clearRecoverySecret = false,
    bool clearSyncError = false,
    ExistingVaultRestoreFailureCode? restoreError,
    bool clearRestoreError = false,
  }) {
    if (!mounted) return;
    state = CloudAccountState(
      snapshot: snapshot ?? state.snapshot,
      loading: loading ?? state.loading,
      errorCode: clearAuthError ? null : errorCode ?? state.errorCode,
      pendingEmail: pendingEmail ?? state.pendingEmail,
      syncBusy: syncBusy ?? state.syncBusy,
      syncRunStatus: syncRunStatus ?? state.syncRunStatus,
      pushed: pushed ?? state.pushed,
      pulled: pulled ?? state.pulled,
      conflicts24h: conflicts24h ?? state.conflicts24h,
      conflicts: conflicts ?? state.conflicts,
      recoverySecret: clearRecoverySecret
          ? null
          : recoverySecret ?? state.recoverySecret,
      syncError: clearSyncError ? false : syncError ?? state.syncError,
      syncFailure: clearSyncError ? null : syncFailure ?? state.syncFailure,
      syncStage: clearSyncError ? null : syncStage ?? state.syncStage,
      pending: pending ?? state.pending,
      lastSuccess: lastSuccess ?? state.lastSuccess,
      restoreError: clearRestoreError
          ? null
          : restoreError ?? state.restoreError,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_syncSubscription?.cancel());
    super.dispose();
  }
}
