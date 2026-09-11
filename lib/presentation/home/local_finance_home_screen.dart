import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dashboard_overview.dart';
import '../formatting/equis_formatters.dart';
import '../shared/equis_glass.dart';

class LocalFinanceHomeScreen extends ConsumerWidget {
  const LocalFinanceHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(localFinanceControllerProvider);
    return state.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: Text(l10n.appTitle)),
        body: Center(child: Text(l10n.localVaultErrorMessage)),
      ),
      data: (snapshot) => _HomeContent(snapshot: snapshot),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.snapshot});
  final LocalFinanceSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final configured = snapshot?.vault != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          if (configured)
            IconButton(
              tooltip: l10n.intelligenceTitle,
              onPressed: () => context.push('/intelligence'),
              icon: const Icon(Icons.insights_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: configured ? () => context.push('/transactions/new') : null,
        icon: const Icon(Icons.add),
        label: Text(l10n.addTransactionAction),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!configured) ...[
            Text(
              l10n.availableMoneyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            EquisGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('—', style: EquisTypography.numeric),
                    const SizedBox(height: 8),
                    Text(l10n.availableMoneyPlaceholder),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (snapshot?.requiresSetup ?? false)
            const _LocalSetupCard()
          else if (snapshot == null)
            EquisGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.offline_bolt_outlined),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.foundationStatusTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.foundationStatusBody),
                          const SizedBox(height: 12),
                          Chip(label: Text(l10n.offlineReadyLabel)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            DashboardOverview(finance: snapshot!),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  const _AddAccountButton(),
                  TextButton.icon(
                    onPressed: () => context.push('/taxonomy'),
                    icon: const Icon(Icons.category_outlined),
                    label: Text(l10n.manageCategoriesTagsAction),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _RecentTransactions(snapshot: snapshot!),
          ],
        ],
      ),
    );
  }
}

class _AddAccountButton extends ConsumerWidget {
  const _AddAccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    onPressed: () => _show(context, ref),
    icon: const Icon(Icons.account_balance_wallet_outlined),
    label: Text(AppLocalizations.of(context).addAccountAction),
  );

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_NewAccount>(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    );
    if (result == null) return;
    await ref
        .read(localFinanceControllerProvider.notifier)
        .createAccount(
          name: result.name,
          type: result.type,
          nature: result.type == AccountType.creditCard
              ? AccountNature.liability
              : AccountNature.asset,
          currency: result.currency,
        );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _name = TextEditingController();
  AccountType _type = AccountType.checking;
  CurrencyCode _currency = CurrencyCode.brl;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addAccountAction),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('new-account-name'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.accountNameLabel),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: l10n.accountTypeLabel),
              items: [
                DropdownMenuItem(
                  value: AccountType.checking,
                  child: Text(l10n.checkingAccountType),
                ),
                DropdownMenuItem(
                  value: AccountType.savings,
                  child: Text(l10n.savingsAccountType),
                ),
                DropdownMenuItem(
                  value: AccountType.cash,
                  child: Text(l10n.cashAccountType),
                ),
                DropdownMenuItem(
                  value: AccountType.digitalWallet,
                  child: Text(l10n.walletAccountType),
                ),
                DropdownMenuItem(
                  value: AccountType.creditCard,
                  child: Text(l10n.creditCardAccountType),
                ),
              ],
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CurrencyCode>(
              initialValue: _currency,
              decoration: InputDecoration(labelText: l10n.currencyLabel),
              items: [
                DropdownMenuItem(value: CurrencyCode.brl, child: Text('BRL')),
                DropdownMenuItem(value: CurrencyCode.usd, child: Text('USD')),
              ],
              onChanged: (value) => setState(() => _currency = value!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          key: const Key('confirm-add-account'),
          onPressed: () {
            final value = _name.text.trim();
            if (value.isNotEmpty) {
              Navigator.pop(context, _NewAccount(value, _type, _currency));
            }
          },
          child: Text(l10n.addAccountAction),
        ),
      ],
    );
  }
}

final class _NewAccount {
  const _NewAccount(this.name, this.type, this.currency);
  final String name;
  final AccountType type;
  final CurrencyCode currency;
}

class _LocalSetupCard extends ConsumerStatefulWidget {
  const _LocalSetupCard();

  @override
  ConsumerState<_LocalSetupCard> createState() => _LocalSetupCardState();
}

class _LocalSetupCardState extends ConsumerState<_LocalSetupCard> {
  final _formKey = GlobalKey<FormState>();
  final _profileName = TextEditingController();
  final _accountName = TextEditingController();
  CurrencyCode _currency = CurrencyCode.brl;

