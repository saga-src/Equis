import 'package:flutter/material.dart';

import '../../application/ports/sync_aggregate_store.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/entities/account_removal_assessment.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/equis_formatters.dart';

typedef AccountRemovalAssessor =
    Future<AccountRemovalAssessment> Function(AccountAggregate account);
typedef AccountLifecycleAction =
    Future<void> Function(AccountAggregate account);

/// The caller supplies current accounts and performs all lifecycle mutations.
class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({
    super.key,
    required this.accounts,
    required this.assessRemoval,
    required this.removeAccount,
    required this.restoreAccount,
    this.initialAccountId,
    this.recoveryStates = const [],
    this.requestRecovery,
    this.refreshAccounts,
  });

  final List<AccountAggregate> accounts;
  final AccountRemovalAssessor assessRemoval;
  final AccountLifecycleAction removeAccount;
  final AccountLifecycleAction restoreAccount;
  final EntityId? initialAccountId;
  final List<AccountSyncRecoveryState> recoveryStates;
  final Future<void> Function(AccountSyncRecoveryState)? requestRecovery;
  final VoidCallback? refreshAccounts;

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  EntityId? _busyAccountId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recoveryIds = widget.recoveryStates
        .map((item) => item.accountId)
        .toSet();
    final active = widget.accounts
        .where(
          (item) =>
              item.account.deletedAt == null &&
              !item.account.archived &&
              !recoveryIds.contains(item.account.id.value),
        )
        .toList();
    final archived = widget.accounts
        .where(
          (item) =>
              item.account.deletedAt == null &&
              item.account.archived &&
              !recoveryIds.contains(item.account.id.value),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountManagementTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.recoveryStates.isNotEmpty) ...[
                Text(
                  l10n.accountRecoveryTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(l10n.accountRecoveryExplanation),
                for (final recovery in widget.recoveryStates)
                  _recoveryTile(recovery),
                const SizedBox(height: 24),
              ],
              Text(
                l10n.activeAccountsTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (active.isEmpty)
                ListTile(title: Text(l10n.noActiveAccountsMessage))
              else
                for (final account in active)
                  _accountTile(
                    account,
                    actionLabel: l10n.reviewAccountRemovalAction,
                    actionIcon: Icons.more_horiz,
                    onPressed: () => _reviewRemoval(account),
                  ),
              const SizedBox(height: 24),
              Text(
                l10n.archivedAccountsTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (archived.isEmpty)
                ListTile(title: Text(l10n.noArchivedAccountsMessage))
              else
                for (final account in archived)
                  _accountTile(
                    account,
                    actionLabel: l10n.restoreAccountAction,
                    actionIcon: Icons.restore,
                    onPressed: () => _confirmRestore(account),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recoveryTile(AccountSyncRecoveryState recovery) {
    final l10n = AppLocalizations.of(context);
    AccountAggregate? aggregate;
    for (final item in widget.accounts) {
      if (item.account.id.value == recovery.accountId) aggregate = item;
    }
    final busy = _busyAccountId?.value == recovery.accountId;
    return Card(
      key: ValueKey('account-recovery-${recovery.accountId}'),
      child: ListTile(
        leading: const Icon(Icons.sync_problem_outlined),
        title: Text(aggregate?.account.name ?? l10n.accountLabel),
        subtitle: recovery.restorationPending
            ? Text(l10n.accountRecoveryPendingMessage)
            : null,
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : recovery.restorationPending
            ? null
            : IconButton(
                tooltip: l10n.restoreAccountAction,
                icon: const Icon(Icons.restore),
                onPressed:
                    _busyAccountId == null && widget.requestRecovery != null
                    ? () => _confirmRecovery(recovery)
                    : null,
              ),
      ),
    );
  }

  Future<void> _confirmRecovery(AccountSyncRecoveryState recovery) async {
    if (_busyAccountId != null || recovery.restorationPending) return;
    final l10n = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreAccountAction),
        content: Text(l10n.accountRecoveryConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.restoreAccountAction),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (!widget.recoveryStates.any(
      (state) =>
          state.accountId == recovery.accountId &&
          state.revision == recovery.revision &&
          !state.restorationPending,
    )) {
      _changed();
      return;
    }
    setState(() => _busyAccountId = EntityId.parse(recovery.accountId));
    try {
      await widget.requestRecovery?.call(recovery);
    } on AccountLifecycleConflict {
      if (mounted) _changed();
    } catch (_) {
      if (mounted) {
        _message(AppLocalizations.of(context).accountActionFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Widget _accountTile(
    AccountAggregate aggregate, {
    required String actionLabel,
    required IconData actionIcon,
    required VoidCallback onPressed,
  }) {
    final busy = _busyAccountId == aggregate.account.id;
    final isCard = aggregate.account.type == AccountType.creditCard;
    return Card(
      key: ValueKey('account-${aggregate.account.id.value}'),
      child: ListTile(
        selected: aggregate.account.id == widget.initialAccountId,
        leading: Icon(
          isCard ? Icons.credit_card : Icons.account_balance_wallet,
        ),
        title: Text(aggregate.account.name),
        subtitle: aggregate.account.institution == null
            ? null
            : Text(aggregate.account.institution!),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: actionLabel,
                onPressed: _busyAccountId == null ? onPressed : null,
                icon: Icon(actionIcon),
              ),
      ),
    );
  }

  AccountAggregate? _current(AccountAggregate account) {
    for (final item in widget.accounts) {
      if (item.account.id == account.account.id &&
          item.account.deletedAt == null &&
          item.account.revision == account.account.revision &&
          item.account.archived == account.account.archived) {
        return item;
      }
    }
    return null;
  }

  Future<void> _reviewRemoval(AccountAggregate aggregate) async {
    if (_busyAccountId != null) return;
    setState(() => _busyAccountId = aggregate.account.id);
    try {
      final assessment = await widget.assessRemoval(aggregate);
      if (!mounted) return;
      if (_current(aggregate) == null ||
          assessment.aggregate.account.id != aggregate.account.id ||
          assessment.aggregate.account.revision != aggregate.account.revision) {
        _changed();
        return;
      }
      setState(() => _busyAccountId = null);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => _RemovalDialog(assessment: assessment),
      );
      if (accepted != true || !mounted) return;
      if (_current(aggregate) == null) {
        _changed();
        return;
      }
      setState(() => _busyAccountId = aggregate.account.id);
      await widget.removeAccount(aggregate);
    } on AccountRemovalBlocked {
      if (mounted) _changed();
    } on AccountLifecycleConflict {
      if (mounted) _changed();
    } catch (_) {
      if (mounted) {
        _message(AppLocalizations.of(context).accountActionFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _confirmRestore(AccountAggregate aggregate) async {
    if (_busyAccountId != null) return;
    final l10n = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreAccountAction),
        content: Text(l10n.restoreAccountConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.restoreAccountAction),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (_current(aggregate) == null) {
      _changed();
      return;
    }
    setState(() => _busyAccountId = aggregate.account.id);
    try {
      await widget.restoreAccount(aggregate);
    } on AccountLifecycleConflict {
      if (mounted) _changed();
    } catch (_) {
      if (mounted) {
        _message(AppLocalizations.of(context).accountActionFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _changed() {
    _message(AppLocalizations.of(context).accountChangedMessage);
    widget.refreshAccounts?.call();
  }
}

class _RemovalDialog extends StatelessWidget {
  const _RemovalDialog({required this.assessment});

  final AccountRemovalAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final disposition = assessment.disposition;
    final action = switch (disposition) {
      AccountRemovalDisposition.blocked => null,
      AccountRemovalDisposition.archive => l10n.archiveAccountAction,
      AccountRemovalDisposition.delete => l10n.deleteAccountAction,
    };
    return AlertDialog(
      title: Text(assessment.aggregate.account.name),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (disposition) {
                AccountRemovalDisposition.blocked =>
                  l10n.accountRemovalBlockedMessage,
                AccountRemovalDisposition.archive =>
                  l10n.archiveAccountConfirmation,
                AccountRemovalDisposition.delete =>
                  l10n.deleteAccountConfirmation,
              }),
              if (assessment.balances.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.accountBalancesTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final balance in assessment.balances)
                  Text(
                    EquisFormatters.moneyMinor(
                      context,
                      currency: balance.currency,
                      minor: balance.minorUnits,
                    ),
                  ),
              ],
              if (assessment.hasReferences) ...[
                const SizedBox(height: 12),
                Text(l10n.accountReferencesLabel),
                for (final kind in AccountReferenceKind.values)
                  if ((assessment.references[kind] ?? 0) > 0)
                    Text(
                      '${_referenceLabel(l10n, kind)}: '
                      '${EquisFormatters.integer(context, assessment.references[kind]!)}',
                    ),
              ],
              if (assessment.blockers.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final blocker in assessment.blockers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(_blockerLabel(l10n, blocker)),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancelAction),
        ),
        if (action != null)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
      ],
    );
  }
}

String _blockerLabel(
  AppLocalizations l10n,
  AccountRemovalBlocker blocker,
) => switch (blocker) {
  AccountRemovalBlocker.pocketBalance => l10n.accountBlockerBalance,
  AccountRemovalBlocker.openStatement => l10n.accountBlockerStatement,
  AccountRemovalBlocker.scheduledInstallment => l10n.accountBlockerInstallment,
  AccountRemovalBlocker.activeRecurrence => l10n.accountBlockerRecurrence,
  AccountRemovalBlocker.pendingTransaction => l10n.accountBlockerTransaction,
  AccountRemovalBlocker.activeGoal => l10n.accountBlockerGoal,
  AccountRemovalBlocker.enabledBudget => l10n.accountBlockerBudget,
};

String _referenceLabel(AppLocalizations l10n, AccountReferenceKind kind) =>
    switch (kind) {
      AccountReferenceKind.movements => l10n.accountReferencesMovements,
      AccountReferenceKind.statements => l10n.accountReferencesStatements,
      AccountReferenceKind.installmentPlans =>
        l10n.accountReferencesInstallmentPlans,
      AccountReferenceKind.recurrenceTemplates =>
        l10n.accountReferencesRecurrenceTemplates,
      AccountReferenceKind.transactions => l10n.accountReferencesTransactions,
      AccountReferenceKind.goals => l10n.accountReferencesGoals,
      AccountReferenceKind.budgets => l10n.accountReferencesBudgets,
      AccountReferenceKind.attachments => l10n.accountReferencesAttachments,
    };
