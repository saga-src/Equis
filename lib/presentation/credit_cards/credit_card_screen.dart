import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/credit_cards/credit_card_models.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../shared/equis_glass.dart';
import '../formatting/taxonomy_labels.dart';

class CreditCardScreen extends ConsumerWidget {
  const CreditCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(creditCardControllerProvider);
    final cards = ref.watch(creditCardContextsProvider);
    final snapshot = ref.watch(localFinanceControllerProvider).valueOrNull;
    if (cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.creditCardsTitle)),
        body: Center(child: Text(l10n.noCreditCardsMessage)),
      );
    }
    final overview = state.overview;
    final profile = overview?.profile;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.creditCardsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.statementsTabLabel),
              Tab(text: l10n.installmentsTabLabel),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: state.card?.pocketId.value,
                    decoration: InputDecoration(
                      labelText: l10n.selectCardLabel,
                    ),
                    items: [
                      for (final card in cards)
                        DropdownMenuItem(
                          value: card.pocketId.value,
                          child: Text(
                            '${_accountName(snapshot, card.accountId)} · ${card.currency.value}',
                          ),
                        ),
                    ],
                    onChanged: state.loading
                        ? null
                        : (value) {
                            final card = cards.singleWhere(
                              (item) => item.pocketId.value == value,
                            );
                            ref
                                .read(creditCardControllerProvider.notifier)
                                .select(card);
                          },
                  ),
                  const SizedBox(height: 10),
                  if (profile == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _configure(context, ref),
                        icon: const Icon(Icons.tune),
                        label: Text(l10n.configureCardAction),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: l10n.creditLimitLabel,
                            value: _money(
                              context,
                              state.card!,
                              overview?.limit?.limitMinor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Metric(
                            label: l10n.availableCreditLabel,
                            value: _money(
                              context,
                              state.card!,
                              overview?.availableCreditMinor,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.configureCardAction,
                          onPressed: () => _configure(context, ref),
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _purchase(context, ref),
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text(l10n.addCardPurchaseAction),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _installment(context, ref),
                          icon: const Icon(Icons.calendar_view_month),
                          label: Text(l10n.addInstallmentAction),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _charge(context, ref),
                          icon: const Icon(Icons.percent),
                          label: Text(l10n.feeInterestAction),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _refund(context, ref),
                          icon: const Icon(Icons.undo),
                          label: Text(l10n.refundPurchaseAction),
                        ),
                      ],
                    ),
                  ],
                  if (state.loading) const LinearProgressIndicator(),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.cardLoadFailedMessage,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: profile == null
                  ? Center(child: Text(l10n.configureCardAction))
                  : TabBarView(
                      children: [
                        _StatementsList(
                          values: overview?.statements ?? const [],
                          card: state.card!,
                        ),
                        _InstallmentsList(
                          values: overview?.installmentPlans ?? const [],
                          card: state.card!,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementsList extends ConsumerWidget {
  const _StatementsList({required this.values, required this.card});
  final List<CreditCardStatementView> values;
  final CreditCardContext card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (values.isEmpty) return Center(child: Text(l10n.noStatementsMessage));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final view = values[index];
        return EquisGlassCard(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(
              '${view.statement.periodStart} — ${view.statement.periodEnd}',
            ),
            subtitle: Text(
              '${_statementStatus(l10n, view.statement.status)} · '
              '${l10n.dueDayLabel}: ${view.statement.dueDate}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _money(context, card, view.amounts.dueMinor),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (view.amounts.dueMinor > 0)
                  IconButton(
                    tooltip: l10n.payStatementAction,
                    onPressed: () => _pay(context, ref, view.statement, card),
                    icon: const Icon(Icons.payments_outlined),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InstallmentsList extends ConsumerWidget {
  const _InstallmentsList({required this.values, required this.card});
  final List<InstallmentPlanView> values;
  final CreditCardContext card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (values.isEmpty) return Center(child: Text(l10n.noInstallmentsMessage));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final value = values[index];
        return EquisGlassCard(
          child: ListTile(
            leading: const Icon(Icons.calendar_view_month),
            title: Text(
              value.plan.description ?? '${value.plan.installmentCount}x',
            ),
            subtitle: Text(
              '${l10n.currentInstallmentLabel}: ${value.currentInstallment}/${value.plan.installmentCount} · '
              '${l10n.remainingAmountLabel}: ${_money(context, card, value.remainingMinor)}',
            ),
            trailing: value.plan.status == InstallmentPlanStatus.active
                ? IconButton(
                    tooltip: l10n.cancelInstallmentAction,
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () => ref
                        .read(creditCardControllerProvider.notifier)
                        .cancelPlan(value),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => EquisGlassCard(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.merge(EquisTypography.numeric),
          ),
        ],
      ),
    ),
  );
}

Future<void> _configure(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final state = ref.read(creditCardControllerProvider);
  final closing = TextEditingController(
    text: '${state.overview?.profile?.defaultClosingDay ?? 20}',
  );
  final due = TextEditingController(
    text: '${state.overview?.profile?.defaultDueDay ?? 5}',
  );
  final limit = TextEditingController(
    text: _plainAmount(state.overview?.limit?.limitMinor),
  );
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.configureCardAction),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: closing,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.closingDayLabel),
          ),
          TextField(
            controller: due,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.dueDayLabel),
          ),
          TextField(
            controller: limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.creditLimitLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.saveAction),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await ref
        .read(creditCardControllerProvider.notifier)
        .configure(
          closingDay: int.parse(closing.text),
          dueDay: int.parse(due.text),
          limitText: limit.text,
        );
  }
}

Future<void> _purchase(BuildContext context, WidgetRef ref) =>
    _classifiedCharge(context, ref, fee: false);

Future<void> _charge(BuildContext context, WidgetRef ref) =>
    _classifiedCharge(context, ref, fee: true);

Future<void> _classifiedCharge(
  BuildContext context,
  WidgetRef ref, {
  required bool fee,
}) async {
  final l10n = AppLocalizations.of(context);
  final snapshot = ref.read(localFinanceControllerProvider).valueOrNull;
  final categories =
      snapshot?.categories
          .where((item) => item.type == CategoryType.expense)
          .toList() ??
      const [];
  if (categories.isEmpty) return;
  var category = categories.first.id;
  var date = _today();
  final amount = TextEditingController();
  final title = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(fee ? l10n.feeInterestAction : l10n.addCardPurchaseAction),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: l10n.amountLabel),
              ),
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: l10n.descriptionLabel),
              ),
              DropdownButtonFormField<EntityId>(
                initialValue: category,
                decoration: InputDecoration(labelText: l10n.categoryLabel),
                items: [
                  for (final item in categories)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(categoryLabel(context, item)),
                    ),
                ],
                onChanged: (value) => setState(() => category = value!),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.dateLabel),
                subtitle: Text(EquisFormatters.date(context, date)),
                onTap: () async {
                  final picked = await _pickDate(context, date);
                  if (picked != null) setState(() => date = picked);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    ),
  );
  if (accepted != true) return;
  final controller = ref.read(creditCardControllerProvider.notifier);
  if (fee) {
    await controller.charge(
      amountText: amount.text,
      categoryId: category,
      date: date,
      title: title.text,
    );
  } else {
    await controller.purchase(
      amountText: amount.text,
      categoryId: category,
      date: date,
      title: title.text,
    );
  }
}

