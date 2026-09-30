import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/app_providers.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../application/services/everyday_transaction_service.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/equis_formatters.dart';
import '../formatting/taxonomy_labels.dart';
import 'transaction_detail_controller.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({required this.transactionId, super.key});

  final String? transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final finance = ref.watch(localFinanceControllerProvider);
    return finance.when(
      loading: () => Scaffold(
        appBar: AppBar(
          title: Text(l10n.transactionDetailTitle),
          leading: _homeLeading(context, l10n),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(
          title: Text(l10n.transactionDetailTitle),
          leading: _homeLeading(context, l10n),
        ),
        body: Center(child: Text(l10n.localVaultErrorMessage)),
      ),
      data: (snapshot) {
        final vaultId = snapshot?.vault?.id;
        final id = _parseId(transactionId);
        if (vaultId == null || id == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.transactionDetailTitle),
              leading: _homeLeading(context, l10n),
            ),
            body: Center(
              child: Text(
                vaultId == null
                    ? l10n.setupRequiredMessage
                    : l10n.transactionNotFoundMessage,
              ),
            ),
          );
        }
        final key = TransactionDetailKey(vaultId: vaultId, transactionId: id);
        final detail = ref.watch(transactionDetailControllerProvider(key));
        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.transactionDetailTitle),
            leading: _homeLeading(context, l10n),
            actions: [
              if (detail.data case final data?
                  when everydayTransactionCanEdit(
                    data.transaction,
                    accounts: data.accounts,
                    categories: data.categories,
                  ))
                TextButton.icon(
                  onPressed: () async {
                    await context.push('/transactions/${id.value}');
                    if (context.mounted) {
                      await ref
                          .read(
                            transactionDetailControllerProvider(key).notifier,
                          )
                          .reload();
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.editTransactionAction),
                ),
            ],
          ),
          body: switch (detail.status) {
            TransactionDetailStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            TransactionDetailStatus.missing => Center(
              child: Text(l10n.transactionNotFoundMessage),
            ),
            TransactionDetailStatus.error => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.transactionDetailLoadFailedMessage),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref
                        .read(transactionDetailControllerProvider(key).notifier)
                        .reload(),
                    child: Text(l10n.transactionDetailRetryAction),
                  ),
                ],
              ),
            ),
            TransactionDetailStatus.ready => TransactionDetailContent(
              data: detail.data!,
            ),
          },
        );
      },
    );
  }

  Widget? _homeLeading(BuildContext context, AppLocalizations l10n) =>
      GoRouter.of(context).canPop()
      ? null
      : IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: l10n.homeNavigationLabel,
          onPressed: () => context.go('/'),
        );
}

class TransactionDetailContent extends StatelessWidget {
  const TransactionDetailContent({required this.data, super.key});

