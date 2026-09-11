import 'package:flutter/material.dart';
import '../formatting/equis_formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/ledger/transaction_search.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../shared/equis_glass.dart';
import '../formatting/taxonomy_labels.dart';
import 'transaction_history_controller.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({this.initialFilter, super.key});
  final TransactionSearchFilter? initialFilter;
  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    _applyInitialFilter();
  }

  @override
  void didUpdateWidget(TransactionHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != oldWidget.initialFilter) _applyInitialFilter();
  }

  void _applyInitialFilter() {
    final filter = widget.initialFilter;
    if (filter == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(transactionHistoryControllerProvider.notifier).apply(filter);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(localFinanceControllerProvider).valueOrNull;
    final history = ref.watch(transactionHistoryControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transactionHistoryTitle),
        actions: [
          TextButton.icon(
            onPressed: snapshot?.vault == null
                ? null
                : () => _openFilters(context, ref, snapshot!, history.filter),
            icon: const Icon(Icons.tune),
            label: Text(l10n.filtersAction),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: snapshot?.vault == null
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/transactions/new'),
              tooltip: l10n.addTransactionAction,
              child: const Icon(Icons.add),
            ),
      body: _body(context, ref, snapshot, history),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot? snapshot,
    TransactionHistoryState history,
  ) {
    final l10n = AppLocalizations.of(context);
    if (snapshot?.vault == null) {
      return Center(child: Text(l10n.setupRequiredMessage));
    }
    if (history.error != null && history.items.isEmpty) {
      return Center(child: Text(l10n.historySearchFailedMessage));
    }
    if (history.loading && history.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.items.isEmpty) {
      return Center(child: Text(l10n.noHistoryResultsMessage));
    }
    return RefreshIndicator(
      onRefresh: () => ref
          .read(transactionHistoryControllerProvider.notifier)
          .apply(history.filter!),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: history.items.length + (history.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == history.items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: history.loading
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: ref
                            .read(transactionHistoryControllerProvider.notifier)
                            .loadMore,
                        child: Text(l10n.loadMoreAction),
                      ),
              ),
            );
          }
          final transaction = history.items[index];
          return EquisGlassCard(
            child: ListTile(
              leading: Icon(_icon(transaction.type)),
              title: Text(
                transaction.title?.trim().isNotEmpty == true
                    ? transaction.title!
                    : _typeLabel(l10n, transaction.type),
              ),
              subtitle: Text(
                '${transaction.financialDate} · ${_statusLabel(l10n, transaction.status)}',
              ),
              trailing: Text(
                _amount(context, transaction),
                style: EquisTypography.numeric,
              ),
              onTap: _editable(transaction)
                  ? () => context.push('/transactions/${transaction.id.value}')
                  : null,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFilters(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot snapshot,
    TransactionSearchFilter? current,
  ) async {
    final filter = await showDialog<TransactionSearchFilter>(
      context: context,
      builder: (context) =>
          _HistoryFilterDialog(snapshot: snapshot, current: current),
    );
    if (filter != null) {
      await ref
          .read(transactionHistoryControllerProvider.notifier)
          .apply(filter);
    }
  }
}

class _HistoryFilterDialog extends StatefulWidget {
  const _HistoryFilterDialog({required this.snapshot, this.current});

  final LocalFinanceSnapshot snapshot;
  final TransactionSearchFilter? current;

  @override
  State<_HistoryFilterDialog> createState() => _HistoryFilterDialogState();
}

class _HistoryFilterDialogState extends State<_HistoryFilterDialog> {
  late final TextEditingController _merchant;
  late final TextEditingController _notes;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  LocalDate? _from;
  LocalDate? _to;
  EntityId? _accountId;
  EntityId? _categoryId;
  EntityId? _tagId;
  bool _withoutTags = false;
  bool _reportingExpensesOnly = false;
  CurrencyCode? _currency;
  bool _descendants = false;
  late Set<LedgerTransactionType> _types;
  late Set<LedgerTransactionStatus> _statuses;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _merchant = TextEditingController(text: current?.merchantQuery);
    _notes = TextEditingController(text: current?.notesQuery);
    _minimum = TextEditingController(
      text: _majorText(current?.minimumAmountMinor),
    );
    _maximum = TextEditingController(
      text: _majorText(current?.maximumAmountMinor),
    );
    _from = current?.fromDate;
    _to = current?.toDate;
    _accountId = current?.accountId;
    _categoryId = current?.categoryId;
    _tagId = current?.tagId;
    _withoutTags = current?.withoutTags ?? false;
    _reportingExpensesOnly = current?.reportingExpensesOnly ?? false;
    _currency = current?.currency;
    _descendants = current?.includeDescendantCategories ?? false;
    _types = {...?current?.types};
    _statuses = {...?current?.statuses};
  }

  @override
  void dispose() {
    _merchant.dispose();
    _notes.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencies =
        widget.snapshot.accounts
            .expand((account) => account.pockets)
            .map((pocket) => pocket.currency)
            .toSet()
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    return AlertDialog(
      title: Text(l10n.historyFiltersTitle),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _merchant,
                decoration: InputDecoration(labelText: l10n.payeeLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: InputDecoration(labelText: l10n.notesLabel),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minimum,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.minimumAmountLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maximum,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.maximumAmountLabel,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: l10n.fromDateLabel,
                      value: _from,
                      onChanged: (value) => setState(() => _from = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: l10n.toDateLabel,
                      value: _to,
                      onChanged: (value) => setState(() => _to = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EntityId?>(
                initialValue: _accountId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.accountLabel),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.anyValueLabel),
                  ),
                  for (final account in widget.snapshot.accounts)
                    DropdownMenuItem(
                      value: account.account.id,
                      child: Text(account.account.name),
                    ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EntityId?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.categoryLabel),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.anyValueLabel),
                  ),
                  for (final category in widget.snapshot.categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(categoryLabel(context, category)),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _descendants,
                onChanged: _categoryId == null
                    ? null
                    : (value) => setState(() => _descendants = value ?? false),
                title: Text(l10n.includeDescendantCategoriesLabel),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.withoutTagsLabel),
                value: _withoutTags,
                onChanged: (value) => setState(() {
                  _withoutTags = value;
                  if (value) _tagId = null;
                }),
              ),
              DropdownButtonFormField<EntityId?>(
                key: ValueKey(_withoutTags),
                initialValue: _tagId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.tagFilterLabel),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.anyValueLabel),
                  ),
                  for (final tag in widget.snapshot.tags)
                    DropdownMenuItem(
                      value: tag.id,
                      child: Text(tagLabel(context, tag)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _tagId = value;
                  _withoutTags = false;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CurrencyCode?>(
                initialValue: _currency,
                decoration: InputDecoration(labelText: l10n.currencyLabel),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.anyValueLabel),
                  ),
                  for (final currency in currencies)
                    DropdownMenuItem(
                      value: currency,
                      child: Text(currency.value),
                    ),
                ],
                onChanged: (value) => setState(() => _currency = value),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.transactionTypeLabel),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final type in LedgerTransactionType.values)
                      FilterChip(
                        label: Text(_typeLabel(l10n, type)),
                        selected: _types.contains(type),
                        onSelected: (selected) => setState(() {
                          selected ? _types.add(type) : _types.remove(type);
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(l10n.statusFilterLabel),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final status in LedgerTransactionStatus.values)
                      FilterChip(
                        label: Text(_statusLabel(l10n, status)),
                        selected: _statuses.contains(status),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _statuses.add(status)
                              : _statuses.remove(status);
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _clear, child: Text(l10n.clearFiltersAction)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(onPressed: _apply, child: Text(l10n.applyFiltersAction)),
      ],
    );
  }

  void _clear() {
    Navigator.pop(
      context,
      TransactionSearchFilter(vaultId: widget.snapshot.vault!.id),
    );
  }

  void _apply() {
    try {
      Navigator.pop(
        context,
        TransactionSearchFilter(
          vaultId: widget.snapshot.vault!.id,
          merchantQuery: _merchant.text,
          notesQuery: _notes.text,
          minimumAmountMinor: _minorUnits(_minimum.text),
          maximumAmountMinor: _minorUnits(_maximum.text),
          fromDate: _from,
          toDate: _to,
          accountId: _accountId,
          categoryId: _categoryId,
          includeDescendantCategories: _descendants,
          tagId: _withoutTags ? null : _tagId,
          withoutTags: _withoutTags,
          reportingExpensesOnly: _reportingExpensesOnly,
          currency: _currency,
          types: _types,
          statuses: _statuses,
        ),
      );
    } on Object {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).invalidFiltersMessage),
        ),
      );
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final LocalDate? value;
  final ValueChanged<LocalDate?> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final now = DateTime.now();
      final selected = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(now.year + 10),
        initialDate: value == null
            ? now
            : DateTime(value!.year, value!.month, value!.day),
      );
      if (selected != null) {
        onChanged(LocalDate(selected.year, selected.month, selected.day));
      }
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: value == null
            ? const Icon(Icons.calendar_today_outlined)
            : IconButton(
                tooltip: AppLocalizations.of(context).clearValueAction,
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.clear),
              ),
      ),
      child: Text(value?.toString() ?? '—'),
    ),
  );
}

