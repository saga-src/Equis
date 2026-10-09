import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../formatting/equis_formatters.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../application/ports/budget_repository.dart';
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
    final controller = ref.read(budgetControllerProvider.notifier);
    final month = state.selectedMonth ?? BudgetMonth.fromDate(controller.today);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.budgetsTitle)),
      floatingActionButton: finance?.vault == null
          ? null
          : FloatingActionButton.extended(
              onPressed: state.saving
                  ? null
                  : () => _edit(context, ref, finance!),
              icon: const Icon(Icons.add),
              label: Text(l10n.addBudgetAction),
            ),
      body: finance?.vault == null
          ? Center(child: Text(l10n.setupRequiredMessage))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            key: const Key('budget-previous-month'),
                            tooltip: l10n.budgetPreviousMonth,
                            onPressed:
                                state.saving ||
                                    month.start.year == 1 &&
                                        month.start.month == 1
                                ? null
                                : () => controller.selectMonth(
                                    _offsetMonth(month, -1),
                                  ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          TextButton.icon(
                            key: const Key('budget-select-month'),
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(
                              EquisFormatters.monthYear(context, month.start),
                            ),
                            onPressed: state.saving
                                ? null
                                : () async {
                                    final selected =
                                        await showDialog<BudgetMonth>(
                                          context: context,
                                          builder: (_) =>
                                              _BudgetMonthPicker(month: month),
                                        );
                                    if (selected != null) {
                                      await controller.selectMonth(selected);
                                    }
                                  },
                          ),
                          IconButton(
                            key: const Key('budget-next-month'),
                            tooltip: l10n.budgetNextMonth,
                            onPressed:
                                state.saving ||
                                    month.start.year == 9999 &&
                                        month.start.month == 12
                                ? null
                                : () => controller.selectMonth(
                                    _offsetMonth(month, 1),
                                  ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                          TextButton(
                            onPressed: state.saving
                                ? null
                                : () => controller.selectMonth(
                                    BudgetMonth.fromDate(controller.today),
                                  ),
                            child: Text(l10n.budgetCurrentMonth),
                          ),
                        ],
                      ),
                      Text(
                        l10n.budgetMonthScopeHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      CheckboxListTile(
                        key: const Key('budget-show-deleted'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.budgetShowDeleted),
                        value: state.includeDeleted,
                        onChanged: state.saving
                            ? null
                            : (value) => controller.showDeleted(value!),
                      ),
                    ],
                  ),
                ),
                if (state.loading) const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: controller.reload,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (state.error != null) ...[
                          Text(l10n.budgetLoadFailedMessage),
                          TextButton(
                            onPressed: controller.reload,
                            child: Text(l10n.budgetRetryAction),
                          ),
                        ],
                        if (!state.loading &&
                            state.items.isEmpty &&
                            state.error == null)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(l10n.budgetEmptyMonth),
                          ),
                        for (final item in state.items)
                          _BudgetCard(
                            value: item,
                            finance: finance!,
                            today: controller.today,
                            onEdit: () =>
                                _edit(context, ref, finance, existing: item),
                            onDelete: () => _delete(context, ref, item.budget),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance, {
    BudgetProgress? existing,
  }) async {
    final controller = ref.read(budgetControllerProvider.notifier);
    final month = existing == null
        ? BudgetMonth.fromDate(controller.today)
        : BudgetMonth.fromDate(existing.period.start);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BudgetEditor(
        finance: finance,
        existing: existing,
        month: month,
        onSave: (draft) async {
          if (existing == null) {
            return controller.create(
              name: draft.name,
              currency: finance.vault!.baseCurrency,
              limitText: draft.limit,
              periodType: draft.periodType,
              startsOn: draft.startsOn,
              endsOn: draft.endsOn,
              warningThresholdBps: draft.warningThresholdBps,
              scope: draft.scope,
              limitMethod: draft.limitMethod,
            );
          }
          if (existing.budget.periodType == BudgetPeriodType.monthly) {
            if (draft.editScope == BudgetMonthlyEditScope.onlyMonth &&
                _sameConfiguration(draft, existing)) {
              return draft.name == existing.budget.name
                  ? true
                  : controller.rename(existing.budget, draft.name);
            }
            return controller.updateMonthly(
              existing: existing.budget,
              month: month,
              name: draft.name,
              limitText: draft.limit,
              limitMethod: draft.limitMethod,
              warningThresholdBps: draft.warningThresholdBps,
              scope: draft.scope,
              editScope: draft.editScope,
            );
          }
          return controller.update(
            existing: existing.budget,
            name: draft.name,
            limitText: draft.limit,
            periodType: draft.periodType,
            startsOn: draft.startsOn,
            endsOn: draft.endsOn,
            warningThresholdBps: draft.warningThresholdBps,
            scope: draft.scope,
            enabled: existing.budget.enabled,
          );
        },
        onError: () => ref.read(budgetControllerProvider).error,
      ),
    );
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
      final saved = await ref
          .read(budgetControllerProvider.notifier)
          .delete(budget);
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.budgetSaveFailed)));
      }
    }
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.value,
    required this.onEdit,
    required this.onDelete,
    required this.finance,
    required this.today,
  });

  final BudgetProgress value;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final LocalFinanceSnapshot finance;
  final LocalDate today;

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
                Flexible(
                  child: Chip(
                    avatar: Icon(_stateIcon(value.warningState), size: 18),
                    label: Text(_stateLabel(l10n, value.warningState)),
                    side: BorderSide(color: color),
                  ),
                ),
                if (value.budget.deletedAt == null)
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
            if (value.budget.deletedAt != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.budgetDeletedReadOnly),
              ),
            Text(
              EquisFormatters.dateRange(
                context,
                value.period.start,
                value.period.end,
              ),
            ),
            if (value.budget.periodType == BudgetPeriodType.monthly) ...[
              Text(
                value.period.start.compareTo(today) > 0
                    ? l10n.budgetFutureMonthHint
                    : value.period.end.compareTo(today) < 0
                    ? l10n.budgetPastMonthHint
                    : l10n.budgetCurrentMonthHint(
                        EquisFormatters.date(context, today),
                      ),
              ),
              if (value.effectiveConfiguration case final configuration?)
                Text(
                  _configurationDescription(
                    context,
                    configuration,
                    BudgetMonth.fromDate(value.period.start),
                    value.budget.currency,
                  ),
                ),
            ],
            Text(
              _scopeDescription(
                context,
                value.effectiveConfiguration?.scope ?? value.budget.scope,
                finance,
              ),
            ),
            Text(
              l10n.budgetWarningValue(
                _budgetWarningPercent(
                  context,
                  value.effectiveConfiguration?.warningThresholdBps ??
                      value.budget.warningThresholdBps,
                ),
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
                  label: l10n.budgetLimitLabel,
                  value: _money(
                    context,
                    value.budget.currency,
                    value.effectiveLimitMinor,
                  ),
                ),
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
                _Metric(
                  label: l10n.budgetUsageLabel,
                  value: EquisFormatters.percentFromBasisPoints(
                    context,
                    value.usageBps,
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
  const _BudgetEditor({
    required this.finance,
    required this.month,
    required this.onSave,
    required this.onError,
    this.existing,
  });

  final LocalFinanceSnapshot finance;
  final BudgetProgress? existing;
  final BudgetMonth month;
  final Future<bool> Function(_BudgetDraft) onSave;
  final Object? Function() onError;

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
  final _descendants = <EntityId, bool>{};
  BudgetLimitMethod _limitMethod = BudgetLimitMethod.fixed;
  BudgetMonthlyEditScope _editScope = BudgetMonthlyEditScope.onlyMonth;
  bool _saving = false;
  String? _error;
  CurrencyCode get _currency =>
      widget.existing?.budget.currency ?? widget.finance.vault!.baseCurrency;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing?.budget;
    if (existing == null) {
      _threshold.text = '80';
      return;
    }
    _name.text = existing.name;
    final configuration = widget.existing?.effectiveConfiguration;
    _limit.text = _amountText(
      configuration?.amountMinor ?? existing.limitMinor,
    );
    _threshold.text = _amountText(
      configuration?.warningThresholdBps ?? existing.warningThresholdBps,
    );
    _limitMethod = configuration?.limitMethod ?? BudgetLimitMethod.fixed;
    _periodType = existing.periodType;
    _startsOn = existing.startsOn;
    _endsOn = existing.endsOn;
    final scope = configuration?.scope ?? existing.scope;
    _categories.addAll(scope.categories.map((item) => item.categoryId));
    _accounts.addAll(scope.accountIds);
    _tags.addAll(scope.tagIds);
    for (final category in scope.categories) {
      _descendants[category.categoryId] = category.includeDescendants;
    }
    if (scope.categories.isNotEmpty) {
      _includeDescendants = scope.categories.every(
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
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.existing == null
              ? l10n.addBudgetAction
              : l10n.editBudgetAction,
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('budget-name'),
                  enabled: !_saving,
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.budgetNameLabel),
                ),
                if (widget.existing?.budget.periodType ==
                    BudgetPeriodType.monthly)
                  Text(l10n.budgetGeneralNameHint),
                if (_periodType == BudgetPeriodType.monthly) ...[
                  const SizedBox(height: 12),
                  Text(EquisFormatters.monthYear(context, widget.month.start)),
                  if (widget.existing == null)
                    Text(l10n.budgetCreationMonthHint),
                  DropdownButtonFormField<BudgetLimitMethod>(
                    key: const Key('budget-limit-method'),
                    initialValue: _limitMethod,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.budgetLimitMethodLabel,
                    ),
                    items: [
                      for (final method in BudgetLimitMethod.values)
                        DropdownMenuItem(
                          value: method,
                          child: Text(_methodLabel(l10n, method)),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _limitMethod = value!),
                  ),
                  if (widget.existing != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<BudgetMonthlyEditScope>(
                      key: const Key('budget-edit-scope'),
                      initialValue: _editScope,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.budgetEditScopeLabel,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: BudgetMonthlyEditScope.onlyMonth,
                          child: Text(l10n.budgetOnlyMonth),
                        ),
                        DropdownMenuItem(
                          value: BudgetMonthlyEditScope.fromMonth,
                          child: Text(l10n.budgetFromMonth),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _editScope = value!),
                    ),
                    Text(l10n.budgetPreserveOverridesHint),
                  ],
                ],
                const SizedBox(height: 12),
                TextField(
                  key: const Key('budget-amount'),
                  enabled: !_saving,
                  controller: _limit,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        _periodType == BudgetPeriodType.monthly &&
                            _limitMethod != BudgetLimitMethod.fixed
                        ? l10n.budgetDailyAmountLabel
                        : l10n.budgetLimitLabel,
                    prefixText: '${_currency.value} ',
                  ),
                ),
                if (_periodType == BudgetPeriodType.monthly) ...[
                  const SizedBox(height: 8),
                  Text(
                    _preview(context),
                    key: const Key('budget-limit-preview'),
                  ),
                  if (_limitMethod == BudgetLimitMethod.weekday)
                    Text(l10n.budgetWeekdayHint),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<BudgetPeriodType>(
                  key: const Key('budget-period'),
                  isExpanded: true,
                  initialValue: _periodType,
                  decoration: InputDecoration(
                    labelText: l10n.budgetPeriodLabel,
                  ),
                  items: [
                    for (final type in BudgetPeriodType.values.where(
                      (type) =>
                          widget.existing == null ||
                          _periodType == BudgetPeriodType.monthly ||
                          type != BudgetPeriodType.monthly,
                    ))
                      DropdownMenuItem(
                        value: type,
                        child: Text(_periodLabel(l10n, type)),
                      ),
                  ],
                  onChanged:
                      _saving ||
                          widget.existing?.budget.periodType ==
                              BudgetPeriodType.monthly
                      ? null
                      : (value) => setState(() => _periodType = value!),
                ),
                if (_periodType == BudgetPeriodType.custom) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _pick(true),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _startsOn?.toString() ?? l10n.customStartDateLabel,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _pick(false),
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
                  key: const Key('budget-threshold'),
                  enabled: !_saving,
                  controller: _threshold,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                        onSelected: _saving
                            ? null
                            : (selected) => setState(
                                () => selected
                                    ? _categories.add(category.id)
                                    : _categories.remove(category.id),
                              ),
                      ),
                  ],
                ),
                for (final id
                    in _categories
                        .where(
                          (id) =>
                              !expenseCategories.any((item) => item.id == id),
                        )
                        .toList())
                  InputChip(
                    label: Text(l10n.budgetUnavailableCategory),
                    onDeleted: _saving
                        ? null
                        : () => setState(() => _categories.remove(id)),
                  ),
                if (_categories.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.includeDescendantsLabel),
                    value: _includeDescendants,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _includeDescendants = value;
                            for (final id in _categories) {
                              _descendants[id] = value;
                            }
                          }),
                  ),
                const SizedBox(height: 8),
                Text(l10n.budgetAccountsScope),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final aggregate in widget.finance.accounts.where(
                      (item) =>
                          !item.account.archived &&
                          item.account.deletedAt == null,
                    ))
                      FilterChip(
                        label: Text(aggregate.account.name),
                        selected: _accounts.contains(aggregate.account.id),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(
                                () => selected
                                    ? _accounts.add(aggregate.account.id)
                                    : _accounts.remove(aggregate.account.id),
                              ),
                      ),
                  ],
                ),
                for (final id
                    in _accounts
                        .where(
                          (id) => !widget.finance.accounts.any(
                            (item) =>
                                item.account.id == id &&
                                !item.account.archived &&
                                item.account.deletedAt == null,
                          ),
                        )
                        .toList())
                  InputChip(
                    label: Text(l10n.budgetUnavailableAccount),
                    onDeleted: _saving
                        ? null
                        : () => setState(() => _accounts.remove(id)),
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
                        onSelected: _saving
                            ? null
                            : (selected) => setState(
                                () => selected
                                    ? _tags.add(tag.id)
                                    : _tags.remove(tag.id),
                              ),
                      ),
                  ],
                ),
                for (final id
                    in _tags
                        .where(
                          (id) =>
                              !widget.finance.tags.any((item) => item.id == id),
                        )
                        .toList())
                  InputChip(
                    label: Text(l10n.budgetUnavailableTag),
                    onDeleted: _saving
                        ? null
                        : () => setState(() => _tags.remove(id)),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      key: const Key('budget-editor-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            key: const Key('budget-save'),
            onPressed: _saving ? null : _submit,
            child: Text(_saving ? l10n.budgetSaving : l10n.saveAction),
          ),
        ],
      ),
    );
  }

  String _preview(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_limit.text.trim().isEmpty) return l10n.budgetPreviewHint;
    try {
      final configuration = BudgetMonthlyConfiguration(
        limitMethod: _limitMethod,
        amountMinor: parseBudgetAmount(_limit.text, _currency),
        warningThresholdBps: 8000,
        scope: BudgetScope(),
      );
      configuration.limitFor(BudgetMonth(2024, 1));
      return _configurationDescription(
        context,
        configuration,
        widget.month,
        _currency,
      );
    } catch (_) {
      return l10n.budgetInvalidAmount;
    }
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final limit = _limit.text.trim();
    int threshold;
    try {
      threshold = parseBudgetAmount(_threshold.text, _currency);
      if (name.isEmpty || threshold > 10000) throw const FormatException();
      final amount = parseBudgetAmount(limit, _currency);
      if (_periodType == BudgetPeriodType.monthly) {
        BudgetMonthlyConfiguration(
          limitMethod: _limitMethod,
          amountMinor: amount,
          warningThresholdBps: threshold,
          scope: BudgetScope(),
        ).limitFor(BudgetMonth(2024, 1));
      }
    } catch (_) {
      setState(() => _error = l10n.budgetInvalidForm);
      return;
    }
    if (_periodType == BudgetPeriodType.custom &&
        (_startsOn == null ||
            _endsOn == null ||
            _startsOn!.compareTo(_endsOn!) > 0)) {
      setState(() => _error = l10n.budgetInvalidForm);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(
      _BudgetDraft(
        name: name,
        limit: limit,
        periodType: _periodType,
        startsOn: _periodType == BudgetPeriodType.custom ? _startsOn : null,
        endsOn: _periodType == BudgetPeriodType.custom ? _endsOn : null,
        warningThresholdBps: threshold,
        limitMethod: _limitMethod,
        editScope: _editScope,
        scope: BudgetScope(
          categories: [
            for (final id in _categories)
              BudgetCategoryScope(
                categoryId: id,
                includeDescendants: _descendants[id] ?? _includeDescendants,
              ),
          ],
          accountIds: _accounts,
          tagIds: _tags,
        ),
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.onError() is BudgetRevisionConflict
            ? l10n.budgetRevisionChanged
            : l10n.budgetSaveFailed;
      });
    }
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
    required this.limitMethod,
    required this.editScope,
  });

  final String name;
  final String limit;
  final BudgetPeriodType periodType;
  final LocalDate? startsOn;
  final LocalDate? endsOn;
  final int warningThresholdBps;
  final BudgetScope scope;
  final BudgetLimitMethod limitMethod;
  final BudgetMonthlyEditScope editScope;
}