  @override
  void dispose() {
    _profileName.dispose();
    _accountName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.setupLocalVaultTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(l10n.setupLocalVaultBody),
              const SizedBox(height: 20),
              TextFormField(
                controller: _profileName,
                decoration: InputDecoration(labelText: l10n.profileNameLabel),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountName,
                decoration: InputDecoration(
                  labelText: l10n.firstAccountNameLabel,
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CurrencyCode>(
                initialValue: _currency,
                decoration: InputDecoration(
                  labelText: l10n.reportingCurrencyLabel,
                ),
                items: [
                  DropdownMenuItem(
                    value: CurrencyCode.brl,
                    child: const Text('BRL'),
                  ),
                  DropdownMenuItem(
                    value: CurrencyCode.usd,
                    child: const Text('USD'),
                  ),
                ],
                onChanged: (value) => setState(() => _currency = value!),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('continue-offline'),
                    onPressed: () => _setup(openCloudAccount: false),
                    icon: const Icon(Icons.offline_bolt_outlined),
                    label: Text(l10n.continueOfflineAction),
                  ),
                  OutlinedButton.icon(
                    key: const Key('create-equis-account'),
                    onPressed: () => _setup(openCloudAccount: true),
                    icon: const Icon(Icons.cloud_outlined),
                    label: Text(l10n.createEquisAccountAction),
                  ),
                  TextButton.icon(
                    key: const Key('restore-existing-account'),
                    onPressed: () => context.push('/cloud-account'),
                    icon: const Icon(Icons.login),
                    label: Text(l10n.alreadyHaveAccountAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? AppLocalizations.of(context).requiredFieldMessage
      : null;

  Future<void> _setup({required bool openCloudAccount}) async {
    if (!_formKey.currentState!.validate()) return;
    final locale = Localizations.localeOf(context);
    await ref
        .read(localFinanceControllerProvider.notifier)
        .setup(
          profileName: _profileName.text.trim(),
          accountName: _accountName.text.trim(),
          currency: _currency,
          locale: locale.languageCode == 'pt' ? 'pt-BR' : 'en-US',
          timezone: locale.languageCode == 'pt' ? 'America/Sao_Paulo' : 'UTC',
        );
    if (mounted && openCloudAccount) context.push('/cloud-account');
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions({required this.snapshot});
  final LocalFinanceSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                l10n.recentTransactionsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (snapshot.recentTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(l10n.noRecentTransactionsMessage),
              )
            else
              for (final transaction in snapshot.recentTransactions)
                ListTile(
                  leading: Icon(_icon(transaction.type)),
                  title: Text(_title(context, transaction)),
                  subtitle: Text(
                    '${transaction.financialDate} · ${_status(context, transaction.status)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _amount(context, transaction),
                        style: EquisTypography.numeric,
                      ),
                      PopupMenuButton<_TransactionAction>(
                        onSelected: (action) =>
                            _act(context, ref, transaction, action),
                        itemBuilder: (context) => [
                          if (_editable(transaction))
                            PopupMenuItem(
                              value: _TransactionAction.edit,
                              child: Text(l10n.editTransactionAction),
                            ),
                          if (transaction.status ==
                              LedgerTransactionStatus.cleared)
                            PopupMenuItem(
                              value: _TransactionAction.reconcile,
                              child: Text(l10n.reconcileTransactionAction),
                            ),
                          PopupMenuItem(
                            value: _TransactionAction.delete,
                            child: Text(l10n.deleteTransactionAction),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: _editable(transaction)
                      ? () => context.push(
                          '/transactions/${transaction.id.value}',
                        )
                      : null,
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    LedgerTransaction transaction,
    _TransactionAction action,
  ) async {
    final controller = ref.read(localFinanceControllerProvider.notifier);
    switch (action) {
      case _TransactionAction.edit:
        await context.push('/transactions/${transaction.id.value}');
      case _TransactionAction.reconcile:
        await controller.reconcileTransaction(transaction);
      case _TransactionAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppLocalizations.of(dialogContext).confirmDeleteTitle),
            content: Text(
              AppLocalizations.of(dialogContext).confirmDeleteTransactionBody,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(dialogContext).cancelAction),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(AppLocalizations.of(dialogContext).deleteAction),
              ),
            ],
          ),
        );
        if (confirmed == true) await controller.deleteTransaction(transaction);
    }
  }
}

enum _TransactionAction { edit, reconcile, delete }

bool _editable(LedgerTransaction transaction) =>
    transaction.status != LedgerTransactionStatus.reconciled &&
    transaction.status != LedgerTransactionStatus.cancelled &&
    const {
      LedgerTransactionType.expense,
      LedgerTransactionType.income,
      LedgerTransactionType.transfer,
    }.contains(transaction.type);

IconData _icon(LedgerTransactionType type) => switch (type) {
  LedgerTransactionType.expense => Icons.arrow_upward,
  LedgerTransactionType.income => Icons.arrow_downward,
  LedgerTransactionType.transfer => Icons.swap_horiz,
  _ => Icons.receipt_long_outlined,
};

String _title(BuildContext context, LedgerTransaction transaction) {
  if (transaction.title?.trim().isNotEmpty ?? false) return transaction.title!;
  final l10n = AppLocalizations.of(context);
  return switch (transaction.type) {
    LedgerTransactionType.expense => l10n.expenseTypeLabel,
    LedgerTransactionType.income => l10n.incomeTypeLabel,
    LedgerTransactionType.transfer => l10n.transferTypeLabel,
    _ => transaction.type.stored,
  };
}

String _status(BuildContext context, LedgerTransactionStatus status) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    LedgerTransactionStatus.pending => l10n.statusPendingLabel,
    LedgerTransactionStatus.cleared => l10n.statusClearedLabel,
    LedgerTransactionStatus.reconciled => l10n.statusReconciledLabel,
    LedgerTransactionStatus.cancelled => l10n.statusCancelledLabel,
  };
}

String _amount(BuildContext context, LedgerTransaction transaction) {
  if (transaction.type == LedgerTransactionType.transfer) return '↔';
  final movement = transaction.movements.first;
  final sign = transaction.type == LedgerTransactionType.expense ? '−' : '+';
  return '$sign ${EquisFormatters.moneyMinor(context, currency: movement.pocket.currency, minor: movement.amountMinor.abs())}';
}
