import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';

import '../../app/providers/app_providers.dart';
import '../../application/ports/investment_repository.dart';
import '../../application/services/investment_service.dart';
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
    final hasInvestmentAccount =
        finance != null && _allInvestmentPockets(finance).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.investmentsTitle),
        actions: [
          IconButton(
            key: const Key('market-data-info'),
            tooltip: l.marketDataInfoTooltip,
            onPressed: () => _showMarketDataInfo(context),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: l.refreshPricesAction,
            onPressed: state.loading
                ? null
                : () => _refreshPrices(context, ref),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: finance?.vault == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addInstrument(context, ref, finance!),
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
                  if (!hasInvestmentAccount) ...[
                    _InvestmentAccountGuide(
                      currency: finance!.vault!.baseCurrency,
                      onPressed: () => _showBrokerageAccountGuide(
                        context,
                        ref,
                        finance,
                        currency: finance.vault!.baseCurrency,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (state.error != null) ...[
                    _InlineInvestmentError(
                      message: l.investmentActionFailedMessage,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (state.lastRefresh != null) ...[
                    _MarketRefreshSummaryCard(summary: state.lastRefresh!),
                    const SizedBox(height: 12),
                  ],
                  _PortfolioSummary(report: report),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _cashAction(context, ref, finance, 'fee'),
                        icon: const Icon(Icons.receipt_outlined),
                        label: Text(l.feeInvestmentAction),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _cashAction(context, ref, finance, 'deposit'),
                        icon: const Icon(Icons.south_west),
                        label: Text(l.depositInvestmentAction),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _cashAction(context, ref, finance, 'withdraw'),
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
                        finance,
                        holding,
                        action,
                        latestPrice:
                            _priceFor(
                              state.prices,
                              holding.instrument.id,
                            )?.quote?.price ??
                            holding.price?.price,
                      ),
                    ),
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }

  void _showMarketDataInfo(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('market-data-info-dialog'),
        title: Row(
          children: [
            Icon(Icons.query_stats_outlined, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(l.marketDataInfoTitle)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MarketDataInfoPoint(
                icon: Icons.hub_outlined,
                text: l.marketDataInfoProviders,
              ),
              const SizedBox(height: 16),
              _MarketDataInfoPoint(
                icon: Icons.schedule_outlined,
                text: l.marketDataInfoDelay,
              ),
              const SizedBox(height: 16),
              _MarketDataInfoPoint(
                icon: Icons.edit_outlined,
                text: l.marketDataInfoManualPriority,
              ),
              const Divider(height: 32),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l.marketDataAttribution,
                  style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _addInstrument(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance,
  ) async {
    final draft = await showDialog<_InstrumentDraft>(
      context: context,
      builder: (_) => _InstrumentDialog(
        currencies: _availableCurrencies(finance),
        initialCurrency: finance.vault!.baseCurrency,
        pockets: _allInvestmentPockets(finance),
        controller: ref.read(investmentControllerProvider.notifier),
      ),
    );
    if (!context.mounted) return;
    if (draft != null) {
      await _runInvestmentMutation(
        context,
        () => ref
            .read(investmentControllerProvider.notifier)
            .createInstrument(
              name: draft.name,
              symbol: draft.symbol,
              exchange: draft.exchange,
              assetClass: draft.assetClass,
              currency: draft.currency,
              candidate: draft.candidate,
              preview: draft.preview,
              initialMode: draft.initialMode,
              initialPocket: draft.initialPocket,
              quantity: draft.quantity,
              unitPrice: draft.price,
              fees: draft.fees,
              taxes: draft.taxes,
              date: draft.date,
            ),
      );
    }
  }

  Future<void> _refreshPrices(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(investmentControllerProvider.notifier);
    await _runInvestmentMutation(context, controller.refreshPrices);
  }

  Future<void> _instrumentAction(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance,
    HoldingReport holding,
    String action, {
    Decimal? latestPrice,
  }) async {
    if (action == 'delete') {
      await _deleteAsset(context, ref, holding.instrument);
      return;
    }
    if (action == 'price') {
      final draft = await showDialog<_PriceDraft>(
        context: context,
        builder: (_) => const _PriceDialog(),
      );
      if (!context.mounted) return;
      if (draft != null) {
        await _runInvestmentMutation(
          context,
          () => ref
              .read(investmentControllerProvider.notifier)
              .overridePrice(holding.instrument, draft.price, draft.date),
        );
      }
      return;
    }
    if (action == 'link') {
      final controller = ref.read(investmentControllerProvider.notifier);
      final draft = await showDialog<_MarketLinkDraft>(
        context: context,
        builder: (_) => _MarketLinkDialog(
          instrument: holding.instrument,
          controller: controller,
        ),
      );
      if (!context.mounted) return;
      if (draft != null) {
        await _runInvestmentMutation(
          context,
          () => controller.linkMarketCandidate(
            instrument: holding.instrument,
            candidate: draft.candidate,
            preview: draft.preview,
          ),
        );
      }
      return;
    }
    final pockets = _investmentPockets(finance, holding.instrument.currency);
    if (pockets.isEmpty) {
      await _showBrokerageAccountGuide(
        context,
        ref,
        finance,
        currency: holding.instrument.currency,
        lockCurrency: true,
      );
      return;
    }
    if (action == 'buy' || action == 'sell') {
      final draft = await showDialog<_TradeDraft>(
        context: context,
        builder: (_) => _TradeDialog(
          sell: action == 'sell',
          pockets: pockets,
          initialUnitPrice: latestPrice,
        ),
      );
      if (!context.mounted) return;
      if (draft != null) {
        await _runInvestmentMutation(
          context,
          () => ref
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
              ),
        );
      }
      return;
    }
    if (action == 'dividend' || action == 'interest') {
      final categories = finance.categories
          .where((item) => item.type == CategoryType.income)
          .toList();
      if (categories.isEmpty) {
        _showMessage(
          context,
          AppLocalizations.of(context).missingInvestmentCategoryMessage,
        );
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
      if (!context.mounted) return;
      if (draft != null) {
        await _runInvestmentMutation(
          context,
          () => ref
              .read(investmentControllerProvider.notifier)
              .income(
                instrument: holding.instrument,
                pocket: draft.pocket,
                categoryId: draft.category.id,
                amount: draft.amount,
                date: draft.date,
                interest: action == 'interest',
              ),
        );
      }
    }
  }

  Future<void> _deleteAsset(
    BuildContext context,
    WidgetRef ref,
    InvestmentInstrument instrument,
  ) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.deleteInvestmentAssetAction),
        content: Text(l.confirmDeleteInvestmentAssetBody(instrument.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.deleteAction),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    try {
      await ref.read(investmentControllerProvider.notifier).delete(instrument);
      if (context.mounted) {
        _showMessage(
          context,
          AppLocalizations.of(context).investmentAssetDeletedMessage,
        );
      }
    } on InvestmentAssetInUse {
      if (context.mounted) {
        _showMessage(
          context,
          AppLocalizations.of(context).investmentAssetDeleteBlockedMessage,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(
          context,
          AppLocalizations.of(context).investmentActionFailedMessage,
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
    final controller = ref.read(investmentControllerProvider.notifier);
    if (action == 'fee') {
      final investment = _allInvestmentPockets(finance);
      if (investment.isEmpty) {
        await _showBrokerageAccountGuide(
          context,
          ref,
          finance,
          currency: finance.vault!.baseCurrency,
        );
        return;
      }
      final categories = finance.categories
          .where((item) => item.type == CategoryType.expense)
          .toList();
      if (categories.isEmpty) {
        _showMessage(
          context,
          AppLocalizations.of(context).missingInvestmentCategoryMessage,
        );
        return;
      }
      final draft = await showDialog<_IncomeDraft>(
        context: context,
        builder: (_) =>
            _AmountCategoryDialog(pockets: investment, categories: categories),
      );
      if (!context.mounted) return;
      if (draft != null) {
        await _runInvestmentMutation(
          context,
          () => controller.fee(
            pocket: draft.pocket,
            categoryId: draft.category.id,
            amount: draft.amount,
            date: draft.date,
          ),
        );
      }
      return;
    }
    final regular = _allRegularPockets(finance);
    if (regular.isEmpty) {
      _showMessage(
        context,
        AppLocalizations.of(context).missingRegularInvestmentAccountMessage,
      );
      return;
    }
    final regularCurrencies = regular
        .map((item) => item.pocket.currency)
        .toSet();
    final investment = _allInvestmentPockets(finance)
        .where((item) => regularCurrencies.contains(item.pocket.currency))
        .toList();
    if (investment.isEmpty) {
      await _showBrokerageAccountGuide(
        context,
        ref,
        finance,
        currency: regular.first.pocket.currency,
        lockCurrency: true,
      );
      return;
    }
    final investmentCurrencies = investment
        .map((item) => item.pocket.currency)
        .toSet();
    final compatibleRegular = regular
        .where((item) => investmentCurrencies.contains(item.pocket.currency))
        .toList();
    final draft = await showDialog<_CashTransferDraft>(
      context: context,
      builder: (_) => _CashTransferDialog(
        regular: compatibleRegular,
        investment: investment,
        deposit: action == 'deposit',
      ),
    );
    if (!context.mounted) return;
    if (draft != null) {
      await _runInvestmentMutation(
        context,
        () => controller.transferCash(
          regular: draft.regular,
          investment: draft.investment,
          amount: draft.amount,
          date: draft.date,
          deposit: action == 'deposit',
        ),
      );
    }
  }

  Future<void> _showBrokerageAccountGuide(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance, {
    required CurrencyCode currency,
    bool lockCurrency = false,
  }) async {
    final draft = await showDialog<_BrokerageAccountDraft>(
      context: context,
      builder: (_) => _BrokerageAccountDialog(
        currencies: _availableCurrencies(finance),
        initialCurrency: currency,
        lockCurrency: lockCurrency,
      ),
    );
    if (!context.mounted) return;
    if (draft == null) return;
    try {
      await ref
          .read(localFinanceControllerProvider.notifier)
          .createAccount(
            name: draft.name,
            type: AccountType.investment,
            nature: AccountNature.asset,
            currency: draft.currency,
          );
      await ref.read(investmentControllerProvider.notifier).reload();
      if (context.mounted) {
        _showMessage(
          context,
          AppLocalizations.of(context).investmentAccountCreatedMessage,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(
          context,
          AppLocalizations.of(context).investmentActionFailedMessage,
        );
      }
    }
  }

  Future<void> _runInvestmentMutation(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        _showMessage(
          context,
          AppLocalizations.of(context).investmentActionFailedMessage,
        );
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MarketDataInfoPoint extends StatelessWidget {
  const _MarketDataInfoPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _InvestmentAccountGuide extends StatelessWidget {
  const _InvestmentAccountGuide({
    required this.currency,
    required this.onPressed,
  });
  final CurrencyCode currency;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.investmentAccountSetupTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.investmentAccountSetupBody(currency.value)),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('create-investment-account'),
              onPressed: onPressed,
              icon: const Icon(Icons.account_balance_outlined),
              label: Text(l.createInvestmentAccountAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineInvestmentError extends StatelessWidget {
  const _InlineInvestmentError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _MarketRefreshSummaryCard extends StatelessWidget {
  const _MarketRefreshSummaryCard({required this.summary});
  final MarketRefreshSummary summary;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              summary.failed == 0
                  ? Icons.check_circle_outline
                  : Icons.warning_amber,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(
                  context,
                ).marketRefreshSummary(summary.updated, summary.failed),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
                    if (i.providerSymbol == null || i.providerName == null)
                      PopupMenuItem(
                        value: 'link',
                        child: Text(l.linkMarketAssetAction),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l.deleteInvestmentAssetAction),
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
  const _InstrumentDialog({
    required this.currencies,
    required this.initialCurrency,
    required this.pockets,
    required this.controller,
  });
  final List<CurrencyCode> currencies;
  final CurrencyCode initialCurrency;
  final List<_NamedPocket> pockets;
  final InvestmentController controller;
  @override
  State<_InstrumentDialog> createState() => _InstrumentDialogState();
}

class _InstrumentDialogState extends State<_InstrumentDialog> {
  final name = TextEditingController(),
      symbol = TextEditingController(),
      exchange = TextEditingController(),
      quantity = TextEditingController(),
      price = TextEditingController(),
      fees = TextEditingController(),
      taxes = TextEditingController();
  var assetClass = InvestmentAssetClass.stock;
  late CurrencyCode currency;
  Timer? _debounce;
  var _request = 0;
  var _searching = false;
  var _searchFailed = false;
  var _manual = false;
  var _addPosition = false;
  var _mode = InitialPositionMode.historicalBuy;
  var _date = _today();
  List<MarketInstrumentCandidate> _results = const [];
  MarketInstrumentCandidate? _selected;
  MarketQuotePreview? _preview;
  LedgerPocket? _pocket;

  @override
  void initState() {
    super.initState();
    currency = widget.initialCurrency;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    name.dispose();
    symbol.dispose();
    exchange.dispose();
    quantity.dispose();
    price.dispose();
    fees.dispose();
    taxes.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    if (_manual || _selected != null || value.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchFailed = false;
      });
      return;
    }
    final request = ++_request;
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await widget.controller.searchInstruments(
          query: value,
          assetClass: assetClass,
          currency: currency,
        );
        if (!mounted || request != _request) return;
        setState(() {
          _results = results;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _results = const [];
          _searching = false;
          _searchFailed = true;
        });
      }
    });
  }

  Future<void> _select(MarketInstrumentCandidate candidate) async {
    _debounce?.cancel();
    setState(() {
      _selected = candidate;
      _manual = false;
      _results = const [];
      _preview = null;
      _searching = true;
      _searchFailed = false;
      assetClass = candidate.assetClass;
      currency = candidate.currency;
      name.text = candidate.name;
      symbol.text = candidate.symbol;
      exchange.text = candidate.exchange ?? '';
      _pocket = null;
    });
    try {
      final preview = await widget.controller.quoteCandidate(candidate);
      if (!mounted || _selected != candidate) return;
      setState(() {
        _preview = preview;
        _searching = false;
        if (preview != null) price.text = preview.price.toString();
      });
    } catch (_) {
      if (!mounted || _selected != candidate) return;
      setState(() {
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _preview = null;
      _manual = false;
      name.clear();
      symbol.clear();
      exchange.clear();
      price.clear();
      _pocket = null;
      _searchFailed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currencies = <CurrencyCode>{...widget.currencies, currency}.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final pockets = widget.pockets
        .where((item) => item.pocket.currency == currency)
        .toList();
    final canSave =
        name.text.trim().isNotEmpty &&
        (!_addPosition ||
            (_pocket != null &&
                quantity.text.trim().isNotEmpty &&
                price.text.trim().isNotEmpty));
    return AlertDialog(
      title: Text(l.addInstrumentAction),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<InvestmentAssetClass>(
                initialValue: assetClass,
                decoration: InputDecoration(labelText: l.assetClassLabel),
                items: [
                  for (final value in InvestmentAssetClass.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(l.investmentAssetClassLabel(value.name)),
                    ),
                ],
                onChanged: _selected != null
                    ? null
                    : (value) {
                        setState(() => assetClass = value!);
                        _scheduleSearch(symbol.text);
                      },
              ),
              DropdownButtonFormField<CurrencyCode>(
                key: const Key('instrument-currency'),
                initialValue: currency,
                decoration: InputDecoration(labelText: l.currencyLabel),
                items: [
                  for (final value in currencies)
                    DropdownMenuItem(value: value, child: Text(value.value)),
                ],
                onChanged: _selected != null
                    ? null
                    : (value) {
                        setState(() {
                          currency = value!;
                          _pocket = null;
                        });
                        _scheduleSearch(symbol.text);
                      },
              ),
              TextField(
                controller: symbol,
                readOnly: _selected != null,
                onChanged: _scheduleSearch,
                decoration: InputDecoration(
                  labelText: l.assetSearchLabel,
                  hintText: l.assetSearchHint,
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
              if (_results.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (_, index) {
                      final item = _results[index];
                      return ListTile(
                        title: Text('${item.symbol} · ${item.name}'),
                        subtitle: Text(
                          [
                            if (item.exchange?.isNotEmpty ?? false)
                              item.exchange!,
                            item.currency.value,
                            item.provider.name,
                          ].join(' · '),
                        ),
                        onTap: () => _select(item),
                      );
                    },
                  ),
                ),
              if (!_searching &&
                  !_manual &&
                  _selected == null &&
                  symbol.text.trim().length >= 2 &&
                  _results.isEmpty)
                Text(
                  _searchFailed ? l.assetSearchFailed : l.assetSearchNoResults,
                ),
              if (_selected != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close),
                    label: Text(l.clearAssetSelectionAction),
                  ),
                )
              else if (!_manual)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _manual = true;
                      _results = const [];
                      _searchFailed = false;
                    }),
                    child: Text(l.addAssetManuallyAction),
                  ),
                ),
              TextField(
                controller: name,
                readOnly: _selected != null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l.instrumentNameLabel),
              ),
              TextField(
                controller: exchange,
                readOnly: _selected != null,
                decoration: InputDecoration(
                  labelText: l.instrumentExchangeLabel,
                ),
              ),
              if (_preview != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.currentMarketPriceLabel),
                  trailing: Text(
                    '${_preview!.price} ${_preview!.currency.value}',
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.addInitialPositionLabel),
                value: _addPosition,
                onChanged: (value) => setState(() => _addPosition = value),
              ),
              if (_addPosition) ...[
                DropdownButtonFormField<InitialPositionMode>(
                  initialValue: _mode,
                  decoration: InputDecoration(
                    labelText: l.initialPositionModeLabel,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: InitialPositionMode.historicalBuy,
                      child: Text(l.historicalBuyMode),
                    ),
                    DropdownMenuItem(
                      value: InitialPositionMode.openingPosition,
                      child: Text(l.openingPositionMode),
                    ),
                  ],
                  onChanged: (value) => setState(() => _mode = value!),
                ),
                if (_mode == InitialPositionMode.openingPosition)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l.openingPositionDescription),
                  ),
                DropdownButtonFormField<LedgerPocket>(
                  key: ValueKey(
                    '${currency.value}-${_pocket?.id.value ?? 'none'}',
                  ),
                  initialValue:
                      pockets.any((item) => item.pocket.id == _pocket?.id)
                      ? _pocket
                      : null,
                  decoration: InputDecoration(labelText: l.cashAccountLabel),
                  items: [
                    for (final item in pockets)
                      DropdownMenuItem(
                        value: item.pocket,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: pockets.isEmpty
                      ? null
                      : (value) => setState(() => _pocket = value),
                ),
                if (pockets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l.investmentAccountSetupBody(currency.value)),
                  ),
                TextField(
                  controller: quantity,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: l.quantityLabel),
                ),
                TextField(
                  controller: price,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: l.unitPriceLabel),
                ),
                TextField(
                  controller: fees,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: l.feesLabel),
                ),
                TextField(
                  controller: taxes,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: l.taxesLabel),
                ),
                _DateRow(
                  label: l.investmentDateLabel,
                  date: _date,
                  onChanged: (value) => setState(() => _date = value),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.pop(
                  context,
                  _InstrumentDraft(
                    name: name.text.trim(),
                    symbol: symbol.text.trim(),
                    exchange: exchange.text.trim(),
                    assetClass: assetClass,
                    currency: currency,
                    candidate: _selected,
                    preview: _preview,
                    initialMode: _addPosition ? _mode : null,
                    initialPocket: _addPosition ? _pocket : null,
                    quantity: quantity.text.trim(),
                    price: price.text.trim(),
                    fees: fees.text.trim(),
                    taxes: taxes.text.trim(),
                    date: _date,
                  ),
                )
              : null,
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _MarketLinkDialog extends StatefulWidget {
  const _MarketLinkDialog({required this.instrument, required this.controller});

  final InvestmentInstrument instrument;
  final InvestmentController controller;

  @override
  State<_MarketLinkDialog> createState() => _MarketLinkDialogState();
}

class _MarketLinkDialogState extends State<_MarketLinkDialog> {
  final query = TextEditingController();
  Timer? _debounce;
  var _request = 0;
  var _loading = false;
  var _failed = false;
  List<MarketInstrumentCandidate> _results = const [];
  MarketInstrumentCandidate? _selected;
  MarketQuotePreview? _preview;

  @override
  void initState() {
    super.initState();
    query.text = widget.instrument.symbol ?? '';
    if (query.text.length >= 2) _schedule(query.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void _schedule(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _selected = null;
      _preview = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final values = await widget.controller.searchInstruments(
          query: value,
          assetClass: widget.instrument.assetClass,
          currency: widget.instrument.currency,
        );
        if (!mounted || request != _request) return;
        setState(() {
          _results = values
              .where((item) => item.currency == widget.instrument.currency)
              .toList();
          _loading = false;
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _results = const [];
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  Future<void> _select(MarketInstrumentCandidate candidate) async {
    setState(() {
      _selected = candidate;
      _preview = null;
      _loading = true;
      _failed = false;
    });
    try {
      final preview = await widget.controller.quoteCandidate(candidate);
      if (!mounted || _selected != candidate) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || _selected != candidate) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.linkMarketAssetTitle),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: query,
              autofocus: true,
              onChanged: _schedule,
              decoration: InputDecoration(
                labelText: l.assetSearchLabel,
                hintText: l.assetSearchHint,
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ),
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, index) {
                    final item = _results[index];
                    return ListTile(
                      selected: item == _selected,
                      title: Text('${item.symbol} · ${item.name}'),
                      subtitle: Text(
                        '${item.exchange ?? ''} · ${item.provider.name}',
                      ),
                      onTap: () => _select(item),
                    );
                  },
                ),
              ),
            if (!_loading && query.text.trim().length >= 2 && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _failed ? l.assetSearchFailed : l.assetSearchNoResults,
                ),
              ),
            if (_preview != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.currentMarketPriceLabel),
                trailing: Text(
                  '${_preview!.price} ${_preview!.currency.value}',
                ),
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
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(
                  context,
                  _MarketLinkDraft(_selected!, _preview),
                ),
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

class _BrokerageAccountDialog extends StatefulWidget {
  const _BrokerageAccountDialog({
    required this.currencies,
    required this.initialCurrency,
    required this.lockCurrency,
  });
  final List<CurrencyCode> currencies;
  final CurrencyCode initialCurrency;
  final bool lockCurrency;

  @override
  State<_BrokerageAccountDialog> createState() =>
      _BrokerageAccountDialogState();
}

class _BrokerageAccountDialogState extends State<_BrokerageAccountDialog> {
  final name = TextEditingController();
  late CurrencyCode currency;

  @override
  void initState() {
    super.initState();
    currency = widget.initialCurrency;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.investmentAccountSetupTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('brokerage-name'),
              autofocus: true,
              controller: name,
              decoration: InputDecoration(labelText: l.brokerageNameLabel),
            ),
            DropdownButtonFormField<CurrencyCode>(
              key: const Key('brokerage-currency'),
              initialValue: currency,
              decoration: InputDecoration(labelText: l.currencyLabel),
              items: [
                for (final value in widget.currencies)
                  DropdownMenuItem(value: value, child: Text(value.value)),
              ],
              onChanged: widget.lockCurrency
                  ? null
                  : (value) => setState(() => currency = value!),
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
                _BrokerageAccountDraft(name.text.trim(), currency),
              );
            }
          },
          child: Text(l.createInvestmentAccountAction),
        ),
      ],
    );
  }
}

class _TradeDialog extends StatefulWidget {
  const _TradeDialog({
    required this.sell,
    required this.pockets,
    this.initialUnitPrice,
  });
  final bool sell;
  final List<_NamedPocket> pockets;
  final Decimal? initialUnitPrice;
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
    price.text = widget.initialUnitPrice?.toString() ?? '';
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
    investment = _compatibleInvestment.first;
  }

  List<_NamedPocket> get _compatibleInvestment => widget.investment
      .where((item) => item.pocket.currency == regular.pocket.currency)
      .toList();

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
              onChanged: (v) => setState(() {
                regular = v!;
                investment = _compatibleInvestment.first;
              }),
            ),
            DropdownButtonFormField(
              key: ValueKey(regular.pocket.id),
              initialValue: investment,
              items: [
                for (final p in _compatibleInvestment)
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
) => _allInvestmentPockets(
  finance,
).where((item) => item.pocket.currency == currency).toList();

List<_NamedPocket> _allInvestmentPockets(LocalFinanceSnapshot finance) => [
  for (final aggregate in finance.accounts)
    if (aggregate.account.type == AccountType.investment)
      for (final pocket in aggregate.pockets)
        _NamedPocket(
          '${aggregate.account.name} · ${pocket.currency.value}',
          LedgerPocket(
            id: pocket.id,
            currency: pocket.currency,
            nature: aggregate.account.nature,
          ),
        ),
];
List<_NamedPocket> _allRegularPockets(LocalFinanceSnapshot finance) => [
  for (final aggregate in finance.accounts)
    if (aggregate.account.type != AccountType.investment &&
        aggregate.account.nature == AccountNature.asset)
      for (final pocket in aggregate.pockets)
        _NamedPocket(
          '${aggregate.account.name} · ${pocket.currency.value}',
          LedgerPocket(
            id: pocket.id,
            currency: pocket.currency,
            nature: aggregate.account.nature,
          ),
        ),
];

List<CurrencyCode> _availableCurrencies(LocalFinanceSnapshot finance) {
  final byValue = <String, CurrencyCode>{
    finance.vault!.baseCurrency.value: finance.vault!.baseCurrency,
    CurrencyCode.brl.value: CurrencyCode.brl,
    CurrencyCode.usd.value: CurrencyCode.usd,
  };
  for (final aggregate in finance.accounts) {
    for (final pocket in aggregate.pockets) {
      byValue[pocket.currency.value] = pocket.currency;
    }
  }
  final values = byValue.values.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return values;
}

final class _NamedPocket {
  const _NamedPocket(this.name, this.pocket);
  final String name;
  final LedgerPocket pocket;
}

final class _InstrumentDraft {
  const _InstrumentDraft({
    required this.name,
    required this.symbol,
    required this.exchange,
    required this.assetClass,
    required this.currency,
    required this.quantity,
    required this.price,
    required this.fees,
    required this.taxes,
    required this.date,
    this.candidate,
    this.preview,
    this.initialMode,
    this.initialPocket,
  });
  final String name, symbol, exchange;
  final InvestmentAssetClass assetClass;
  final CurrencyCode currency;
  final MarketInstrumentCandidate? candidate;
  final MarketQuotePreview? preview;
  final InitialPositionMode? initialMode;
  final LedgerPocket? initialPocket;
  final String quantity, price, fees, taxes;
  final LocalDate date;
}

final class _MarketLinkDraft {
  const _MarketLinkDraft(this.candidate, this.preview);
  final MarketInstrumentCandidate candidate;
  final MarketQuotePreview? preview;
}

final class _BrokerageAccountDraft {
  const _BrokerageAccountDraft(this.name, this.currency);
  final String name;
  final CurrencyCode currency;
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