BudgetMonth _offsetMonth(BudgetMonth month, int offset) {
  final date = DateTime.utc(month.start.year, month.start.month + offset);
  return BudgetMonth(date.year, date.month);
}

bool _sameConfiguration(_BudgetDraft draft, BudgetProgress value) {
  final configuration = value.effectiveConfiguration;
  final scope = configuration?.scope ?? value.budget.scope;
  bool sameIds(Set<EntityId> a, Set<EntityId> b) =>
      a.length == b.length && a.containsAll(b);
  return draft.limitMethod ==
          (configuration?.limitMethod ?? BudgetLimitMethod.fixed) &&
      parseBudgetAmount(draft.limit, value.budget.currency) ==
          (configuration?.amountMinor ?? value.budget.limitMinor) &&
      draft.warningThresholdBps ==
          (configuration?.warningThresholdBps ??
              value.budget.warningThresholdBps) &&
      sameIds(draft.scope.accountIds, scope.accountIds) &&
      sameIds(draft.scope.tagIds, scope.tagIds) &&
      draft.scope.categories.length == scope.categories.length &&
      draft.scope.categories.every(
        (link) => scope.categories.any(
          (other) =>
              link.categoryId == other.categoryId &&
              link.includeDescendants == other.includeDescendants,
        ),
      );
}