int? _minorUnits(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final parts = normalized.split('.');
  if (parts.length > 2 || !RegExp(r'^\d+$').hasMatch(parts.first)) {
    throw const FormatException();
  }
  final fraction = parts.length == 1 ? '' : parts.last;
  if (fraction.length > 2 ||
      (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction))) {
    throw const FormatException();
  }
  return int.parse(parts.first) * 100 +
      int.parse(
        fraction.padRight(2, '0').isEmpty ? '0' : fraction.padRight(2, '0'),
      );
}

String _majorText(int? minor) {
  if (minor == null) return '';
  return '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}

String _typeLabel(AppLocalizations l10n, LedgerTransactionType type) =>
    l10n.transactionTypeName(type.stored);

String _statusLabel(AppLocalizations l10n, LedgerTransactionStatus status) =>
    switch (status) {
      LedgerTransactionStatus.pending => l10n.statusPendingLabel,
      LedgerTransactionStatus.cleared => l10n.statusClearedLabel,
      LedgerTransactionStatus.reconciled => l10n.statusReconciledLabel,
      LedgerTransactionStatus.cancelled => l10n.statusCancelledLabel,
    };

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

String _amount(BuildContext context, LedgerTransaction transaction) {
  if (transaction.type == LedgerTransactionType.transfer) return '↔';
  final movement = transaction.movements.first;
  final sign = movement.amountMinor < 0 ? '−' : '+';
  return '$sign ${EquisFormatters.moneyMinor(context, currency: movement.pocket.currency, minor: movement.amountMinor.abs())}';
}
