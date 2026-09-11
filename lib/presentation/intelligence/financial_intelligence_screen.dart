import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';

import '../../app/providers/app_providers.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/intelligence/financial_intelligence_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/taxonomy_labels.dart';
import '../shared/equis_glass.dart';
import 'financial_intelligence_controller.dart';

class FinancialIntelligenceScreen extends ConsumerWidget {
  const FinancialIntelligenceScreen({
    this.financeOverride,
    this.stateOverride,
    super.key,
  });

  final LocalFinanceSnapshot? financeOverride;
  final FinancialIntelligenceState? stateOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final finance =
        financeOverride ??
        ref.watch(localFinanceControllerProvider).valueOrNull;
    final FinancialIntelligenceState state =
        stateOverride ?? ref.watch(financialIntelligenceControllerProvider);
    final report = state.report;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.intelligenceTitle),
        actions: [
          IconButton(
            tooltip: l10n.refreshInsightsAction,
            onPressed: state.loading
                ? null
                : () => ref
                      .read(financialIntelligenceControllerProvider.notifier)
                      .reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: finance?.vault == null
          ? Center(child: Text(l10n.setupRequiredMessage))
          : state.loading && report == null
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && report == null
          ? Center(child: Text(l10n.intelligenceLoadFailedMessage))
          : report == null
          ? Center(child: Text(l10n.noInsightsMessage))
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(financialIntelligenceControllerProvider.notifier)
                  .reload(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l10n.intelligenceSubtitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  EquisGlassCard(
                    key: const Key('local-intelligence-privacy'),
                    child: ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: Text(l10n.intelligencePrivacyMessage),
                    ),
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l10n.intelligenceLoadFailedMessage,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (!report.enabled)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.intelligenceDisabledMessage),
                    )
                  else if (report.insights.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.noInsightsMessage),
                    )
                  else
                    for (final insight in report.insights)
                      _InsightCard(
                        insight: insight,
                        currency: report.currency,
                        finance: finance!,
                      ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.insight,
    required this.currency,
    required this.finance,
  });

  final FinancialInsight insight;
  final CurrencyCode currency;
  final LocalFinanceSnapshot finance;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (insight.severity) {
      FinancialInsightSeverity.positive => const Color(0xFF059669),
      FinancialInsightSeverity.information => colors.primary,
      FinancialInsightSeverity.caution => const Color(0xFFD97706),
      FinancialInsightSeverity.critical => colors.error,
    };
    return EquisGlassCard(
      key: Key('insight-${insight.kind.name}'),
      child: ExpansionTile(
        leading: Icon(_icon(insight.kind), color: color),
        title: Text(_message(context)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context).calculationTraceTitle,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              _formula(context),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _message(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = insight.metrics;
    return switch (insight.kind) {
      FinancialInsightKind.spendingTrend => l.spendingTrendInsight(
        _signedPercent(m['delta_bps']!),
      ),
      FinancialInsightKind.expenseAnomaly => l.expenseAnomalyInsight(
        _categoryName(context, insight.sourceId),
        _money(context, currency, m['projected_minor']!),
        _signedPercent(m['delta_bps']!),
      ),
      FinancialInsightKind.budgetForecast => l.budgetForecastInsight(
        insight.label ?? '',
        _money(context, currency, m['projected_minor']!),
        _money(context, currency, m['limit_minor']!),
      ),
      FinancialInsightKind.cashFlowForecast => l.cashFlowForecastInsight(
        m['days']!,
        _money(context, currency, m['closing_minor']!),
      ),
      FinancialInsightKind.recurringCommitments =>
        l.recurringCommitmentsInsight(
          m['count']!,
          _money(context, currency, m['total_minor']!),
        ),
      FinancialInsightKind.goalContribution => l.goalContributionInsight(
        insight.label ?? '',
        _money(context, currency, m['gap_minor']!),
      ),
      FinancialInsightKind.emergencyFund => l.emergencyFundInsight(
        (m['coverage_milli_months']! / 1000).toStringAsFixed(1),
        _money(context, currency, m['average_expense_minor']!),
      ),
      FinancialInsightKind.debtOverview => l.debtOverviewInsight(
        _money(context, currency, m['debt_minor']!),
        _percent(m['debt_to_asset_bps']!),
      ),
      FinancialInsightKind.netWorthTrend => l.netWorthTrendInsight(
        _money(context, currency, m['delta_minor']!),
        _signedPercent(m['delta_bps']!),
        m['sample_months']!,
      ),
      FinancialInsightKind.investmentConcentration =>
        l.investmentConcentrationInsight(
          insight.label ?? '',
          _percent(m['allocation_bps']!),
        ),
    };
  }

  String _formula(BuildContext context) {
    final m = insight.metrics;
    String money(String key) => _money(context, currency, m[key]!);
    return switch (insight.kind) {
      FinancialInsightKind.spendingTrend =>
        '${money('current_minor')} ÷ ${m['elapsed_days']} × ${m['period_days']} = '
            '${money('projected_minor')}; ${money('projected_minor')} ÷ '
            '${money('previous_minor')} − 1 = ${_signedPercent(m['delta_bps']!)}%',
      FinancialInsightKind.expenseAnomaly =>
        '${money('current_minor')} ÷ ${m['elapsed_days']} × ${m['period_days']} = '
            '${money('projected_minor')}; ${money('projected_minor')} ÷ '
            '${money('previous_minor')} − 1 = ${_signedPercent(m['delta_bps']!)}%',
      FinancialInsightKind.budgetForecast =>
        '${money('used_minor')} ÷ ${money('limit_minor')} = '
            '${_percent(m['usage_bps']!)}%; ${money('projected_minor')}',
      FinancialInsightKind.cashFlowForecast =>
        '${money('opening_minor')} + ${m['event_count']} → ${money('closing_minor')}',
      FinancialInsightKind.recurringCommitments =>
        'Σ(${m['count']}) = ${money('total_minor')}',
      FinancialInsightKind.goalContribution =>
        '${money('required_minor')} − ${money('planned_minor')} = ${money('gap_minor')}',
      FinancialInsightKind.emergencyFund =>
        '${money('liquid_minor')} ÷ ${money('average_expense_minor')} = '
            '${(m['coverage_milli_months']! / 1000).toStringAsFixed(1)} '
            '(n=${m['sample_months']})',
      FinancialInsightKind.debtOverview =>
        '${money('debt_minor')} ÷ ${money('asset_minor')} = '
            '${_percent(m['debt_to_asset_bps']!)}%',
      FinancialInsightKind.netWorthTrend =>
        '${money('current_minor')} − ${money('starting_minor')} = '
            '${money('delta_minor')} (n=${m['sample_months']})',
      FinancialInsightKind.investmentConcentration =>
        '${_percent(m['allocation_bps']!)}% × ${money('portfolio_minor')} '
            '(n=${m['holding_count']})',
    };
  }

  String _categoryName(BuildContext context, EntityId? id) {
    if (id == null) return '';
    for (final category in finance.categories) {
      if (category.id == id) return categoryLabel(context, category);
    }
    return id.value.substring(0, 8);
  }
}

IconData _icon(FinancialInsightKind kind) => switch (kind) {
  FinancialInsightKind.spendingTrend => Icons.trending_up,
  FinancialInsightKind.expenseAnomaly => Icons.notification_important_outlined,
  FinancialInsightKind.budgetForecast => Icons.savings_outlined,
  FinancialInsightKind.cashFlowForecast => Icons.waterfall_chart,
  FinancialInsightKind.recurringCommitments => Icons.event_repeat,
  FinancialInsightKind.goalContribution => Icons.flag_outlined,
  FinancialInsightKind.emergencyFund => Icons.health_and_safety_outlined,
  FinancialInsightKind.debtOverview => Icons.credit_score_outlined,
  FinancialInsightKind.netWorthTrend => Icons.account_balance_outlined,
  FinancialInsightKind.investmentConcentration => Icons.donut_large,
};

String _money(BuildContext context, CurrencyCode currency, int minor) =>
    EquisFormatters.moneyMinor(context, currency: currency, minor: minor);

String _percent(int bps) => (bps / 100).toStringAsFixed(1);
String _signedPercent(int bps) {
  final value = _percent(bps);
  return bps > 0 ? '+$value' : value;
}
