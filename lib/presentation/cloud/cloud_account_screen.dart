import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/providers/app_providers.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../application/services/existing_vault_restore_service.dart';
import '../../domain/cloud/cloud_identity_models.dart';
import '../../application/ports/sync_conflict_resolver.dart';
import '../../application/services/sync_engine.dart';
import '../../l10n/app_localizations.dart';
import 'cloud_account_controller.dart';
import '../shared/equis_glass.dart';

class CloudAccountScreen extends ConsumerStatefulWidget {
  const CloudAccountScreen({
    this.financeOverride,
    this.stateOverride,
    super.key,
  });

  final LocalFinanceSnapshot? financeOverride;
  final CloudAccountState? stateOverride;

  @override
  ConsumerState<CloudAccountScreen> createState() => _CloudAccountScreenState();
}

class _CloudAccountScreenState extends ConsumerState<CloudAccountScreen>
    with WidgetsBindingObserver {
  Timer? _activityTimer;
  void _refreshActivity() {
    if (mounted && widget.stateOverride == null) {
      unawaited(
        ref.read(cloudAccountControllerProvider.notifier).refreshDiagnostics(),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshActivity());
    _activityTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshActivity(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshActivity();
  }

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _recoverySecret = TextEditingController();

  @override
  void dispose() {
    _activityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    _recoverySecret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final finance =
        widget.financeOverride ??
        ref.watch(localFinanceControllerProvider).valueOrNull;
    final CloudAccountState state =
        widget.stateOverride ?? ref.watch(cloudAccountControllerProvider);
    final snapshot = state.snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.cloudAccountTitle),
        actions: [
          IconButton(
            tooltip: l.refreshAction,
            onPressed: state.loading
                ? null
                : () => ref
                      .read(cloudAccountControllerProvider.notifier)
                      .reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: finance?.vault == null
          ? _restoreBody(context, state)
          : state.loading && snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : snapshot == null
          ? Center(child: Text(l.authUnknownMessage))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                EquisGlassCard(
                  key: const Key('cloud-local-first-notice'),
                  child: ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(l.cloudAccountIntro),
                    subtitle: Text(l.localAccessPreservedMessage),
                  ),
                ),
                const SizedBox(height: 12),
                _StatusCard(snapshot: snapshot),
                if (snapshot.status == CloudAccountStatus.signedIn) ...[
                  const SizedBox(height: 12),
                  _SyncCard(state: state),
                ],
                if (state.errorCode != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error(l, state.errorCode!),
                    key: const Key('cloud-auth-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (snapshot.status == CloudAccountStatus.localOnly)
                  const SizedBox.shrink()
                else if (snapshot.status == CloudAccountStatus.signedIn)
                  FilledButton.icon(
                    key: const Key('cloud-sign-out'),
                    onPressed: state.loading
                        ? null
                        : () => ref
                              .read(cloudAccountControllerProvider.notifier)
                              .signOut(),
                    icon: const Icon(Icons.logout),
                    label: Text(l.signOutAction),
                  )
                else ...[
                  if (snapshot.status ==
                      CloudAccountStatus.awaitingEmailVerification) ...[
                    Text(
                      l.awaitingVerificationBody(
                        state.pendingEmail ?? snapshot.identity?.email ?? '',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: state.loading
                          ? null
                          : () => ref
                                .read(cloudAccountControllerProvider.notifier)
                                .resendVerification(),
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: Text(l.resendVerificationAction),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('cloud-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(labelText: l.emailLabel),
                          validator: (value) =>
                              value == null ||
                                  !value.contains('@') ||
                                  value.trim().length < 5
                              ? l.requiredFieldMessage
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('cloud-password'),
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: l.passwordLabel,
                          ),
                          validator: (value) =>
                              value == null || value.length < 8
                              ? l.requiredFieldMessage
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              key: const Key('cloud-sign-in'),
                              onPressed: state.loading
                                  ? null
                                  : () => _submit(create: false),
                              child: Text(l.signInAction),
                            ),
                            OutlinedButton(
                              key: const Key('cloud-create-account'),
                              onPressed: state.loading
                                  ? null
                                  : () => _submit(create: true),
                              child: Text(l.createEquisAccountAction),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _restoreBody(BuildContext context, CloudAccountState state) {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        EquisGlassCard(
          key: const Key('restore-existing-vault-card'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.restoreExistingVaultTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l.restoreExistingVaultBody),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('restore-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: l.emailLabel),
                    validator: (value) => value == null || !value.contains('@')
                        ? l.requiredFieldMessage
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('restore-password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(labelText: l.passwordLabel),
                    validator: (value) => value == null || value.length < 8
                        ? l.requiredFieldMessage
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('restore-recovery-secret'),
                    controller: _recoverySecret,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l.recoverySecretLabel,
                      helperText: l.recoverySecretRestoreHint,
                    ),
                    validator: (value) =>
                        value == null ||
                            !value.trim().startsWith('equis-recovery-v1_')
                        ? l.requiredFieldMessage
                        : null,
                  ),
                  if (state.errorCode != null ||
                      state.restoreError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.errorCode != null
                          ? _error(l, state.errorCode!)
                          : _restoreError(l, state.restoreError!),
                      key: const Key('restore-vault-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('restore-existing-vault'),
                    onPressed: state.loading ? null : _submitRestore,
                    icon: state.loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                    label: Text(l.restoreAndSyncAction),
                  ),
                  const SizedBox(height: 8),
                  Text(l.restoreLocalDataSafetyMessage),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitRestore() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(cloudAccountControllerProvider.notifier)
        .restoreExisting(
          email: _email.text.trim(),
          password: _password.text,
          recoverySecret: _recoverySecret.text.trim(),
        );
  }

  Future<void> _submit({required bool create}) async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(cloudAccountControllerProvider.notifier);
    if (create) {
      await controller.createAccount(
        email: _email.text.trim(),
        password: _password.text,
      );
    } else {
      await controller.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
  }
}

String _restoreError(
  AppLocalizations l,
  ExistingVaultRestoreFailureCode code,
) => switch (code) {
  ExistingVaultRestoreFailureCode.noVault => l.restoreNoVaultMessage,
  ExistingVaultRestoreFailureCode.multipleVaults =>
    l.restoreMultipleVaultsMessage,
  ExistingVaultRestoreFailureCode.invalidRecoverySecret =>
    l.restoreInvalidSecretMessage,
  ExistingVaultRestoreFailureCode.localVaultExists =>
    l.restoreLocalVaultExistsMessage,
  ExistingVaultRestoreFailureCode.synchronization => l.restoreSyncFailedMessage,
  ExistingVaultRestoreFailureCode.unavailable => l.authUnknownMessage,
};

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snapshot});
  final CloudAccountSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = switch (snapshot.status) {
      CloudAccountStatus.localOnly => l.continueOfflineAction,
      CloudAccountStatus.signedOut ||
      CloudAccountStatus.sessionExpired => l.signInAction,
      CloudAccountStatus.awaitingEmailVerification =>
        l.awaitingVerificationTitle,
      CloudAccountStatus.signedIn => l.cloudSignedInTitle,
    };
    final body = snapshot.status == CloudAccountStatus.signedIn
        ? l.cloudSignedInBody(snapshot.identity?.email ?? '')
        : snapshot.status == CloudAccountStatus.localOnly
        ? l.cloudNotConfiguredMessage
        : l.localAccessPreservedMessage;
    return EquisGlassCard(
      key: Key('cloud-status-${snapshot.status.name}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body),
            const SizedBox(height: 8),
            Text(
              l.deviceIdentityLabel(
                snapshot.device.name,
                snapshot.device.platform,
                snapshot.device.id.value.substring(0, 8),
              ),
            ),
            if (snapshot.binding != null && !snapshot.binding!.syncEnabled) ...[
              const SizedBox(height: 8),
              Text(l.cloudSyncEncryptionPendingMessage),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard({required this.state});

  final CloudAccountState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(cloudAccountControllerProvider.notifier);
    final enabled = state.snapshot?.binding?.syncEnabled == true;
    final secret = state.recoverySecret;
    final statusText = state.syncError
        ? l.syncStatusError
        : switch (state.syncRunStatus) {
            SyncRunStatus.succeeded =>
              state.conflicts.isNotEmpty
                  ? l.syncStatusError
                  : state.pending > 0
                  ? l.syncPendingLabel
                  : l.syncStatusSynced,
            SyncRunStatus.offline => l.syncStatusOffline,
            SyncRunStatus.permanentFailure => l.syncStatusError,
            null => l.syncStatusReady,
          };

    return EquisGlassCard(
      key: const Key('cloud-sync-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.secureSyncTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (state.syncBusy) const LinearProgressIndicator(),
            if (!enabled && secret == null) ...[
              Text(l.secureSyncDisabledBody),
              if (state.syncFailure != null) ...[
                Text(_syncFailureText(l, state.syncFailure!)),
                SelectableText(_setupDiagnostic(state.syncFailure!)),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('enable-secure-sync'),
                onPressed: state.syncBusy
                    ? null
                    : controller.prepareSynchronization,
                icon: const Icon(Icons.lock_outline),
                label: Text(l.enableSecureSyncAction),
              ),
            ] else if (!enabled && secret != null) ...[
              Text(
                l.recoverySecretTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(l.recoverySecretBody),
              const SizedBox(height: 12),
              SelectableText(
                secret,
                key: const Key('sync-recovery-secret'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: secret));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l.recoverySecretCopiedMessage),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(l.copyRecoverySecretAction),
                  ),
                  FilledButton.icon(
                    key: const Key('confirm-recovery-saved'),
                    onPressed: state.syncBusy
                        ? null
                        : controller.confirmRecoverySaved,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text(l.confirmRecoverySavedAction),
                  ),
                ],
              ),
            ] else ...[
              Text(state.syncBusy ? l.syncRunningLabel : statusText),
              Text('${l.syncPendingLabel}: ${state.pending}'),
              Text(l.syncAutomaticPolicy),
              Text(
                '${l.syncLastSuccessLabel}: ${state.lastSuccess?.toLocal().toString() ?? l.syncNeverLabel}',
              ),
              if (state.syncFailure != null) ...[
                Text(_syncFailureText(l, state.syncFailure!)),
                SelectableText(
                  '${state.syncStage?.name ?? "setup"}/${state.syncFailure!.name}',
                ),
              ],
              const SizedBox(height: 6),
              Text(
                l.syncDiagnostics(
                  state.pushed,
                  state.pulled,
                  state.conflicts24h,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('manual-sync-retry'),
                onPressed: state.syncBusy
                    ? null
                    : controller.retrySynchronization,
                icon: const Icon(Icons.sync),
                label: Text(l.retrySyncAction),
              ),
              if (state.conflicts.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  l.syncConflictsTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final conflict in state.conflicts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l.syncEntityTypeLabel(conflict.entityType.wireName),
                    ),
                    subtitle: Text(
                      l.syncConflictBody(
                        l.syncEntityTypeLabel(conflict.entityType.wireName),
                        _prefix(conflict.recordId),
                        conflict.localRevision,
                        conflict.remoteRevision,
                      ),
                    ),
                    trailing: PopupMenuButton<SyncConflictResolution>(
                      onSelected: (resolution) => controller.resolveConflict(
                        conflictId: conflict.id,
                        resolution: resolution,
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: SyncConflictResolution.keepLocal,
                          child: Text(l.keepLocalAction),
                        ),
                        PopupMenuItem(
                          value: SyncConflictResolution.keepRemote,
                          child: Text(l.keepRemoteAction),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _prefix(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);

String _setupDiagnostic(SyncFailureKind failure) => 'setup/${failure.name}';

String _error(AppLocalizations l, CloudAuthFailureCode code) => switch (code) {
  CloudAuthFailureCode.unavailable => l.cloudNotConfiguredMessage,
  CloudAuthFailureCode.invalidCredentials => l.authInvalidCredentialsMessage,
  CloudAuthFailureCode.emailNotVerified => l.authEmailNotVerifiedMessage,
  CloudAuthFailureCode.weakPassword => l.authWeakPasswordMessage,
  CloudAuthFailureCode.accountAlreadyExists => l.authAccountExistsMessage,
  CloudAuthFailureCode.rateLimited => l.authRateLimitedMessage,
  CloudAuthFailureCode.network => l.authNetworkMessage,
  CloudAuthFailureCode.vaultUserMismatch => l.authVaultMismatchMessage,
  CloudAuthFailureCode.unknown => l.authUnknownMessage,
};

String _syncFailureText(AppLocalizations l, SyncFailureKind kind) =>
    switch (kind) {
      SyncFailureKind.keyMismatch => l.syncCryptoHelp,
      SyncFailureKind.clientObsolete => l.syncCompatibilityHelp,
      SyncFailureKind.network => l.syncNetworkHelp,
      SyncFailureKind.sessionExpired => l.syncSessionHelp,
      SyncFailureKind.accessDenied => l.syncAccessHelp,
      SyncFailureKind.incompatibleServer => l.syncCompatibilityHelp,
      SyncFailureKind.invalidPayload => l.syncPayloadHelp,
      SyncFailureKind.cryptography => l.syncCryptoHelp,
      SyncFailureKind.localData => l.syncLocalHelp,
      SyncFailureKind.remote => l.syncRemoteHelp,
    };
