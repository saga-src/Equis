import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';

import '../../app/providers/app_providers.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/investments/investment_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../shared/equis_glass.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/taxonomy_labels.dart';
import 'investment_controller.dart';

class InvestmentScreen extends ConsumerWidget {
  const InvestmentScreen({this.financeOverride, this.stateOverride, super.key});
  final LocalFinanceSnapshot? financeOverride;
  final InvestmentState? stateOverride;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final finance =
        financeOverride ??
        ref.watch(localFinanceControllerProvider).valueOrNull;
    final InvestmentState state =
        stateOverride ?? ref.watch(investmentControllerProvider);
    final report = state.report;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.investmentsTitle),
        actions: [
          IconButton(
            tooltip: l.refreshPricesAction,
            onPressed: state.loading
                ? null
                : () => ref
                      .read(investmentControllerProvider.notifier)
                      .refreshPrices(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: finance?.vault == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addInstrument(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l.addInstrumentAction),
            ),
      body: finance?.vault == null
          ? Center(child: Text(l.setupRequiredMessage))
          : state.loading && report == null
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && report == null
          ? Center(child: Text(l.investmentLoadFailedMessage))
          : report == null
          ? Center(child: Text(l.noInvestmentsMessage))
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(investmentControllerProvider.notifier).reload(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PortfolioSummary(report: report),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _cashAction(context, ref, finance!, 'fee'),
                        icon: const Icon(Icons.receipt_outlined),
                        label: Text(l.feeInvestmentAction),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _cashAction(context, ref, finance!, 'deposit'),
                        icon: const Icon(Icons.south_west),
                        label: Text(l.depositInvestmentAction),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _cashAction(context, ref, finance!, 'withdraw'),
                        icon: const Icon(Icons.north_east),
                        label: Text(l.withdrawInvestmentAction),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (report.holdings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.noInvestmentsMessage),
                    ),
                  for (final holding in report.holdings)
                    _HoldingCard(
                      holding: holding,
                      price: _priceFor(state.prices, holding.instrument.id),
                      onAction: (action) => _instrumentAction(
                        context,
                        ref,
                        finance!,
                        holding,
                        action,
                      ),
                    ),
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }

  Future<void> _addInstrument(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_InstrumentDraft>(
      context: context,
      builder: (_) => const _InstrumentDialog(),
    );
    if (draft != null) {
      await ref
          .read(investmentControllerProvider.notifier)
          .createInstrument(
            name: draft.name,
            symbol: draft.symbol,
            exchange: draft.exchange,
            assetClass: draft.assetClass,
          );
    }
  }

  Future<void> _instrumentAction(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance,
    HoldingReport holding,
    String action,
  ) async {
    if (action == 'price') {
      final draft = await showDialog<_PriceDraft>(
        context: context,
        builder: (_) => const _PriceDialog(),
      );
      if (draft != null) {
        await ref
            .read(investmentControllerProvider.notifier)
            .overridePrice(holding.instrument, draft.price, draft.date);
      }
      return;
    }
    final pockets = _investmentPockets(finance, holding.instrument.currency);
    if (pockets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).cashAccountLabel)),
      );
      return;
    }
    if (action == 'buy' || action == 'sell') {
      final draft = await showDialog<_TradeDraft>(
        context: context,
        builder: (_) => _TradeDialog(sell: action == 'sell', pockets: pockets),
      );
      if (draft != null) {
        await ref
            .read(investmentControllerProvider.notifier)
            .trade(
              instrument: holding.instrument,
              pocket: draft.pocket,
              quantity: draft.quantity,
              unitPrice: draft.price,
              fees: draft.fees,
              taxes: draft.taxes,
              date: draft.date,
              sell: action == 'sell',
            );
      }
      return;
    }
    if (action == 'dividend' || action == 'interest') {
      final categories = finance.categories
          .where((item) => item.type == CategoryType.income)
          .toList();
      if (categories.isEmpty) {
        return;
      }
      final draft = await showDialog<_IncomeDraft>(
        context: context,
        builder: (_) => _IncomeDialog(
          interest: action == 'interest',
          pockets: pockets,
          categories: categories,
        ),
      );
      if (draft != null) {
        await ref
            .read(investmentControllerProvider.notifier)
            .income(
              instrument: holding.instrument,
              pocket: draft.pocket,
              categoryId: draft.category.id,
              amount: draft.amount,
              date: draft.date,
              interest: action == 'interest',
            );
      }
    }
  }

  Future<void> _cashAction(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance,
    String action,
  ) async {
    final currency = finance.vault!.baseCurrency;
    final investment = _investmentPockets(finance, currency);
    if (investment.isEmpty) return;
    final controller = ref.read(investmentControllerProvider.notifier);
    if (action == 'fee') {
      final categories = finance.categories
          .where((item) => item.type == CategoryType.expense)
          .toList();
      if (categories.isEmpty) return;
      final draft = await showDialog<_IncomeDraft>(
        context: context,
        builder: (_) =>
            _AmountCategoryDialog(pockets: investment, categories: categories),
      );
      if (draft != null) {
        await controller.fee(
          pocket: draft.pocket,
          categoryId: draft.category.id,
          amount: draft.amount,
          date: draft.date,
        );
      }
      return;
    }
    final regular = _regularPockets(finance, currency);
    if (regular.isEmpty) return;
    final draft = await showDialog<_CashTransferDraft>(
      context: context,
      builder: (_) => _CashTransferDialog(
        regular: regular,
        investment: investment,
        deposit: action == 'deposit',
      ),
    );
    if (draft != null) {
      await controller.transferCash(
        regular: draft.regular,
        investment: draft.investment,
        amount: draft.amount,
        date: draft.date,
        deposit: action == 'deposit',
      );
    }
  }
}

