import '../../domain/ledger/transaction_search.dart';
import '../../domain/ledger/ledger_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';
import '../accessibility/accessible_chart.dart';
import '../shared/equis_glass.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/shared/local_date.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/taxonomy_labels.dart';
import '../budgets/budget_controller.dart';
import '../goals/goal_controller.dart';
import '../wealth/wealth_controller.dart';
import '../investments/investment_controller.dart';
import 'tag_bubble_layout.dart';

class DashboardOverview extends ConsumerWidget {
  const DashboardOverview({
    required this.finance,
    this.reportOverride,
    this.wealthStateOverride,
    this.investmentStateOverride,
    super.key,
  });

  final LocalFinanceSnapshot finance;
  final DashboardSnapshot? reportOverride;
  final WealthState? wealthStateOverride;
  final InvestmentState? investmentStateOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dashboardControllerProvider);
    final budgets = ref.watch(budgetControllerProvider);
    final goals = ref.watch(goalControllerProvider);
    final WealthState wealth =
        wealthStateOverride ??
        ref.watch(wealthControllerProvider) ??
        const WealthState();
    final InvestmentState investments =
        investmentStateOverride ?? ref.watch(investmentControllerProvider);
    final report = reportOverride ?? state.snapshot;
    if (report == null) {
      if (state.error != null) {
        return Column(
          children: [
            const _DashboardControls(),
            EquisGlassCard(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(l10n.localVaultErrorMessage),
                trailing: IconButton(
                  tooltip: l10n.refreshAction,
                  onPressed: () =>
                      ref.read(dashboardControllerProvider.notifier).reload(),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ],
        );
      }
      return const Column(
        children: [
          _DashboardControls(),
          SizedBox(height: 16),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.loading) const LinearProgressIndicator(),
        _AvailableMoney(report: report),
        if (report.missingRates.isNotEmpty || report.usesEstimatedRates) ...[
          const SizedBox(height: 8),
          EquisGlassCard(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(
                report.missingRates.isNotEmpty
                    ? l10n.reportingIncompleteMessage
                    : l10n.reportingEstimatedMessage,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _ResponsivePair(
          first: _ThisMonth(report: report),
          second: _Planning(report: report, budgets: budgets, goals: goals),
        ),
        const SizedBox(height: 16),
        Text(l10n.dashboardCurrentPositionLabel),
        _ResponsivePair(
          first: _NetWorthSummary(state: wealth),
          second: _InvestmentSummary(state: investments),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.reportsSectionTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _SpendingReport(
          report: report,
          finance: finance,
          mode: state.selection.mode,
        ),
        const SizedBox(height: 16),
        _AccountBalances(report: report),
      ],
    );
  }
}

class _DashboardControls extends ConsumerWidget {
  const _DashboardControls();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dashboardControllerProvider);
    final controller = ref.read(dashboardControllerProvider.notifier);
    final theme = Theme.of(context);
    final controlStyle = theme.textTheme.bodySmall;
    String periodLabel(DashboardRangePreset preset) => switch (preset) {
      DashboardRangePreset.thisMonth => l10n.thisMonthTitle,
      DashboardRangePreset.lastMonth => l10n.dashboardLastMonthLabel,
      DashboardRangePreset.lastThreeMonths =>
        l10n.dashboardLastThreeMonthsLabel,
      DashboardRangePreset.thisYear => l10n.dashboardThisYearLabel,
      DashboardRangePreset.custom => l10n.dashboardCustomRangeLabel,
    };
    Widget menuLabel(String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: controlStyle),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            PopupMenuButton<DashboardRangePreset>(
              key: ValueKey('dashboard-range-${state.selection.preset.name}'),
              initialValue: state.selection.preset,
              tooltip: l10n.dashboardPeriodTitle,
              child: menuLabel(periodLabel(state.selection.preset)),
              itemBuilder: (context) => [
                for (final preset in DashboardRangePreset.values)
                  PopupMenuItem(
                    value: preset,
                    child: Text(
                      periodLabel(preset),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onSelected: (preset) async {
                DashboardDateRange? custom;
                if (preset == DashboardRangePreset.custom) {
                  final today = controller.today;
                  final selected = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: today.toUtcDate(),
                    initialDateRange: DateTimeRange(
                      start: state.selection.resolve(today).from.toUtcDate(),
                      end: state.selection.resolve(today).through.toUtcDate(),
                    ),
                  );
                  if (selected == null) return;
                  custom = DashboardDateRange(
                    from: LocalDate(
                      selected.start.year,
                      selected.start.month,
                      selected.start.day,
                    ),
                    through: LocalDate(
                      selected.end.year,
                      selected.end.month,
                      selected.end.day,
                    ),
                  );
                }
                await controller.select(
                  DashboardSelection(
                    preset: preset,
                    customRange: custom,
                    mode: state.selection.mode,
                  ),
                );
              },
            ),
            PopupMenuButton<CashFlowMode>(
              key: ValueKey('dashboard-mode-${state.selection.mode.name}'),
              initialValue: state.selection.mode,
              tooltip: l10n.dashboardFlowModeLabel,
              child: menuLabel(
                state.selection.mode == CashFlowMode.daily
                    ? l10n.dashboardDailyLabel
                    : l10n.dashboardCumulativeLabel,
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: CashFlowMode.daily,
                  child: Text(
                    l10n.dashboardDailyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuItem(
                  value: CashFlowMode.cumulative,
                  child: Text(
                    l10n.dashboardCumulativeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onSelected: (mode) =>
                  controller.select(state.selection.withMode(mode)),
            ),
          ],
        ),
        if (state.invalidSelection) Text(l10n.dashboardInvalidSelectionMessage),
        if (state.preferenceError != null)
          Text(l10n.experiencePreferenceFailedMessage),
      ],
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 16), second],
        );
      }
      final row = Row(
        key: const Key('dashboard-wide-pair'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
      return IntrinsicHeight(child: row);
    },
  );
}

class _NetWorthSummary extends StatelessWidget {
  const _NetWorthSummary({required this.state});
  final WealthState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final report = state.report;
    return EquisGlassCard(
      child: _PositionSummaryTile(
        leading: const Icon(
          Icons.account_balance_outlined,
          key: Key('net-worth-summary-icon'),
        ),
        title: Text(
          report != null &&
                  (report.current.hasIncompleteAccounts ||
                      report.current.hasIncompleteInvestments)
              ? l10n.netWorthKnownSubtotalLabel
              : l10n.netWorthLabel,
          key: const Key('net-worth-summary-title'),
        ),
        subtitle: report == null
            ? Text(state.error == null ? '—' : l10n.wealthLoadFailedMessage)
            : Column(
                key: const Key('net-worth-summary-values'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _money(
                      context,
                      report.currency,
                      report.current.netWorthMinor,
                    ),
                    style: EquisTypography.numeric,
                  ),
                  if (report.current.hasIncompleteAccounts)
                    Text(l10n.accountSyncIncompleteMessage),
                ],
              ),
        onTap: () => context.go('/wealth'),
      ),
    );
  }
}

