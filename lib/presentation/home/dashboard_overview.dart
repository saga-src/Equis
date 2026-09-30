import 'dart:math' as math;

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
import '../../l10n/app_localizations.dart';
import '../formatting/taxonomy_labels.dart';
import '../budgets/budget_controller.dart';
import '../goals/goal_controller.dart';
import '../wealth/wealth_controller.dart';
import '../investments/investment_controller.dart';

class DashboardOverview extends ConsumerWidget {
  const DashboardOverview({
    required this.finance,
    this.reportOverride,
    this.wealthStateOverride,
    super.key,
  });

  final LocalFinanceSnapshot finance;
  final DashboardSnapshot? reportOverride;
  final WealthState? wealthStateOverride;

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
    final investments = ref.watch(investmentControllerProvider);
    final report = reportOverride ?? state.snapshot;
    if (report == null) {
      if (state.error != null) {
        return EquisGlassCard(
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
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _ResponsivePair(
          first: _SpendingReport(report: report, finance: finance),
          second: _CashFlowReport(report: report),
          matchHeight: false,
        ),
        const SizedBox(height: 16),
        _AccountBalances(report: report),
      ],
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.first,
    required this.second,
    this.matchHeight = true,
  });
  final Widget first;
  final Widget second;
  final bool matchHeight;

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
        crossAxisAlignment: matchHeight
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second),
        ],
      );
      return matchHeight ? IntrinsicHeight(child: row) : row;
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
      child: ListTile(
        leading: const Icon(Icons.account_balance_outlined),
        title: Text(
          report != null &&
                  (report.current.hasIncompleteAccounts ||
                      report.current.hasIncompleteInvestments)
              ? l10n.netWorthKnownSubtotalLabel
              : l10n.netWorthLabel,
        ),
        subtitle: report == null
            ? Text(state.error == null ? '—' : l10n.wealthLoadFailedMessage)
            : Column(
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
        trailing: const Icon(Icons.chevron_right),
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
      child: ListTile(
        leading: const Icon(Icons.show_chart),
        title: Text(
          report?.isKnownSubtotal == true
              ? l10n.fixedIncomeKnownSubtotalLabel
              : l10n.portfolioValueLabel,
        ),
        subtitle: report == null
            ? Text(state.error == null ? '—' : l10n.investmentLoadFailedMessage)
            : Column(
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
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/investments'),
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
        Text(
          l10n.availableMoneyTitle,
          style: Theme.of(context).textTheme.titleMedium,
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
    final values = [report.incomeMinor, report.expenseMinor];
    final maxValue = values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return EquisGlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.thisMonthTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Value(
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
                    '${_money(context, report.reportingCurrency, report.expenseMinor)}.',
                child: BarChart(
                  BarChartData(
                    maxY: _chart(maxValue) * 1.2,
                    minY: 0,
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
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt() == 0
                                ? l10n.incomeReportLabel
                                : l10n.expensesReportLabel,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: _chart(report.incomeMinor),
                            color: Theme.of(context).colorScheme.primary,
                            width: 24,
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: _chart(report.expenseMinor),
                            color: Theme.of(context).colorScheme.error,
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
              budgets.items.isEmpty
                  ? l10n.activeBudgetsCount(0)
                  : '${l10n.activeBudgetsCount(budgets.items.length)} · '
                        '${l10n.budgetUsagePercent((budgets.items.first.usageBps / 100).round())}',
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
  const _SpendingReport({required this.report, required this.finance});
  final DashboardSnapshot report;
  final LocalFinanceSnapshot finance;
  @override
  ConsumerState<_SpendingReport> createState() => _SpendingReportState();
}

class _SpendingReportState extends ConsumerState<_SpendingReport> {
  bool _tags = false;

  String _tagName(BuildContext context, TagSpending value) {
    if (value.tagId == null) return AppLocalizations.of(context).withoutTagsLabel;
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
        toDate: report.cashFlow.isEmpty
            ? report.periodEnd
            : report.cashFlow.last.date,
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
    required double cellWidth,
    required double maxDiameter,
    required int maximum,
  }) {
    final label = _tagName(context, value);
    final amount = _money(
      context,
      widget.report.reportingCurrency,
      value.amountMinor,
    );
    // Circle area is proportional to the tag's own amount, not a share of expenses.
    final diameter = maxDiameter * math.sqrt(value.amountMinor / maximum);
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: '$label, $amount',
      onTap: () => _openTagHistory(context, value),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _openTagHistory(context, value),
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: cellWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: maxDiameter,
                  height: maxDiameter,
                  child: Center(
                    child: SizedBox(
                      key: Key(
                        'tag-bubble-${value.tagId?.value ?? 'without-tags'}',
                      ),
                      width: diameter,
                      height: diameter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.28),
                          border: Border.all(color: color),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Text(
                  amount,
                  style: EquisTypography.numeric,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final report = widget.report;
    final values = report.spendingByTag;
    final positives = values.where((value) => value.amountMinor > 0).toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final featured = positives.take(6).toList();
    final otherValues = [
      ...positives.skip(6),
      ...values.where((value) => value.amountMinor == 0),
    ];
    final negatives = values.where((value) => value.amountMinor < 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l.categoriesTitle)),
            ButtonSegment(value: true, label: Text(l.tagsTitle)),
          ],
          selected: {_tags},
          onSelectionChanged: (value) => setState(() => _tags = value.single),
        ),
        const SizedBox(height: 8),
        if (!_tags)
          _CategoryReport(report: report, finance: widget.finance)
        else
          EquisGlassCard(
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
                  if (featured.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final columns = width < 260 ? 1 : width < 480 ? 2 : 3;
                        const spacing = 8.0;
                        final cellWidth =
                            (width - spacing * (columns - 1)) / columns;
                        final maxDiameter = math.min(128.0, cellWidth - 12);
                        return Wrap(
                          key: const Key('tag-bubble-grid'),
                          spacing: spacing,
                          runSpacing: 16,
                          children: [
                            for (final value in featured)
                              _tagBubble(
                                context,
                                value,
                                cellWidth: cellWidth,
                                maxDiameter: maxDiameter,
                                maximum: featured.first.amountMinor,
                              ),
                          ],
                        );
                      },
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
                  if (negatives.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l.negativeTagValuesTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final value in negatives)
                      _tagListTile(context, value),
                  ],
                ],
              ),
            ),
          ),
      ],
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
              SizedBox(
                height: 220,
                child: Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
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
  toDate: report.cashFlow.isEmpty
      ? report.periodEnd
      : report.cashFlow.last.date,
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
  const _CashFlowReport({required this.report});
  final DashboardSnapshot report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    var runningIncome = 0;
    var runningExpense = 0;
    final income = <FlSpot>[];
    final expense = <FlSpot>[];
    for (var index = 0; index < report.cashFlow.length; index++) {
      runningIncome += report.cashFlow[index].incomeMinor;
      runningExpense += report.cashFlow[index].expenseMinor;
      income.add(FlSpot(index.toDouble(), _chart(runningIncome)));
      expense.add(FlSpot(index.toDouble(), _chart(runningExpense)));
    }
    return EquisGlassCard(
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
            SizedBox(
              height: 220,
              child: report.cashFlow.isEmpty
                  ? Center(child: Text(l10n.noSpendingDataMessage))
                  : AccessibleChart(
                      label: l10n.cashFlowChartTitle,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (report.cashFlow.length - 1).toDouble(),
                          minY: 0,
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
                                interval: 7,
                                getTitlesWidget: (value, meta) => Text(
                                  '${value.toInt() + 1}',
                                  style: Theme.of(context).textTheme.labelSmall,
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
  const _Value({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(
        value,
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