class _PortfolioSummary extends StatelessWidget {
  const _PortfolioSummary({required this.report});
  final PortfolioReport report;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.portfolioValueLabel),
            Text(
              _money(context, report.currency, report.marketValueMinor),
              key: const Key('portfolio-value'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Metric(
                  l.portfolioCostLabel,
                  _money(context, report.currency, report.costBasisMinor),
                ),
                _Metric(
                  l.unrealizedResultLabel,
                  _money(context, report.currency, report.unrealizedMinor),
                ),
                _Metric(
                  l.realizedResultLabel,
                  _money(context, report.currency, report.realizedMinor),
                ),
                _Metric(
                  l.investmentIncomeLabel,
                  _money(context, report.currency, report.incomeMinor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.holding,
    required this.price,
    required this.onAction,
  });
  final HoldingReport holding;
  final MarketPriceState? price;
  final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final i = holding.instrument;
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    i.symbol?.isNotEmpty ?? false
                        ? '${i.symbol} · ${i.name}'
                        : i.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: onAction,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'buy',
                      child: Text(l.buyInvestmentAction),
                    ),
                    PopupMenuItem(
                      value: 'sell',
                      child: Text(l.sellInvestmentAction),
                    ),
                    PopupMenuItem(
                      value: 'dividend',
                      child: Text(l.dividendInvestmentAction),
                    ),
                    PopupMenuItem(
                      value: 'interest',
                      child: Text(l.interestInvestmentAction),
                    ),
                    PopupMenuItem(
                      value: 'price',
                      child: Text(l.manualPriceAction),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              '${l.quantityLabel}: ${holding.quantity}  ·  ${l.averageCostLabel}: ${holding.averageCost} ${i.currency.value}',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: holding.allocationBps / 10000),
            const SizedBox(height: 6),
            Text(
              '${l.allocationLabel}: ${(holding.allocationBps / 100).toStringAsFixed(1)}%',
            ),
            if (holding.marketValueMinor == null &&
                holding.quantity > Decimal.zero)
              Text(l.missingMarketPriceMessage),
            if (price?.stale ?? false)
              Text(
                l.stalePriceMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (price?.refreshFailed ?? false)
              Text(
                l.priceRefreshFailedMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (holding.marketValueMinor != null)
              Text(
                '${l.portfolioValueLabel}: ${_money(context, i.currency, holding.marketValueMinor!)} · '
                '${l.unrealizedResultLabel}: ${_money(context, i.currency, holding.unrealizedMinor ?? 0)}',
              ),
            Text(
              '${l.realizedResultLabel}: ${_money(context, i.currency, holding.realizedMinor)} · '
              '${l.investmentIncomeLabel}: ${_money(context, i.currency, holding.incomeMinor)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceDialog extends StatefulWidget {
  const _PriceDialog();

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final price = TextEditingController();
  var date = _today();

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.manualPriceAction),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l.unitPriceLabel),
            ),
            _DateRow(
              label: l.investmentDateLabel,
              date: date,
              onChanged: (value) => setState(() => date = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (price.text.trim().isNotEmpty) {
              Navigator.pop(context, _PriceDraft(price.text.trim(), date));
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _InstrumentDialog extends StatefulWidget {
  const _InstrumentDialog();
  @override
  State<_InstrumentDialog> createState() => _InstrumentDialogState();
}

class _InstrumentDialogState extends State<_InstrumentDialog> {
  final name = TextEditingController(),
      symbol = TextEditingController(),
      exchange = TextEditingController();
  var assetClass = InvestmentAssetClass.stock;
  @override
  void dispose() {
    name.dispose();
    symbol.dispose();
    exchange.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.addInstrumentAction),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: l.instrumentNameLabel),
            ),
            TextField(
              controller: symbol,
              decoration: InputDecoration(labelText: l.instrumentSymbolLabel),
            ),
            TextField(
              controller: exchange,
              decoration: InputDecoration(labelText: l.instrumentExchangeLabel),
            ),
            DropdownButtonFormField(
              initialValue: assetClass,
              decoration: InputDecoration(labelText: l.assetClassLabel),
              items: [
                for (final value in InvestmentAssetClass.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(l.investmentAssetClassLabel(value.name)),
                  ),
              ],
              onChanged: (value) => setState(() => assetClass = value!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isNotEmpty) {
              Navigator.pop(
                context,
                _InstrumentDraft(
                  name.text.trim(),
                  symbol.text.trim(),
                  exchange.text.trim(),
                  assetClass,
                ),
              );
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _TradeDialog extends StatefulWidget {
  const _TradeDialog({required this.sell, required this.pockets});
  final bool sell;
  final List<_NamedPocket> pockets;
  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  final quantity = TextEditingController(),
      price = TextEditingController(),
      fees = TextEditingController(),
      taxes = TextEditingController();
  late _NamedPocket pocket;
  var date = _today();
  @override
  void initState() {
    super.initState();
    pocket = widget.pockets.first;
  }

  @override
  void dispose() {
    for (final c in [quantity, price, fees, taxes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.sell ? l.sellInvestmentAction : l.buyInvestmentAction),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: pocket,
              decoration: InputDecoration(labelText: l.cashAccountLabel),
              items: [
                for (final p in widget.pockets)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => pocket = v!),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.quantityLabel),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.unitPriceLabel),
            ),
            TextField(
              controller: fees,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.feesLabel),
            ),
            TextField(
              controller: taxes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.taxesLabel),
            ),
            _DateRow(
              label: l.investmentDateLabel,
              date: date,
              onChanged: (v) => setState(() => date = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (quantity.text.isNotEmpty && price.text.isNotEmpty) {
              Navigator.pop(
                context,
                _TradeDraft(
                  pocket.pocket,
                  quantity.text,
                  price.text,
                  fees.text,
                  taxes.text,
                  date,
                ),
              );
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _IncomeDialog extends StatefulWidget {
  const _IncomeDialog({
    required this.interest,
    required this.pockets,
    required this.categories,
  });
  final bool interest;
  final List<_NamedPocket> pockets;
  final List<CategoryNode> categories;
  @override
  State<_IncomeDialog> createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<_IncomeDialog> {
  final amount = TextEditingController();
  late _NamedPocket pocket;
  late CategoryNode category;
  var date = _today();
  @override
  void initState() {
    super.initState();
    pocket = widget.pockets.first;
    category = widget.categories.first;
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.interest
            ? l.interestInvestmentAction
            : l.dividendInvestmentAction,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: pocket,
              items: [
                for (final p in widget.pockets)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => pocket = v!),
            ),
            DropdownButtonFormField(
              initialValue: category,
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(
                    value: c,
                    child: Text(categoryLabel(context, c)),
                  ),
              ],
              onChanged: (v) => setState(() => category = v!),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.investmentAmountLabel),
            ),
            _DateRow(
              label: l.investmentDateLabel,
              date: date,
              onChanged: (v) => setState(() => date = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (amount.text.isNotEmpty) {
              Navigator.pop(
                context,
                _IncomeDraft(pocket.pocket, category, amount.text, date),
              );
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _AmountCategoryDialog extends StatefulWidget {
  const _AmountCategoryDialog({
    required this.pockets,
    required this.categories,
  });
  final List<_NamedPocket> pockets;
  final List<CategoryNode> categories;
  @override
  State<_AmountCategoryDialog> createState() => _AmountCategoryDialogState();
}

class _AmountCategoryDialogState extends State<_AmountCategoryDialog> {
  final amount = TextEditingController();
  late _NamedPocket pocket;
  late CategoryNode category;
  var date = _today();
  @override
  void initState() {
    super.initState();
    pocket = widget.pockets.first;
    category = widget.categories.first;
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.feeInvestmentAction),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: pocket,
              items: [
                for (final p in widget.pockets)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => pocket = v!),
            ),
            DropdownButtonFormField(
              initialValue: category,
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(
                    value: c,
                    child: Text(categoryLabel(context, c)),
                  ),
              ],
              onChanged: (v) => setState(() => category = v!),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.investmentAmountLabel),
            ),
            _DateRow(
              label: l.investmentDateLabel,
              date: date,
              onChanged: (v) => setState(() => date = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (amount.text.isNotEmpty) {
              Navigator.pop(
                context,
                _IncomeDraft(pocket.pocket, category, amount.text, date),
              );
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _CashTransferDialog extends StatefulWidget {
  const _CashTransferDialog({
    required this.regular,
    required this.investment,
    required this.deposit,
  });
  final List<_NamedPocket> regular;
  final List<_NamedPocket> investment;
  final bool deposit;
  @override
  State<_CashTransferDialog> createState() => _CashTransferDialogState();
}

class _CashTransferDialogState extends State<_CashTransferDialog> {
  final amount = TextEditingController();
  late _NamedPocket regular, investment;
  var date = _today();
  @override
  void initState() {
    super.initState();
    regular = widget.regular.first;
    investment = widget.investment.first;
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.deposit ? l.depositInvestmentAction : l.withdrawInvestmentAction,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: regular,
              items: [
                for (final p in widget.regular)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => regular = v!),
            ),
            DropdownButtonFormField(
              initialValue: investment,
              items: [
                for (final p in widget.investment)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => investment = v!),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.investmentAmountLabel),
            ),
            _DateRow(
              label: l.investmentDateLabel,
              date: date,
              onChanged: (v) => setState(() => date = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (amount.text.isNotEmpty) {
              Navigator.pop(
                context,
                _CashTransferDraft(
                  regular.pocket,
                  investment.pocket,
                  amount.text,
                  date,
                ),
              );
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.onChanged,
  });
  final String label;
  final LocalDate date;
  final ValueChanged<LocalDate> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(EquisFormatters.date(context, date)),
    trailing: const Icon(Icons.calendar_today),
    onTap: () async {
      final v = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
        initialDate: date.toUtcDate(),
      );
      if (v != null) onChanged(LocalDate(v.year, v.month, v.day));
    },
  );
}

List<_NamedPocket> _investmentPockets(
  LocalFinanceSnapshot finance,
  CurrencyCode currency,
) => [
  for (final aggregate in finance.accounts)
    if (aggregate.account.type == AccountType.investment)
      for (final pocket in aggregate.pockets)
        if (pocket.currency == currency)
          _NamedPocket(
            aggregate.account.name,
            LedgerPocket(
              id: pocket.id,
              currency: pocket.currency,
              nature: aggregate.account.nature,
            ),
          ),
];
List<_NamedPocket> _regularPockets(
  LocalFinanceSnapshot finance,
  CurrencyCode currency,
) => [
  for (final aggregate in finance.accounts)
    if (aggregate.account.type != AccountType.investment &&
        aggregate.account.nature == AccountNature.asset)
      for (final pocket in aggregate.pockets)
        if (pocket.currency == currency)
          _NamedPocket(
            aggregate.account.name,
            LedgerPocket(
              id: pocket.id,
              currency: pocket.currency,
              nature: aggregate.account.nature,
            ),
          ),
];

final class _NamedPocket {
  const _NamedPocket(this.name, this.pocket);
  final String name;
  final LedgerPocket pocket;
}

final class _InstrumentDraft {
  const _InstrumentDraft(
    this.name,
    this.symbol,
    this.exchange,
    this.assetClass,
  );
  final String name, symbol, exchange;
  final InvestmentAssetClass assetClass;
}

final class _TradeDraft {
  const _TradeDraft(
    this.pocket,
    this.quantity,
    this.price,
    this.fees,
    this.taxes,
    this.date,
  );
  final LedgerPocket pocket;
  final String quantity, price, fees, taxes;
  final LocalDate date;
}

final class _IncomeDraft {
  const _IncomeDraft(this.pocket, this.category, this.amount, this.date);
  final LedgerPocket pocket;
  final CategoryNode category;
  final String amount;
  final LocalDate date;
}

final class _CashTransferDraft {
  const _CashTransferDraft(
    this.regular,
    this.investment,
    this.amount,
    this.date,
  );
  final LedgerPocket regular, investment;
  final String amount;
  final LocalDate date;
}

final class _PriceDraft {
  const _PriceDraft(this.price, this.date);
  final String price;
  final LocalDate date;
}

MarketPriceState? _priceFor(
  List<MarketPriceState> prices,
  EntityId instrumentId,
) {
  for (final price in prices) {
    if (price.instrument.id == instrumentId) return price;
  }
  return null;
}

String _money(BuildContext context, CurrencyCode c, int v) =>
    EquisFormatters.moneyMinor(context, currency: c, minor: v);
LocalDate _today() {
  final n = DateTime.now();
  return LocalDate(n.year, n.month, n.day);
}