String _amountText(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

String _budgetWarningPercent(BuildContext context, int bps) =>
    NumberFormat.decimalPercentPattern(
      locale: Localizations.localeOf(context).toLanguageTag(),
      decimalDigits: bps % 100 == 0
          ? 0
          : bps % 10 == 0
          ? 1
          : 2,
    ).format(bps / 10000);

String _methodLabel(AppLocalizations l10n, BudgetLimitMethod method) =>
    switch (method) {
      BudgetLimitMethod.fixed => l10n.budgetFixedMonthly,
      BudgetLimitMethod.calendarDay => l10n.budgetPerDay,
      BudgetLimitMethod.weekday => l10n.budgetPerWeekday,
    };

String _configurationDescription(
  BuildContext context,
  BudgetMonthlyConfiguration configuration,
  BudgetMonth month,
  CurrencyCode currency,
) {
  final l10n = AppLocalizations.of(context);
  final total = _money(context, currency, configuration.limitFor(month));
  if (configuration.limitMethod == BudgetLimitMethod.fixed) {
    return l10n.budgetMonthlyTotal(total);
  }
  final days = configuration.limitMethod == BudgetLimitMethod.calendarDay
      ? month.days
      : month.weekdays;
  return '${_methodLabel(l10n, configuration.limitMethod)} · ${l10n.budgetLimitCalculation(_money(context, currency, configuration.amountMinor), days, total)}';
}

String _scopeDescription(
  BuildContext context,
  BudgetScope scope,
  LocalFinanceSnapshot finance,
) {
  final l10n = AppLocalizations.of(context);
  if (scope.isOverall) return l10n.overallSpendingScope;
  final categories = [
    for (final link in scope.categories)
      if (link.includeDescendants)
        l10n.budgetCategoryWithDescendants(
          finance.categories.any((item) => item.id == link.categoryId)
              ? categoryLabel(
                  context,
                  finance.categories.firstWhere(
                    (item) => item.id == link.categoryId,
                  ),
                )
              : l10n.budgetUnavailableCategory,
        )
      else
        finance.categories.any((item) => item.id == link.categoryId)
            ? categoryLabel(
                context,
                finance.categories.firstWhere(
                  (item) => item.id == link.categoryId,
                ),
              )
            : l10n.budgetUnavailableCategory,
  ];
  final accounts = [
    for (final id in scope.accountIds)
      finance.accounts.any((item) => item.account.id == id)
          ? finance.accounts
                .firstWhere((item) => item.account.id == id)
                .account
                .name
          : l10n.budgetUnavailableAccount,
  ];
  final tags = [
    for (final id in scope.tagIds)
      finance.tags.any((item) => item.id == id)
          ? tagLabel(context, finance.tags.firstWhere((item) => item.id == id))
          : l10n.budgetUnavailableTag,
  ];
  String names(List<String> values) =>
      values.isEmpty ? l10n.budgetAllFilters : values.join(', ');
  return '${l10n.budgetCategoriesScope}: ${names(categories)}\n'
      '${l10n.budgetAccountsScope}: ${names(accounts)}\n'
      '${l10n.budgetTagsScope}: ${names(tags)}';
}

class _BudgetMonthPicker extends StatefulWidget {
  const _BudgetMonthPicker({required this.month});
  final BudgetMonth month;
  @override
  State<_BudgetMonthPicker> createState() => _BudgetMonthPickerState();
}

class _BudgetMonthPickerState extends State<_BudgetMonthPicker> {
  late final _year = TextEditingController(
    text: widget.month.start.year.toString(),
  );
  late int _month = widget.month.start.month;
  bool _invalid = false;
  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.budgetSelectMonth),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('budget-month-year'),
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.budgetYearLabel,
                errorText: _invalid ? l10n.budgetInvalidMonth : null,
              ),
            ),
            DropdownButtonFormField<int>(
              key: const Key('budget-month-number'),
              initialValue: _month,
              isExpanded: true,
              items: [
                for (var month = 1; month <= 12; month++)
                  DropdownMenuItem(
                    value: month,
                    child: Text(
                      DateFormat.MMMM(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(DateTime(2024, month)),
                    ),
                  ),
              ],
              onChanged: (value) => _month = value!,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          key: const Key('budget-month-apply'),
          onPressed: () {
            final year = int.tryParse(_year.text.trim());
            if (year == null || year < 1 || year > 9999) {
              setState(() => _invalid = true);
              return;
            }
            Navigator.pop(context, BudgetMonth(year, _month));
          },
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }
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