Future<void> _installment(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final snapshot = ref.read(localFinanceControllerProvider).valueOrNull;
  final categories =
      snapshot?.categories
          .where((item) => item.type == CategoryType.expense)
          .toList() ??
      const [];
  if (categories.isEmpty) return;
  var category = categories.first.id;
  var date = _today();
  final original = TextEditingController();
  final financed = TextEditingController();
  final count = TextEditingController(text: '12');
  final interest = TextEditingController();
  final description = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.addInstallmentAction),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: original,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.originalAmountLabel,
                ),
              ),
              TextField(
                controller: financed,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.financedAmountLabel,
                ),
              ),
              TextField(
                controller: count,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.installmentCountLabel,
                ),
              ),
              TextField(
                controller: interest,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: l10n.interestRateLabel),
              ),
              TextField(
                controller: description,
                decoration: InputDecoration(labelText: l10n.descriptionLabel),
              ),
              DropdownButtonFormField<EntityId>(
                initialValue: category,
                decoration: InputDecoration(labelText: l10n.categoryLabel),
                items: [
                  for (final item in categories)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(categoryLabel(context, item)),
                    ),
                ],
                onChanged: (value) => setState(() => category = value!),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.firstInstallmentDateLabel),
                subtitle: Text(EquisFormatters.date(context, date)),
                onTap: () async {
                  final picked = await _pickDate(context, date);
                  if (picked != null) setState(() => date = picked);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    ),
  );
  if (accepted == true) {
    await ref
        .read(creditCardControllerProvider.notifier)
        .installment(
          originalText: original.text,
          financedText: financed.text.isEmpty ? original.text : financed.text,
          count: int.parse(count.text),
          categoryId: category,
          firstDate: date,
          description: description.text,
          interestRate: interest.text,
        );
  }
}

