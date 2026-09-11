import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';
import '../accessibility/accessible_chart.dart';
import '../shared/equis_glass.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/wealth/asset_models.dart';
import '../../domain/wealth/net_worth_models.dart';
import '../../l10n/app_localizations.dart';
import 'wealth_controller.dart';

class WealthScreen extends ConsumerWidget {
  const WealthScreen({this.financeOverride, this.stateOverride, super.key});
  final LocalFinanceSnapshot? financeOverride;
  final WealthState? stateOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final finance =
        financeOverride ??
        ref.watch(localFinanceControllerProvider).valueOrNull;
    final WealthState state =
        stateOverride ?? ref.watch(wealthControllerProvider);
    final report = state.report;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.wealthTitle)),
      floatingActionButton: finance?.vault == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _create(context, ref, finance!),
              icon: const Icon(Icons.add),
              label: Text(l10n.addAssetAction),
            ),
      body: finance?.vault == null
          ? Center(child: Text(l10n.setupRequiredMessage))
          : state.loading && report == null
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && report == null
          ? Center(child: Text(l10n.wealthLoadFailedMessage))
          : report == null
          ? Center(child: Text(l10n.noAssetsMessage))
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(wealthControllerProvider.notifier).reload(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Summary(report: report),
                  if (report.current.missingRates.isNotEmpty)
                    _Notice(l10n.wealthIncompleteFxMessage),
                  if (report.current.usesEstimatedRates)
                    _Notice(l10n.wealthEstimatedFxMessage),
                  const SizedBox(height: 16),
                  _History(report: report),
                  const SizedBox(height: 16),
                  Text(
                    l10n.includedAccountsLabel,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final aggregate in finance!.accounts)
                    SwitchListTile(
                      key: ValueKey(
                        'net-worth-account-${aggregate.account.id.value}',
                      ),
                      title: Text(aggregate.account.name),
                      subtitle: Text(
                        l10n.accountNatureLabel(aggregate.account.nature.name),
                      ),
                      value: aggregate.account.includeInNetWorth,
                      onChanged: (included) async {
                        await ref
                            .read(localFinanceControllerProvider.notifier)
                            .setAccountNetWorthInclusion(aggregate, included);
                        await ref
                            .read(wealthControllerProvider.notifier)
                            .reload();
                      },
                    ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.physicalAssetsLabel,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (report.physicalAssets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(l10n.noAssetsMessage),
                    ),
                  for (final value in report.physicalAssets)
                    _AssetCard(
                      value: value,
                      onOverride: () => _override(context, ref, value.asset),
                      onDelete: () => _delete(context, ref, value.asset),
                    ),
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance,
  ) async {
    final draft = await showDialog<_AssetDraft>(
      context: context,
      builder: (_) => _AssetEditor(currency: finance.vault!.baseCurrency),
    );
    if (draft == null) return;
    await ref
        .read(wealthControllerProvider.notifier)
        .create(
          name: draft.name,
          type: draft.type,
          currency: finance.vault!.baseCurrency,
          costText: draft.cost,
          method: draft.method,
          acquiredOn: draft.date,
          annualRateText: draft.rate,
          usefulLifeText: draft.life,
          salvageText: draft.salvage,
          included: draft.included,
          notes: draft.notes,
        );
  }

  Future<void> _override(
    BuildContext context,
    WidgetRef ref,
    PhysicalAsset asset,
  ) async {
    final draft = await showDialog<_ValueDraft>(
      context: context,
      builder: (_) => const _ValueEditor(),
    );
    if (draft != null) {
      await ref
          .read(wealthControllerProvider.notifier)
          .overrideValue(asset, draft.value, draft.date, notes: draft.notes);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PhysicalAsset asset,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(l10n.confirmDeleteAssetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteAssetAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(wealthControllerProvider.notifier).delete(asset);
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.report});
  final NetWorthReport report;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final point = report.current;
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.netWorthLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              _money(context, report.currency, point.netWorthMinor),
              key: const Key('net-worth-total'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    l10n.totalAssetsLabel,
                    _money(context, report.currency, point.assetsMinor),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    l10n.totalLiabilitiesLabel,
                    _money(context, report.currency, point.liabilitiesMinor),
                  ),
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
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

class _History extends StatelessWidget {
  const _History({required this.report});
  final NetWorthReport report;
  @override
  Widget build(BuildContext context) {
    if (report.history.length < 2) return const SizedBox.shrink();
    final values = report.history
        .map((point) => point.netWorthMinor / 100)
        .toList();
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    if (min == max) {
      min -= 1;
      max += 1;
    }
    return SizedBox(
      height: 190,
      child: AccessibleChart(
        label: AppLocalizations.of(context).netWorthLabel,
        child: LineChart(
          LineChartData(
            minY: min,
            maxY: max,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                barWidth: 3,
                color: Theme.of(context).colorScheme.primary,
                dotData: const FlDotData(show: false),
                spots: [
                  for (var i = 0; i < values.length; i++)
                    FlSpot(i.toDouble(), values[i]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.value,
    required this.onOverride,
    required this.onDelete,
  });
  final AssetValue value;
  final VoidCallback onOverride;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EquisGlassCard(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.home_work_outlined)),
        title: Text(value.asset.name),
        subtitle: Text(
          '${l10n.physicalAssetTypeLabel(value.asset.type.name)} · '
          '${_method(l10n, value.asset.valuationMethod)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _money(context, value.asset.currency, value.valueMinor),
              style: EquisTypography.numeric,
            ),
            PopupMenuButton<String>(
              onSelected: (item) => item == 'value' ? onOverride() : onDelete(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'value',
                  child: Text(l10n.addValuationAction),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(l10n.deleteAssetAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetEditor extends StatefulWidget {
  const _AssetEditor({required this.currency});
  final CurrencyCode currency;
  @override
  State<_AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<_AssetEditor> {
  final name = TextEditingController(),
      cost = TextEditingController(),
      rate = TextEditingController(),
      life = TextEditingController(),
      salvage = TextEditingController(),
      notes = TextEditingController();
  var type = PhysicalAssetType.property;
  var method = AssetValuationMethod.manual;
  var date = _today();
  var included = true;
  @override
  void dispose() {
    for (final c in [name, cost, rate, life, salvage, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.addAssetAction),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: l.assetNameLabel),
              ),
              DropdownButtonFormField(
                initialValue: type,
                decoration: InputDecoration(labelText: l.assetTypeLabel),
                items: [
                  for (final v in PhysicalAssetType.values)
                    DropdownMenuItem(
                      value: v,
                      child: Text(l.physicalAssetTypeLabel(v.name)),
                    ),
                ],
                onChanged: (v) => setState(() => type = v!),
              ),
              TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.assetCostLabel),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.assetDateLabel),
                subtitle: Text(EquisFormatters.date(context, date)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final v = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200),
                    initialDate: date.toUtcDate(),
                  );
                  if (v != null) {
                    setState(() => date = LocalDate(v.year, v.month, v.day));
                  }
                },
              ),
              DropdownButtonFormField(
                initialValue: method,
                decoration: InputDecoration(labelText: l.valuationMethodLabel),
                items: [
                  for (final v in AssetValuationMethod.values)
                    DropdownMenuItem(value: v, child: Text(_method(l, v))),
                ],
                onChanged: (v) => setState(() => method = v!),
              ),
              if (method == AssetValuationMethod.percentageDepreciation ||
                  method == AssetValuationMethod.percentageAppreciation)
                TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.annualRateLabel),
                ),
              if (method == AssetValuationMethod.straightLine) ...[
                TextField(
                  controller: life,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l.usefulLifeMonthsLabel,
                  ),
                ),
                TextField(
                  controller: salvage,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.salvageValueLabel),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.includeInNetWorthLabel),
                value: included,
                onChanged: (v) => setState(() => included = v),
              ),
              TextField(
                controller: notes,
                decoration: InputDecoration(labelText: l.notesLabel),
              ),
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
          onPressed: () {
            if (name.text.trim().isNotEmpty && cost.text.trim().isNotEmpty) {
              Navigator.pop(
                context,
                _AssetDraft(
                  name.text.trim(),
                  type,
                  cost.text,
                  method,
                  date,
                  rate.text,
                  life.text,
                  salvage.text,
                  included,
                  notes.text,
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

class _ValueEditor extends StatefulWidget {
  const _ValueEditor();
  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  final value = TextEditingController(), notes = TextEditingController();
  var date = _today();
  @override
  void dispose() {
    value.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.addValuationAction),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: value,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.currentValueLabel),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.valuationDateLabel),
            subtitle: Text(EquisFormatters.date(context, date)),
            onTap: () async {
              final v = await showDatePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                initialDate: date.toUtcDate(),
              );
              if (v != null) {
                setState(() => date = LocalDate(v.year, v.month, v.day));
              }
            },
          ),
          TextField(
            controller: notes,
            decoration: InputDecoration(labelText: l.notesLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            if (value.text.trim().isNotEmpty) {
              Navigator.pop(context, _ValueDraft(value.text, date, notes.text));
            }
          },
          child: Text(l.saveAction),
        ),
      ],
    );
  }
}

final class _AssetDraft {
  const _AssetDraft(
    this.name,
    this.type,
    this.cost,
    this.method,
    this.date,
    this.rate,
    this.life,
    this.salvage,
    this.included,
    this.notes,
  );
  final String name, cost, rate, life, salvage, notes;
  final PhysicalAssetType type;
  final AssetValuationMethod method;
  final LocalDate date;
  final bool included;
}

final class _ValueDraft {
  const _ValueDraft(this.value, this.date, this.notes);
  final String value, notes;
  final LocalDate date;
}

String _method(
  AppLocalizations l,
  AssetValuationMethod value,
) => switch (value) {
  AssetValuationMethod.manual => l.manualValuationMethod,
  AssetValuationMethod.straightLine => l.straightLineValuationMethod,
  AssetValuationMethod.percentageDepreciation => l.depreciationValuationMethod,
  AssetValuationMethod.percentageAppreciation => l.appreciationValuationMethod,
  AssetValuationMethod.custom => l.customValuationMethod,
};
String _money(BuildContext context, CurrencyCode currency, int minor) =>
    EquisFormatters.moneyMinor(context, currency: currency, minor: minor);
LocalDate _today() {
  final n = DateTime.now();
  return LocalDate(n.year, n.month, n.day);
}