  final TransactionDetailData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transaction = data.transaction;
    final accountsByPocket = {
      for (final account in data.accounts)
        if (account.account.vaultId == transaction.vaultId)
          for (final pocket in account.pockets) pocket.id: account,
    };
    final categories = {
      for (final category in data.categories)
        if (category.vaultId == transaction.vaultId) category.id: category,
    };
    final tags = {
      for (final tag in data.tags)
        if (tag.vaultId == transaction.vaultId) tag.id: tag,
    };
    final movements = [...transaction.movements]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final splits = [...transaction.splits]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          transaction.title?.trim().isNotEmpty == true
              ? transaction.title!
              : l10n.transactionTypeName(transaction.type.stored),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(l10n.transactionTypeName(transaction.type.stored)),
            ),
            Chip(label: Text(_status(l10n, transaction.status))),
            Chip(
              label: Text(
                EquisFormatters.date(context, transaction.financialDate),
              ),
            ),
          ],
        ),
        _section(context, l10n.transactionDetailMovementsTitle),
        for (final movement in movements)
          Card(
            child: ListTile(
              title: Text(
                _accountName(
                  l10n,
                  movement,
                  accountsByPocket[movement.pocket.id],
                ),
              ),
              subtitle: movement.statementId == null
                  ? null
                  : Text(
                      '${l10n.transactionDetailStatementLabel}: ${movement.statementId!.value}',
                    ),
              trailing: Text(
                EquisFormatters.moneyMinor(
                  context,
                  currency: movement.pocket.currency,
                  minor: movement.amountMinor,
                ),
              ),
            ),
          ),
        if (splits.isNotEmpty) ...[
          _section(context, l10n.transactionDetailSplitsTitle),
          for (final split in splits)
            Card(
              child: ListTile(
                title: Text(
                  categories[split.categoryId] == null
                      ? split.categoryId.value
                      : categoryLabel(context, categories[split.categoryId]!),
                ),
                subtitle: split.memo == null || split.memo!.trim().isEmpty
                    ? null
                    : Text(split.memo!),
                trailing: Text(
                  EquisFormatters.moneyMinor(
                    context,
                    currency: split.money.currency,
                    minor: split.money.minorUnits,
                  ),
                ),
              ),
            ),
        ],
        if (transaction.tagIds.isNotEmpty) ...[
          _section(context, l10n.transactionDetailTagsTitle),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tagId in transaction.tagIds)
                Chip(
                  label: Text(
                    tags[tagId] == null
                        ? tagId.value
                        : tagLabel(context, tags[tagId]!),
                  ),
                ),
            ],
          ),
        ],
        if (transaction.notes?.trim().isNotEmpty == true) ...[
          _section(context, l10n.notesLabel),
          Text(transaction.notes!),
        ],
        if (transaction.fxConversion case final fx?) ...[
          _section(context, l10n.transactionDetailFxTitle),
          _field(l10n.transactionDetailRateLabel, fx.exchangeRate),
          _field(l10n.transactionDetailRateSourceLabel, fx.rateSource),
          if (fx.provider != null)
            _field(l10n.transactionDetailProviderLabel, fx.provider!),
          if (fx.rateDate != null)
            _field(l10n.dateLabel, EquisFormatters.date(context, fx.rateDate!)),
        ],
        if (transaction.investmentEvents.isNotEmpty) ...[
          _section(context, l10n.transactionDetailInvestmentEventsTitle),
          for (final event in transaction.investmentEvents)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(
                      l10n.transactionDetailEventTypeLabel,
                      event.eventType,
                    ),
                    _field(
                      l10n.transactionDetailInstrumentLabel,
                      event.instrumentId.value,
                    ),
                    if (event.quantity != null)
                      _field(
                        l10n.transactionDetailQuantityLabel,
                        event.quantity!,
                      ),
                    if (event.unitPrice != null)
                      _field(
                        l10n.transactionDetailUnitPriceLabel,
                        '${event.unitPrice} ${event.priceCurrency?.value ?? ''}'
                            .trim(),
                      ),
                    if (event.grossMinor != null)
                      _moneyField(
                        context,
                        l10n.transactionDetailGrossLabel,
                        event.grossMinor!,
                        event.priceCurrency ?? movements.first.pocket.currency,
                      ),
                    if (event.feesMinor != null)
                      _moneyField(
                        context,
                        l10n.transactionDetailFeesLabel,
                        event.feesMinor!,
                        event.priceCurrency ?? movements.first.pocket.currency,
                      ),
                    if (event.taxesMinor != null)
                      _moneyField(
                        context,
                        l10n.transactionDetailTaxesLabel,
                        event.taxesMinor!,
                        event.priceCurrency ?? movements.first.pocket.currency,
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (transaction.recurringRuleId != null) ...[
          _section(context, l10n.transactionDetailRecurrenceTitle),
          _field(
            l10n.transactionDetailRuleLabel,
            transaction.recurringRuleId!.value,
          ),
          if (transaction.recurrenceDate != null)
            _field(
              l10n.dateLabel,
              EquisFormatters.date(context, transaction.recurrenceDate!),
            ),
        ],
        if (transaction.reversalOfId != null) ...[
          _section(context, l10n.transactionDetailReversalTitle),
          _field(
            l10n.transactionDetailReversalOfLabel,
            transaction.reversalOfId!.value,
          ),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text('$label: $value'),
  );

  Widget _moneyField(
    BuildContext context,
    String label,
    int amount,
    CurrencyCode currency,
  ) => _field(
    label,
    EquisFormatters.moneyMinor(context, currency: currency, minor: amount),
  );

  String _accountName(
    AppLocalizations l10n,
    LedgerMovement movement,
    AccountAggregate? account,
  ) {
    if (account == null) {
      return '${movement.pocket.id.value} · ${movement.pocket.currency.value}';
    }
    final pocket = account.pockets.firstWhere(
      (candidate) => candidate.id == movement.pocket.id,
    );
    final name = [
      account.account.name,
      if (pocket.name?.trim().isNotEmpty == true) pocket.name!.trim(),
      movement.pocket.currency.value,
    ].join(' · ');
    if (account.account.deletedAt != null) {
      return '$name (${l10n.transactionDetailDeletedAccountLabel})';
    }
    if (account.account.archived) {
      return '$name (${l10n.transactionDetailArchivedAccountLabel})';
    }
    return pocket.archived
        ? '$name (${l10n.transactionDetailArchivedPocketLabel})'
        : name;
  }

  String _status(AppLocalizations l10n, LedgerTransactionStatus status) =>
      switch (status) {
        LedgerTransactionStatus.pending => l10n.statusPendingLabel,
        LedgerTransactionStatus.cleared => l10n.statusClearedLabel,
        LedgerTransactionStatus.reconciled => l10n.statusReconciledLabel,
        LedgerTransactionStatus.cancelled => l10n.statusCancelledLabel,
      };
}

EntityId? _parseId(String? raw) {
  if (raw == null) return null;
  try {
    return EntityId.parse(raw);
  } on FormatException {
    return null;
  }
}
