import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/app_providers.dart';
import '../../domain/entities/account_removal_assessment.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import 'account_management_screen.dart';

class AccountManagementPage extends ConsumerWidget {
  const AccountManagementPage({super.key, this.initialAccountId});

  final String? initialAccountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finance = ref.watch(localFinanceControllerProvider);
    final vaultId = finance.valueOrNull?.vault?.id;
    if (vaultId == null) {
      return _status(context, loading: finance.isLoading);
    }
    final accounts = ref.watch(accountManagementAccountsProvider(vaultId));
    final recovery = ref.watch(accountRecoveryStatesProvider(vaultId));
    return accounts.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
      loading: () => _status(context, loading: true),
      error: (_, _) => _status(context, onRetry: () => _refresh(ref, vaultId)),
      data: (values) => recovery.when(
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: false,
        loading: () => _status(context, loading: true),
        error: (_, _) =>
            _status(context, onRetry: () => _refresh(ref, vaultId)),
        data: (states) => AccountManagementScreen(
          key: ValueKey(vaultId.value),
          accounts: values,
          recoveryStates: states,
          refreshAccounts: () => _refresh(ref, vaultId),
          initialAccountId: _parseId(initialAccountId),
          assessRemoval: (account) async {
            _requireCurrentVault(ref, vaultId);
            return ref
                .read(localAppDependenciesProvider)!
                .session
                .assessAccountRemoval(account, now: UtcInstant.now());
          },
          removeAccount: (account) => _mutate(
            ref,
            vaultId,
            () => ref
                .read(localFinanceControllerProvider.notifier)
                .removeAccount(account),
          ),
          restoreAccount: (account) => _mutate(
            ref,
            vaultId,
            () => ref
                .read(localFinanceControllerProvider.notifier)
                .restoreAccount(account),
          ),
          requestRecovery: (state) async {
            await _mutate(
              ref,
              vaultId,
              () => ref
                  .read(localFinanceControllerProvider.notifier)
                  .requestAccountRestore(vaultId: vaultId, recovery: state),
            );
            final coordinator = ref
                .read(localAppDependenciesProvider)
                ?.syncCoordinator;
            if (coordinator != null) {
              unawaited(coordinator.onResume().then((_) {}, onError: (_) {}));
            }
          },
        ),
      ),
    );
  }

  void _requireCurrentVault(WidgetRef ref, EntityId vaultId) {
    if (ref.read(localFinanceControllerProvider).valueOrNull?.vault?.id !=
        vaultId) {
      throw const AccountLifecycleConflict();
    }
  }

  Future<void> _mutate(
    WidgetRef ref,
    EntityId vaultId,
    Future<void> Function() action,
  ) async {
    _requireCurrentVault(ref, vaultId);
    try {
      await action();
    } finally {
      _refresh(ref, vaultId);
    }
  }

  void _refresh(WidgetRef ref, EntityId vaultId) {
    ref.invalidate(accountManagementAccountsProvider(vaultId));
    ref.invalidate(accountRecoveryStatesProvider(vaultId));
  }

  Widget _status(
    BuildContext context, {
    bool loading = false,
    VoidCallback? onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountManagementTitle)),
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.accountActionFailedMessage),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: Text(l10n.transactionDetailRetryAction),
                    ),
                ],
              ),
      ),
    );
  }

  EntityId? _parseId(String? value) {
    if (value == null) return null;
    try {
      return EntityId.parse(value);
    } on FormatException {
      return null;
    }
  }
}