class _InvestmentSummary extends StatelessWidget {
  const _InvestmentSummary({required this.state});
  final InvestmentState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final report = state.report;
    return EquisGlassCard(
      child: _PositionSummaryTile(
        leading: const Icon(
          Icons.show_chart,
          key: Key('portfolio-summary-icon'),
        ),
        title: Text(
          report?.isKnownSubtotal == true
              ? l10n.fixedIncomeKnownSubtotalLabel
              : l10n.portfolioValueLabel,
          key: const Key('portfolio-summary-title'),
        ),
        subtitle: report == null
            ? Text(state.error == null ? '—' : l10n.investmentLoadFailedMessage)
            : Column(
                key: const Key('portfolio-summary-values'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _money(context, report.currency, report.marketValueMinor),
                    style: EquisTypography.numeric,
                  ),
                  if (report.hasIncompleteAccountSync)
                    Text(l10n.accountSyncIncompleteMessage),
                ],
              ),
        onTap: () => context.go('/investments'),
      ),
    );
  }
}

class _PositionSummaryTile extends StatelessWidget {
  const _PositionSummaryTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final Widget title;
  final Widget subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconTheme.merge(
                  data: IconThemeData(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  child: leading,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: theme.textTheme.bodyLarge!,
                        child: title,
                      ),
                      DefaultTextStyle(
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        child: subtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailableMoney extends StatelessWidget {
  const _AvailableMoney({required this.report});
  final DashboardSnapshot report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = Column(
              key: const Key('available-money-heading'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dashboardCurrentPositionLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  l10n.availableMoneyTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            );
            if (constraints.maxWidth >= 650) {
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  const _DashboardControls(),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 12),
                const _DashboardControls(),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        EquisGlassCard(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _money(
                          context,
                          report.reportingCurrency,
                          report.availableMoneyMinor,
                        ),
                        style: EquisTypography.numeric.copyWith(fontSize: 30),
                      ),
                      if (report.hasIncompleteAccounts)
                        Text(
                          l10n.accountSyncIncompleteMessage,
                          key: const Key('available-money-incomplete'),
                        ),
                    ],
                  ),
                ),
                if (report.isComplete)
                  Icon(
                    Icons.verified_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThisMonth extends StatelessWidget {
  const _ThisMonth({required this.report});
  final DashboardSnapshot report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final values = [
      report.incomeMinor,
      report.expenseMinor,
      report.netCashFlowMinor,
    ];
    final maxValue = values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    final minValue = values.fold<int>(
      0,
      (min, value) => value < min ? value : min,
    );
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.error,
      Theme.of(context).colorScheme.onSurface,
    ];
    return EquisGlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              key: const Key('dashboard-period-summary'),
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.dashboardPeriodTitle,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  EquisFormatters.dateRange(
                    context,
                    report.periodStart,
                    report.periodEnd,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Value(
                    key: const Key('income-summary-column'),
                    label: l10n.incomeReportLabel,
                    value: _money(
                      context,
                      report.reportingCurrency,
                      report.incomeMinor,
                    ),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: _Value(
                    key: const Key('expenses-summary-column'),
                    label: l10n.expensesReportLabel,
                    value: _money(
                      context,
                      report.reportingCurrency,
                      report.expenseMinor,
                    ),
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                Expanded(
                  child: _Value(
                    key: const Key('net-cash-flow-summary-column'),
                    label: l10n.netCashFlowLabel,
                    value: _money(
                      context,
                      report.reportingCurrency,
                      report.netCashFlowMinor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 130,
              child: AccessibleChart(
                label:
                    '${l10n.incomeReportLabel}: '
                    '${_money(context, report.reportingCurrency, report.incomeMinor)}. '
                    '${l10n.expensesReportLabel}: '
                    '${_money(context, report.reportingCurrency, report.expenseMinor)}. '
                    '${l10n.netCashFlowLabel}: '
                    '${_money(context, report.reportingCurrency, report.netCashFlowMinor)}.',
                child: BarChart(
                  chartRendererKey: const Key('dashboard-summary-bars'),
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) =>
                            Theme.of(context).cardTheme.color ??
                            Theme.of(context).colorScheme.surface,
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                      ),
                    ),
                    maxY: _chart(maxValue) * 1.2,
                    minY: _chart(minValue) * 1.2,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    barGroups: [
                      for (var index = 0; index < values.length; index++)
                        BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: _chart(values[index]),
                              color: colors[index],
                              width: 24,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Planning extends StatelessWidget {
  const _Planning({
    required this.report,
    required this.budgets,
    required this.goals,
  });
  final DashboardSnapshot report;
  final BudgetState budgets;
  final GoalState goals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EquisGlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.pie_chart_outline),
            title: Text(l10n.budgetDashboardTitle),
            subtitle: Text(
              budgets.currentItems.isEmpty
                  ? l10n.activeBudgetsCount(0)
                  : '${l10n.activeBudgetsCount(budgets.currentItems.length)} · '
                        '${l10n.budgetUsagePercent((budgets.currentItems.first.usageBps / 100).round())}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/budgets'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(l10n.goalsTabLabel),
            subtitle: Text(l10n.activeGoalsCount(goals.items.length)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/goals'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(l10n.upcomingDashboardTitle),
            subtitle: Text(l10n.upcomingNext30DaysLabel),
            trailing: Text(
              '${report.upcomingCount}',
              style: EquisTypography.numeric.copyWith(fontSize: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendingReport extends ConsumerStatefulWidget {
  const _SpendingReport({
    required this.report,
    required this.finance,
    required this.mode,
  });
  final DashboardSnapshot report;
  final LocalFinanceSnapshot finance;
  final CashFlowMode mode;
  @override
  ConsumerState<_SpendingReport> createState() => _SpendingReportState();
}

class _SpendingReportState extends ConsumerState<_SpendingReport> {
  bool _tags = false;

  String _tagName(BuildContext context, TagSpending value) {
    if (value.tagId == null) {
      return AppLocalizations.of(context).withoutTagsLabel;
    }
    return widget.finance.tags
            .where((tag) => tag.id == value.tagId)
            .map((tag) => tagLabel(context, tag))
            .firstOrNull ??
        value.tagId!.value;
  }

  void _openTagHistory(BuildContext context, TagSpending value) {
    final vault = widget.finance.vault;
    if (vault == null) return;
    final report = widget.report;
    context.go(
      '/history',
      extra: TransactionSearchFilter(
        vaultId: vault.id,
        tagId: value.tagId,
        withoutTags: value.tagId == null,
        fromDate: report.periodStart,
        toDate: report.periodEnd,
        reportingExpensesOnly: true,
      ),
    );
  }

  Widget _tagListTile(BuildContext context, TagSpending value) {
    final amount = _money(
      context,
      widget.report.reportingCurrency,
      value.amountMinor,
    );
    return ListTile(
      key: Key('tag-value-${value.tagId?.value ?? 'without-tags'}'),
      contentPadding: EdgeInsets.zero,
      title: Text(_tagName(context, value)),
      subtitle: Text(amount, style: EquisTypography.numeric),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openTagHistory(context, value),
    );
  }

  Widget _tagBubble(
    BuildContext context,
    TagSpending value, {
    required TagBubblePlacement placement,
  }) {
    final label = _tagName(context, value);
    final amount = _money(
      context,
      widget.report.reportingCurrency,
      value.amountMinor,
    );
    return _TagBubble(
      key: ValueKey(value.tagId?.value ?? 'without-tags'),
      id: value.tagId?.value ?? 'without-tags',
      label: label,
      amount: amount,
      placement: placement,
      onTap: () => _openTagHistory(context, value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final report = widget.report;
    final values = report.spendingByTag;
    final positives = values.where((value) => value.amountMinor > 0).toList()
      ..sort((a, b) {
        final amountOrder = b.amountMinor.compareTo(a.amountMinor);
        return amountOrder != 0
            ? amountOrder
            : (a.tagId?.value ?? '').compareTo(b.tagId?.value ?? '');
      });
    final featured = positives.take(6).toList();
    final negatives = values.where((value) => value.amountMinor < 0);
    final toggle = SegmentedButton<bool>(
      key: const Key('dashboard-spending-toggle'),
      segments: [
        ButtonSegment(value: false, label: Text(l.categoriesTitle)),
        ButtonSegment(value: true, label: Text(l.tagsTitle)),
      ],
      selected: {_tags},
      onSelectionChanged: (value) => setState(() => _tags = value.single),
    );
    final spending = !_tags
        ? _CategoryReport(report: report, finance: widget.finance)
        : EquisGlassCard(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.spendingByTagTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l.tagOverlapMessage),
                  if (values.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l.noSpendingDataMessage),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = TagBubbleLayout.pack(
                        featured.map((value) => value.amountMinor).toList(),
                        width: constraints.maxWidth,
                      );
                      final otherValues = [
                        for (var index = 0; index < featured.length; index++)
                          if (layout.bubbles.isEmpty ||
                              !_TagBubble.hasLabel(
                                context,
                                layout.bubbles[index].radius * 2,
                              ))
                            featured[index],
                        ...positives.skip(6),
                        ...values.where((value) => value.amountMinor == 0),
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (layout.bubbles.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              key: const Key('tag-bubble-cluster'),
                              width: layout.size.width,
                              height: layout.size.height,
                              child: Stack(
                                children: [
                                  for (
                                    var index = 0;
                                    index < featured.length;
                                    index++
                                  )
                                    Positioned(
                                      key: ValueKey(
                                        'tag-placement-${featured[index].tagId?.value ?? 'without-tags'}',
                                      ),
                                      left:
                                          layout.bubbles[index].center.dx -
                                          layout.bubbles[index].hitRadius,
                                      top:
                                          layout.bubbles[index].center.dy -
                                          layout.bubbles[index].hitRadius,
                                      child: _tagBubble(
                                        context,
                                        featured[index],
                                        placement: layout.bubbles[index],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (otherValues.isNotEmpty)
                            ExpansionTile(
                              key: const Key('tag-other-values-expansion'),
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: EdgeInsets.zero,
                              title: Text(l.otherTagValuesTitle),
                              children: [
                                for (final value in otherValues)
                                  _tagListTile(context, value),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                  if (negatives.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l.negativeTagValuesTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final value in negatives) _tagListTile(context, value),
                  ],
                ],
              ),
            ),
          );
    final cashFlow = _CashFlowReport(report: report, mode: widget.mode);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toggle,
              const SizedBox(height: 8),
              spending,
              const SizedBox(height: 16),
              cashFlow,
            ],
          );
        }
        return Table(
          key: const Key('dashboard-wide-pair'),
          columnWidths: const {
            0: FlexColumnWidth(),
            1: FixedColumnWidth(16),
            2: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            TableRow(
              children: [
                toggle,
                const SizedBox.shrink(),
                const SizedBox.shrink(),
              ],
            ),
            const TableRow(
              children: [
                SizedBox(height: 8),
                SizedBox(height: 8),
                SizedBox(height: 8),
              ],
            ),
            TableRow(
              children: [
                ConstrainedBox(
                  key: const Key('dashboard-spending-card'),
                  constraints: BoxConstraints(
                    minHeight:
                        360 + MediaQuery.textScalerOf(context).scale(48) - 48,
                  ),
                  child: spending,
                ),
                const SizedBox.shrink(),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.fill,
                  child: cashFlow,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TagBubble extends StatefulWidget {
  const _TagBubble({
    required this.id,
    required this.label,
    required this.amount,
    required this.placement,
    required this.onTap,
    super.key,
  });

  final String id;
  final String label;
  final String amount;
  final TagBubblePlacement placement;
  final VoidCallback onTap;

  static bool hasLabel(BuildContext context, double diameter) =>
      diameter >= 80 && MediaQuery.textScalerOf(context).scale(12) <= 16.8;

  @override
  State<_TagBubble> createState() => _TagBubbleState();
}

class _TagBubbleState extends State<_TagBubble> {
  final _tooltipKey = GlobalKey<TooltipState>();
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _focusChanged(bool focused) {
    setState(() => _focused = focused);
    Tooltip.dismissAllToolTips();
    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.hasFocus) {
          _tooltipKey.currentState?.ensureTooltipVisible();
        }
      });
    }
  }

  void _activate() {
    Tooltip.dismissAllToolTips();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.placement.radius * 2;
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      key: Key('tag-bubble-target-${widget.id}'),
      width: widget.placement.hitRadius * 2,
      height: widget.placement.hitRadius * 2,
      child: ClipOval(
        child: Tooltip(
          key: _tooltipKey,
          message: '${widget.label}\n${widget.amount}',
          excludeFromSemantics: true,
          waitDuration: const Duration(milliseconds: 200),
          exitDuration: const Duration(milliseconds: 100),
          triggerMode: TooltipTriggerMode.longPress,
          child: Semantics(
            button: true,
            label: '${widget.label}, ${widget.amount}',
            onTap: _activate,
            child: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                shape: CircleBorder(
                  side: _focused
                      ? BorderSide(color: color, width: 2)
                      : BorderSide.none,
                ),
                child: InkWell(
                  focusNode: _focusNode,
                  onFocusChange: _focusChanged,
                  customBorder: const CircleBorder(),
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: _activate,
                  child: Center(
                    child: SizedBox(
                      key: Key('tag-bubble-${widget.id}'),
                      width: diameter,
                      height: diameter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: .28),
                          border: Border.all(color: color),
                        ),
                        child: Center(
                          child: _TagBubble.hasLabel(context, diameter)
                              ? SizedBox(
                                  width: diameter * .7,
                                  height: diameter * .7,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.label,
                                          maxLines: diameter >= 120 ? 2 : 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                      Text(
                                        widget.amount,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: EquisTypography.numeric.copyWith(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryReport extends StatefulWidget {
  const _CategoryReport({required this.report, required this.finance});
  final DashboardSnapshot report;
  final LocalFinanceSnapshot finance;

  @override
  State<_CategoryReport> createState() => _CategoryReportState();
}

class _CategoryReportState extends State<_CategoryReport> {
  var classification = ReportClassification.expense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final report = widget.report;
    final source = classification == ReportClassification.expense
        ? report.spendingByCategory
        : report.incomeByCategory;
    final values = _categorySlices(source);
    final classificationLabel = classification == ReportClassification.expense
        ? l10n.expensesReportLabel
        : l10n.incomeReportLabel;
    final colors = [
      Theme.of(context).colorScheme.primary,
      const Color(0xFF38BDF8),
      const Color(0xFFF59E0B),
      const Color(0xFFA78BFA),
      const Color(0xFFF472B6),
      const Color(0xFF94A3B8),
    ];
    return EquisGlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.categoryBreakdownTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ReportClassification>(
              key: const Key('category-classification-selector'),
              segments: [
                ButtonSegment(
                  value: ReportClassification.expense,
                  label: Text(l10n.expensesReportLabel),
                ),
                ButtonSegment(
                  value: ReportClassification.income,
                  label: Text(l10n.incomeReportLabel),
                ),
              ],
              selected: {classification},
              onSelectionChanged: (value) =>
                  setState(() => classification = value.single),
            ),
            const SizedBox(height: 12),
            if (values.isEmpty)
              SizedBox(
                height: 220,
                child: Center(child: Text(l10n.noSpendingDataMessage)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 220),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 220,
                        child: AccessibleChart(
                          label:
                              '${l10n.categoryBreakdownTitle}: $classificationLabel',
                          child: PieChart(
                            PieChartData(
                              centerSpaceRadius: 42,
                              sectionsSpace: 2,
                              sections: [
                                for (
                                  var index = 0;
                                  index < values.length;
                                  index++
                                )
                                  PieChartSectionData(
                                    value: _chart(values[index].amountMinor),
                                    color: colors[index],
                                    showTitle: false,
                                    radius: 42,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var index = 0; index < values.length; index++)
                            Semantics(
                              button: values[index].categoryId != null,
                              child: InkWell(
                                onTap: values[index].categoryId == null
                                    ? null
                                    : () => _openCategory(
                                        context,
                                        values[index].categoryId!,
                                      ),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: colors[index],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          values[index].categoryId == null
                                              ? l10n.otherCategoriesLabel
                                              : _categoryName(
                                                  context,
                                                  widget.finance,
                                                  values[index].categoryId!,
                                                ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        _money(
                                          context,
                                          report.reportingCurrency,
                                          values[index].amountMinor,
                                        ),
                                        style: EquisTypography.numeric,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openCategory(BuildContext context, EntityId categoryId) {
    final vault = widget.finance.vault;
    if (vault == null) return;
    final report = widget.report;
    context.go(
      '/history',
      extra: dashboardCategoryHistoryFilter(
        vaultId: vault.id,
        categoryId: categoryId,
        report: report,
        classification: classification,
      ),
    );
  }
}

TransactionSearchFilter dashboardCategoryHistoryFilter({
  required EntityId vaultId,
  required EntityId categoryId,
  required DashboardSnapshot report,
  required ReportClassification classification,
}) => TransactionSearchFilter(
  vaultId: vaultId,
  categoryId: categoryId,
  fromDate: report.periodStart,
  toDate: report.periodEnd,
  reportingExpensesOnly: classification == ReportClassification.expense,
  types: classification == ReportClassification.income
      ? const {
          LedgerTransactionType.income,
          LedgerTransactionType.dividend,
          LedgerTransactionType.interest,
        }
      : const {},
);

List<_CategorySlice> _categorySlices(List<CategorySpending> values) {
  final top = values
      .take(5)
      .map(
        (value) => _CategorySlice(
          categoryId: value.categoryId,
          amountMinor: value.amountMinor,
        ),
      );
  if (values.length <= 5) return top.toList();
  return [
    ...top,
    _CategorySlice(
      amountMinor: values
          .skip(5)
          .fold(0, (sum, value) => sum + value.amountMinor),
    ),
  ];
}

final class _CategorySlice {
  const _CategorySlice({this.categoryId, required this.amountMinor});
  final EntityId? categoryId;
  final int amountMinor;
}

class _CashFlowReport extends StatelessWidget {
  const _CashFlowReport({required this.report, required this.mode});
  final DashboardSnapshot report;
  final CashFlowMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final series = cashFlowSeries(report.cashFlow, mode);
    final income = <FlSpot>[];
    final expense = <FlSpot>[];
    for (var index = 0; index < report.cashFlow.length; index++) {
      income.add(FlSpot(index.toDouble(), _chart(series[index].incomeMinor)));
      expense.add(FlSpot(index.toDouble(), _chart(series[index].expenseMinor)));
    }
    return LayoutBuilder(
      builder: (context, constraints) => EquisGlassCard(
        key: const Key('cash-flow-report-card'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cashFlowChartTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                mode == CashFlowMode.daily
                    ? l10n.dashboardDailyLabel
                    : l10n.dashboardCumulativeLabel,
              ),
              SizedBox(
                height: 220,
                child: report.cashFlow.isEmpty
                    ? Center(child: Text(l10n.noSpendingDataMessage))
                    : AccessibleChart(
                        label: l10n.cashFlowChartTitle,
                        child: LineChart(
                          chartRendererKey: const Key('cash-flow-plot'),
                          LineChartData(
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) =>
                                    Theme.of(context).cardTheme.color ??
                                    Theme.of(context).colorScheme.surface,
                                tooltipBorder: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                                tooltipPadding: const EdgeInsets.all(8),
                                maxContentWidth: (constraints.maxWidth - 56)
                                    .clamp(40.0, 180.0)
                                    .toDouble(),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                              ),
                            ),
                            minX: 0,
                            maxX: (report.cashFlow.length - 1)
                                .clamp(1, 1 << 30)
                                .toDouble(),
                            minY: [...income, ...expense].fold<double>(
                              0,
                              (value, point) =>
                                  point.y < value ? point.y : value,
                            ),
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: Theme.of(context).dividerColor,
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize:
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(18) +
                                      8,
                                  interval: (report.cashFlow.length / 5)
                                      .ceil()
                                      .clamp(1, 1 << 30)
                                      .toDouble(),
                                  getTitlesWidget: (value, meta) =>
                                      value.toInt() < 0 ||
                                          value.toInt() >= series.length
                                      ? const SizedBox.shrink()
                                      : SideTitleWidget(
                                          meta: meta,
                                          space: 4,
                                          fitInside:
                                              SideTitleFitInsideData.fromTitleMeta(
                                                meta,
                                                enabled: true,
                                              ),
                                          child: Text(
                                            EquisFormatters.date(
                                              context,
                                              series[value.toInt()].date,
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: income,
                                color: Theme.of(context).colorScheme.primary,
                                barWidth: 3,
                                dotData: const FlDotData(show: false),
                              ),
                              LineChartBarData(
                                spots: expense,
                                color: Theme.of(context).colorScheme.error,
                                barWidth: 3,
                                dotData: const FlDotData(show: false),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountBalances extends StatelessWidget {
  const _AccountBalances({required this.report});
  final DashboardSnapshot report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EquisGlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                l10n.accountBalancesTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final balance in report.accountBalances)
              ListTile(
                leading: Icon(
                  balance.nature == AccountNature.asset
                      ? Icons.account_balance_wallet_outlined
                      : Icons.credit_card_outlined,
                ),
                title: Text(balance.accountName),
                subtitle: Text(
                  '${l10n.originalCurrencyAmountLabel}: '
                  '${_money(context, balance.currency, balance.originalMinor)}',
                ),
                trailing: balance.reportingMinor == null
                    ? const Icon(Icons.warning_amber_outlined)
                    : Text(
                        _money(
                          context,
                          report.reportingCurrency,
                          balance.reportingMinor!,
                        ),
                        style: EquisTypography.numeric,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.value,
    this.color,
    super.key,
  });
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(height: 4),
      Text(
        value,
        textAlign: TextAlign.center,
        style: EquisTypography.numeric.copyWith(color: color, fontSize: 16),
      ),
    ],
  );
}

String _categoryName(
  BuildContext context,
  LocalFinanceSnapshot finance,
  Object categoryId,
) {
  for (final category in finance.categories) {
    if (category.id == categoryId) return categoryLabel(context, category);
  }
  return categoryId.toString().substring(0, 8);
}

String _money(BuildContext context, CurrencyCode currency, int minor) =>
    EquisFormatters.moneyMinor(context, currency: currency, minor: minor);

double _chart(int minor) => minor / 100;