Future<void> _pay(
  BuildContext context,
  WidgetRef ref,
  CreditCardStatement statement,
  CreditCardContext card,
) async {
  final l10n = AppLocalizations.of(context);
  final snapshot = ref.read(localFinanceControllerProvider).valueOrNull;
  final pockets = [
    for (final account in snapshot?.accounts ?? const [])
      if (account.account.nature == AccountNature.asset)
        for (final pocket in account.pockets)
          if (pocket.currency == card.currency)
            LedgerPocket(
              id: pocket.id,
              currency: pocket.currency,
              nature: AccountNature.asset,
            ),
  ];
  if (pockets.isEmpty) return;
  var pocket = pockets.first;
  var date = _today();
  final amount = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.payStatementAction),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l10n.amountLabel),
            ),
            DropdownButtonFormField<EntityId>(
              initialValue: pocket.id,
              decoration: InputDecoration(labelText: l10n.accountLabel),
              items: [
                for (final item in pockets)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.id.value.substring(0, 8)),
                  ),
              ],
              onChanged: (value) => setState(
                () => pocket = pockets.singleWhere((item) => item.id == value),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.dateLabel),
              subtitle: Text(EquisFormatters.date(context, date)),
              onTap: () async {
                final picked = await _pickDate(context, date);
                if (picked != null) setState(() => date = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    ),
  );
  if (accepted == true) {
    await ref
        .read(creditCardControllerProvider.notifier)
        .pay(
          statement: statement,
          bankPocket: pocket,
          amountText: amount.text,
          date: date,
        );
  }
}

Future<void> _refund(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final state = ref.read(creditCardControllerProvider);
  final snapshot = ref.read(localFinanceControllerProvider).valueOrNull;
  final purchases =
      snapshot?.recentTransactions
          .where(
            (item) =>
                item.type == LedgerTransactionType.creditCardPurchase &&
                item.status != LedgerTransactionStatus.cancelled &&
                item.movements.any(
                  (movement) => movement.pocket.id == state.card?.pocketId,
                ),
          )
          .toList() ??
      const [];
  if (purchases.isEmpty) return;
  var purchase = purchases.first;
  var date = _today();
  final amount = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.refundPurchaseAction),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<EntityId>(
              initialValue: purchase.id,
              items: [
                for (final item in purchases)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      item.title ??
                          EquisFormatters.date(context, item.financialDate),
                    ),
                  ),
              ],
              onChanged: (value) => setState(
                () => purchase = purchases.singleWhere(
                  (item) => item.id == value,
                ),
              ),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l10n.amountLabel),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.dateLabel),
              subtitle: Text(EquisFormatters.date(context, date)),
              onTap: () async {
                final picked = await _pickDate(context, date);
                if (picked != null) setState(() => date = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    ),
  );
  if (accepted == true) {
    await ref
        .read(creditCardControllerProvider.notifier)
        .refund(original: purchase, amountText: amount.text, date: date);
  }
}

String _accountName(LocalFinanceSnapshot? snapshot, EntityId accountId) {
  if (snapshot == null) return accountId.value.substring(0, 8);
  return snapshot.accounts
      .singleWhere((item) => item.account.id == accountId)
      .account
      .name;
}

String _money(BuildContext context, CreditCardContext card, int? minor) {
  if (minor == null) return '—';
  return EquisFormatters.moneyMinor(
    context,
    currency: card.currency,
    minor: minor,
  );
}

String _plainAmount(int? minor) =>
    minor == null ? '' : (minor / 100).toStringAsFixed(2);

String _statementStatus(
  AppLocalizations l10n,
  CreditCardStatementStatus status,
) => switch (status) {
  CreditCardStatementStatus.future => l10n.futureStatementStatus,
  CreditCardStatementStatus.open => l10n.openStatementStatus,
  CreditCardStatementStatus.closed => l10n.closedStatementStatus,
  CreditCardStatementStatus.paid => l10n.paidStatementStatus,
  CreditCardStatementStatus.overdue => l10n.overdueStatementStatus,
};

Future<LocalDate?> _pickDate(BuildContext context, LocalDate current) async {
  final value = await showDatePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2200),
    initialDate: current.toUtcDate(),
  );
  return value == null ? null : LocalDate(value.year, value.month, value.day);
}

LocalDate _today() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}
