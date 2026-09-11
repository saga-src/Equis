import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/budgeting/budget_models.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/taxonomy_labels.dart';
import '../shared/equis_glass.dart';
import 'budget_controller.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({this.financeOverride, this.stateOverride, super.key});

  final LocalFinanceSnapshot? financeOverride;
  final BudgetState? stateOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final finance =
        financeOverride ??
        ref.watch(localFinanceControllerProvider).valueOrNull;
    final BudgetState state =
        stateOverride ?? ref.watch(budgetControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.budgetsTitle)),
      floatingActionButton: finance?.vault == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, finance!),
              icon: const Icon(Icons.add),
              label: Text(l10n.addBudgetAction),
            ),
      body: finance?.vault == null
          ? Center(child: Text(l10n.setupRequiredMessage))
          : state.loading && state.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.items.isEmpty
          ? Center(child: Text(l10n.budgetLoadFailedMessage))
          : state.items.isEmpty
          ? Center(child: Text(l10n.noBudgetsMessage))
          : RefreshIndicator(
              onRefresh: ref.read(budgetControllerProvider.notifier).reload,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: state.items.length,
                itemBuilder: (context, index) => _BudgetCard(
                  value: state.items[index],
                  onEdit: () => _edit(
                    context,
                    ref,
                    finance!,
                    existing: state.items[index].budget,
                  ),
                  onDelete: () =>
                      _delete(context, ref, state.items[index].budget),
                ),
              ),
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance, {
    BudgetDefinition? existing,
  }) async {
    final draft = await showDialog<_BudgetDraft>(
      context: context,
      builder: (context) => _BudgetEditor(finance: finance, existing: existing),
    );
    if (draft == null) return;
    final controller = ref.read(budgetControllerProvider.notifier);
    if (existing == null) {
      await controller.create(
        name: draft.name,
        currency: finance.vault!.baseCurrency,
        limitText: draft.limit,
        periodType: draft.periodType,
        startsOn: draft.startsOn,
        endsOn: draft.endsOn,
        warningThresholdBps: draft.warningThresholdBps,
        scope: draft.scope,
      );
    } else {
      await controller.update(
        existing: existing,
        name: draft.name,
        limitText: draft.limit,
        periodType: draft.periodType,
        startsOn: draft.startsOn,
        endsOn: draft.endsOn,
        warningThresholdBps: draft.warningThresholdBps,
        scope: draft.scope,
        enabled: true,
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BudgetDefinition budget,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmDeleteTitle),
        content: Text(l10n.confirmDeleteBudgetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(budgetControllerProvider.notifier).delete(budget);
    }
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.value,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress value;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _stateColor(context, value.warningState);
    final progress = (value.usageBps / 10000).clamp(0.0, 1.0);
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
                    value.budget.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  avatar: Icon(_stateIcon(value.warningState), size: 18),
                  label: Text(_stateLabel(l10n, value.warningState)),
                  side: BorderSide(color: color),
                ),
                PopupMenuButton<_BudgetAction>(
                  onSelected: (action) => switch (action) {
                    _BudgetAction.edit => onEdit(),
                    _BudgetAction.delete => onDelete(),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _BudgetAction.edit,
                      child: Text(l10n.editBudgetAction),
                    ),
                    PopupMenuItem(
                      value: _BudgetAction.delete,
                      child: Text(l10n.deleteBudgetAction),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              EquisFormatters.dateRange(
                context,
                value.period.start,
                value.period.end,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              color: color,
              minHeight: 10,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Metric(
                  label: l10n.budgetUsedLabel,
                  value: _money(
                    context,
                    value.budget.currency,
                    value.usedMinor,
                  ),
                ),
                _Metric(
                  label: l10n.budgetRemainingLabel,
                  value: _money(
                    context,
                    value.budget.currency,
                    value.remainingMinor,
                  ),
                ),
                _Metric(
                  label: l10n.budgetProjectedLabel,
                  value: _money(
                    context,
                    value.budget.currency,
                    value.projectedMinor,
                  ),
                ),
              ],
            ),
            if (value.likelyToExceed) ...[
              const SizedBox(height: 12),
              Text(
                l10n.budgetLikelyExceedMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (!value.isComplete || value.usesEstimatedRates) ...[
              const SizedBox(height: 8),
              Text(
                !value.isComplete
                    ? l10n.budgetIncompleteFxMessage
                    : l10n.budgetEstimatedFxMessage,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _BudgetAction { edit, delete }

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(value, style: EquisTypography.numeric),
    ],
  );
}

class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({required this.finance, this.existing});

  final LocalFinanceSnapshot finance;
  final BudgetDefinition? existing;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  final _name = TextEditingController();
  final _limit = TextEditingController();
  final _threshold = TextEditingController();
  BudgetPeriodType _periodType = BudgetPeriodType.monthly;
  LocalDate? _startsOn;
  LocalDate? _endsOn;
  final _categories = <EntityId>{};
  final _accounts = <EntityId>{};
  final _tags = <EntityId>{};
  bool _includeDescendants = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _threshold.text = '80';
      return;
    }
    _name.text = existing.name;
    _limit.text = (existing.limitMinor / 100).toStringAsFixed(2);
    _threshold.text = (existing.warningThresholdBps / 100).toStringAsFixed(0);
    _periodType = existing.periodType;
    _startsOn = existing.startsOn;
    _endsOn = existing.endsOn;
    _categories.addAll(
      existing.scope.categories.map((item) => item.categoryId),
    );
    _accounts.addAll(existing.scope.accountIds);
    _tags.addAll(existing.scope.tagIds);
    if (existing.scope.categories.isNotEmpty) {
      _includeDescendants = existing.scope.categories.every(
        (item) => item.includeDescendants,
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    _threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final expenseCategories = widget.finance.categories
        .where((item) => item.type == CategoryType.expense && !item.archived)
        .toList();
    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.addBudgetAction : l10n.editBudgetAction,
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.budgetNameLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.budgetLimitLabel,
                  prefixText: '${widget.finance.vault!.baseCurrency.value} ',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BudgetPeriodType>(
                initialValue: _periodType,
                decoration: InputDecoration(labelText: l10n.budgetPeriodLabel),
                items: [
                  for (final type in BudgetPeriodType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_periodLabel(l10n, type)),
                    ),
                ],
                onChanged: (value) => setState(() => _periodType = value!),
              ),
              if (_periodType == BudgetPeriodType.custom) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(true),
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          _startsOn?.toString() ?? l10n.customStartDateLabel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(false),
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _endsOn?.toString() ?? l10n.customEndDateLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _threshold,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.budgetWarningThresholdLabel,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.budgetScopeLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_categories.isEmpty && _accounts.isEmpty && _tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.overallSpendingScope),
                ),
              const SizedBox(height: 12),
              Text(l10n.budgetCategoriesScope),
              Wrap(
                spacing: 8,
                children: [
                  for (final category in expenseCategories)
                    FilterChip(
                      label: Text(categoryLabel(context, category)),
                      selected: _categories.contains(category.id),
                      onSelected: (selected) => setState(
                        () => selected
                            ? _categories.add(category.id)
                            : _categories.remove(category.id),
                      ),
                    ),
                ],
              ),
              if (_categories.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.includeDescendantsLabel),
                  value: _includeDescendants,
                  onChanged: (value) =>
                      setState(() => _includeDescendants = value),
                ),
              const SizedBox(height: 8),
              Text(l10n.budgetAccountsScope),
              Wrap(
                spacing: 8,
                children: [
                  for (final aggregate in widget.finance.accounts)
                    FilterChip(
                      label: Text(aggregate.account.name),
                      selected: _accounts.contains(aggregate.account.id),
                      onSelected: (selected) => setState(
                        () => selected
                            ? _accounts.add(aggregate.account.id)
                            : _accounts.remove(aggregate.account.id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.budgetTagsScope),
              Wrap(
                spacing: 8,
                children: [
                  for (final tag in widget.finance.tags)
                    FilterChip(
                      label: Text(tagLabel(context, tag)),
                      selected: _tags.contains(tag.id),
                      onSelected: (selected) => setState(
                        () =>
                            selected ? _tags.add(tag.id) : _tags.remove(tag.id),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.saveAction)),
      ],
    );
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final current = start ? _startsOn : _endsOn;
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
      initialDate: current?.toUtcDate() ?? now,
    );
    if (selected == null) return;
    setState(() {
      final value = LocalDate(selected.year, selected.month, selected.day);
      if (start) {
        _startsOn = value;
      } else {
        _endsOn = value;
      }
    });
  }

  void _submit() {
    final name = _name.text.trim();
    final limit = _limit.text.trim();
    final threshold = int.tryParse(_threshold.text.trim());
    if (name.isEmpty ||
        limit.isEmpty ||
        threshold == null ||
        threshold < 1 ||
        threshold > 100) {
      return;
    }
    if (_periodType == BudgetPeriodType.custom &&
        (_startsOn == null ||
            _endsOn == null ||
            _startsOn!.compareTo(_endsOn!) > 0)) {
      return;
    }
    Navigator.pop(
      context,
      _BudgetDraft(
        name: name,
        limit: limit,
        periodType: _periodType,
        startsOn: _periodType == BudgetPeriodType.custom ? _startsOn : null,
        endsOn: _periodType == BudgetPeriodType.custom ? _endsOn : null,
        warningThresholdBps: threshold * 100,
        scope: BudgetScope(
          categories: [
            for (final id in _categories)
              BudgetCategoryScope(
                categoryId: id,
                includeDescendants: _includeDescendants,
              ),
          ],
          accountIds: _accounts,
          tagIds: _tags,
        ),
      ),
    );
  }
}

final class _BudgetDraft {
  const _BudgetDraft({
    required this.name,
    required this.limit,
    required this.periodType,
    required this.warningThresholdBps,
    required this.scope,
    this.startsOn,
    this.endsOn,
  });

  final String name;
  final String limit;
  final BudgetPeriodType periodType;
  final LocalDate? startsOn;
  final LocalDate? endsOn;
  final int warningThresholdBps;
  final BudgetScope scope;
}

String _periodLabel(AppLocalizations l10n, BudgetPeriodType type) =>
    switch (type) {
      BudgetPeriodType.weekly => l10n.weeklyBudgetPeriod,
      BudgetPeriodType.monthly => l10n.monthlyBudgetPeriod,
      BudgetPeriodType.yearly => l10n.yearlyBudgetPeriod,
      BudgetPeriodType.custom => l10n.customBudgetPeriod,
    };

String _stateLabel(AppLocalizations l10n, BudgetWarningState state) =>
    switch (state) {
      BudgetWarningState.safe => l10n.budgetSafeState,
      BudgetWarningState.approachingLimit => l10n.budgetApproachingState,
      BudgetWarningState.limitReached => l10n.budgetReachedState,
      BudgetWarningState.exceeded => l10n.budgetExceededState,
    };

IconData _stateIcon(BudgetWarningState state) => switch (state) {
  BudgetWarningState.safe => Icons.check_circle_outline,
  BudgetWarningState.approachingLimit => Icons.warning_amber_outlined,
  BudgetWarningState.limitReached => Icons.error_outline,
  BudgetWarningState.exceeded => Icons.dangerous_outlined,
};

Color _stateColor(BuildContext context, BudgetWarningState state) =>
    switch (state) {
      BudgetWarningState.safe => Theme.of(context).colorScheme.primary,
      BudgetWarningState.approachingLimit => const Color(0xFFF59E0B),
      BudgetWarningState.limitReached ||
      BudgetWarningState.exceeded => Theme.of(context).colorScheme.error,
    };

String _money(BuildContext context, CurrencyCode currency, int minor) =>
    EquisFormatters.moneyMinor(context, currency: currency, minor: minor);
