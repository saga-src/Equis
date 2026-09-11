import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../formatting/equis_formatters.dart';
import '../accessibility/accessible_chart.dart';
import '../shared/equis_glass.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/goals/cash_flow_projection.dart';
import '../../domain/goals/goal_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import 'goal_controller.dart';

class GoalScreen extends ConsumerWidget {
  const GoalScreen({this.financeOverride, this.stateOverride, super.key});

  final LocalFinanceSnapshot? financeOverride;
  final GoalState? stateOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final finance =
        financeOverride ??
        ref.watch(localFinanceControllerProvider).valueOrNull;
    final GoalState state = stateOverride ?? ref.watch(goalControllerProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.goalsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.goalsTabLabel),
              Tab(text: l10n.cashFlowProjectionTabLabel),
            ],
          ),
        ),
        floatingActionButton: finance?.vault == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _edit(context, ref, finance!),
                icon: const Icon(Icons.add),
                label: Text(l10n.addGoalAction),
              ),
        body: finance?.vault == null
            ? Center(child: Text(l10n.setupRequiredMessage))
            : state.loading && state.items.isEmpty && state.cashFlow == null
            ? const Center(child: CircularProgressIndicator())
            : state.error != null &&
                  state.items.isEmpty &&
                  state.cashFlow == null
            ? Center(child: Text(l10n.goalLoadFailedMessage))
            : TabBarView(
                children: [
                  _GoalList(
                    state: state,
                    onEdit: (goal) =>
                        _edit(context, ref, finance!, existing: goal),
                    onContribute: (goal) =>
                        _contribute(context, ref, finance!, goal),
                    onDelete: (goal) => _delete(context, ref, goal),
                  ),
                  _CashFlowView(projection: state.cashFlow),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance, {
    GoalDefinition? existing,
  }) async {
    final draft = await showDialog<_GoalDraft>(
      context: context,
      builder: (context) => _GoalEditor(finance: finance, existing: existing),
    );
    if (draft == null) return;
    final controller = ref.read(goalControllerProvider.notifier);
    if (existing == null) {
      await controller.create(
        name: draft.name,
        type: draft.type,
        currency: finance.vault!.baseCurrency,
        targetText: draft.target,
        plannedMonthlyText: draft.plannedMonthly,
        targetDate: draft.targetDate,
        trackingMode: draft.trackingMode,
        priority: draft.priority,
        accountPocketIds: draft.pocketIds,
      );
    } else {
      await controller.update(
        existing: existing,
        name: draft.name,
        type: draft.type,
        targetText: draft.target,
        plannedMonthlyText: draft.plannedMonthly,
        targetDate: draft.targetDate,
        trackingMode: draft.trackingMode,
        priority: draft.priority,
        accountPocketIds: draft.pocketIds,
      );
    }
  }

  Future<void> _contribute(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot finance,
    GoalDefinition goal,
  ) async {
    final draft = await showDialog<_ContributionDraft>(
      context: context,
      builder: (context) => _ContributionEditor(finance: finance),
    );
    if (draft == null) return;
    await ref
        .read(goalControllerProvider.notifier)
        .contribute(
          goal: goal,
          amountText: draft.amount,
          date: draft.date,
          transactionId: draft.transactionId,
          notes: draft.notes,
        );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    GoalDefinition goal,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.confirmDeleteTitle),
        content: Text(l10n.confirmDeleteGoalBody),
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
      await ref.read(goalControllerProvider.notifier).delete(goal);
    }
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({
    required this.state,
    required this.onEdit,
    required this.onContribute,
    required this.onDelete,
  });

  final GoalState state;
  final ValueChanged<GoalDefinition> onEdit;
  final ValueChanged<GoalDefinition> onContribute;
  final ValueChanged<GoalDefinition> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.items.isEmpty) return Center(child: Text(l10n.noGoalsMessage));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final value = state.items[index];
        return EquisGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_goalIcon(value.goal.type)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value.goal.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (value.targetIsReached)
                      Chip(label: Text(l10n.goalReachedLabel)),
                    PopupMenuButton<_GoalAction>(
                      onSelected: (action) => switch (action) {
                        _GoalAction.edit => onEdit(value.goal),
                        _GoalAction.delete => onDelete(value.goal),
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _GoalAction.edit,
                          child: Text(l10n.editGoalAction),
                        ),
                        PopupMenuItem(
                          value: _GoalAction.delete,
                          child: Text(l10n.deleteGoalAction),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (value.progressBps / 10000).clamp(0.0, 1.0),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Value(
                      label: l10n.goalCurrentLabel,
                      value: _money(
                        context,
                        value.goal.currency,
                        value.currentMinor,
                      ),
                    ),
                    _Value(
                      label: l10n.goalTargetLabel,
                      value: _money(
                        context,
                        value.goal.currency,
                        value.goal.targetMinor,
                      ),
                    ),
                    if (value.requiredMonthlyMinor != null)
                      _Value(
                        label: l10n.requiredMonthlyContributionLabel,
                        value: _money(
                          context,
                          value.goal.currency,
                          value.requiredMonthlyMinor!,
                        ),
                      ),
                    if (value.expectedCompletionDate != null)
                      _Value(
                        label: l10n.expectedCompletionLabel,
                        value: value.expectedCompletionDate.toString(),
                      ),
                  ],
                ),
                if (!value.isComplete || value.usesEstimatedRates) ...[
                  const SizedBox(height: 8),
                  Text(
                    !value.isComplete
                        ? l10n.goalIncompleteFxMessage
                        : l10n.goalEstimatedFxMessage,
                  ),
                ],
                if (value.goal.trackingMode != GoalTrackingMode.linkedAccounts)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => onContribute(value.goal),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addGoalContributionAction),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _GoalAction { edit, delete }

class _CashFlowView extends StatelessWidget {
  const _CashFlowView({required this.projection});
  final CashFlowProjection? projection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = projection;
    if (value == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        EquisGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Value(
                        label: l10n.openingAvailableLabel,
                        value: _money(
                          context,
                          value.reportingCurrency,
                          value.openingAvailableMinor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _Value(
                        label: l10n.projectedClosingLabel,
                        value: _money(
                          context,
                          value.reportingCurrency,
                          value.closingProjectedMinor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(l10n.cashFlowEstimateDisclaimer),
                if (value.events.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    child: AccessibleChart(
                      label: l10n.cashFlowChartTitle,
                      child: LineChart(
                        LineChartData(
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(drawVerticalLine: false),
                          titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                FlSpot(0, value.openingAvailableMinor / 100),
                                for (var i = 0; i < value.events.length; i++)
                                  FlSpot(
                                    (i + 1).toDouble(),
                                    value.events[i].balanceAfterMinor / 100,
                                  ),
                              ],
                              color: Theme.of(context).colorScheme.primary,
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (value.events.isEmpty)
          EquisGlassCard(
            child: ListTile(title: Text(l10n.noProjectedEventsMessage)),
          )
        else
          for (final event in value.events)
            EquisGlassCard(
              child: ListTile(
                leading: Icon(_eventIcon(event.type)),
                title: Text(event.name ?? _eventLabel(l10n, event.type)),
                subtitle: Text(
                  '${EquisFormatters.date(context, event.date)} · '
                  '${_eventLabel(l10n, event.type)}\n'
                  '${l10n.projectedBalanceLabel}: '
                  '${_money(context, value.reportingCurrency, event.balanceAfterMinor)}',
                ),
                isThreeLine: true,
                trailing: Text(
                  _signedMoney(
                    context,
                    value.reportingCurrency,
                    event.amountMinor,
                  ),
                  style: EquisTypography.numeric,
                ),
              ),
            ),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});
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

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({required this.finance, this.existing});
  final LocalFinanceSnapshot finance;
  final GoalDefinition? existing;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _monthly = TextEditingController();
  final _priority = TextEditingController(text: '0');
  GoalType _type = GoalType.custom;
  GoalTrackingMode _tracking = GoalTrackingMode.manual;
  LocalDate? _targetDate;
  final _pockets = <EntityId>{};

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    _name.text = existing.name;
    _target.text = (existing.targetMinor / 100).toStringAsFixed(2);
    _monthly.text = existing.plannedMonthlyMinor == null
        ? ''
        : (existing.plannedMonthlyMinor! / 100).toStringAsFixed(2);
    _priority.text = '${existing.priority}';
    _type = existing.type;
    _tracking = existing.trackingMode;
    _targetDate = existing.targetDate;
    _pockets.addAll(existing.accountPocketIds);
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _monthly.dispose();
    _priority.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.addGoalAction : l10n.editGoalAction,
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.goalNameLabel),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GoalType>(
                initialValue: _type,
                decoration: InputDecoration(labelText: l10n.goalTypeLabel),
                items: [
                  for (final type in GoalType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_goalTypeLabel(l10n, type)),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.goalTargetLabel,
                  prefixText: '${widget.finance.vault!.baseCurrency.value} ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _monthly,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.plannedMonthlyContributionLabel,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _targetDate?.toString() ?? l10n.goalTargetDateLabel,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GoalTrackingMode>(
                initialValue: _tracking,
                decoration: InputDecoration(
                  labelText: l10n.goalTrackingModeLabel,
                ),
                items: [
                  for (final mode in GoalTrackingMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(_trackingLabel(l10n, mode)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _tracking = value!;
                  if (_tracking != GoalTrackingMode.linkedAccounts) {
                    _pockets.clear();
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priority,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.goalPriorityLabel),
              ),
              if (_tracking == GoalTrackingMode.linkedAccounts) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.linkedGoalAccountsLabel),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final aggregate in widget.finance.accounts)
                      for (final pocket in aggregate.pockets.where(
                        (item) => !item.archived,
                      ))
                        FilterChip(
                          label: Text(
                            '${aggregate.account.name} · ${pocket.currency.value}',
                          ),
                          selected: _pockets.contains(pocket.id),
                          onSelected: (selected) => setState(
                            () => selected
                                ? _pockets.add(pocket.id)
                                : _pockets.remove(pocket.id),
                          ),
                        ),
                  ],
                ),
              ],
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 50),
      initialDate: _targetDate?.toUtcDate() ?? DateTime(now.year + 1),
    );
    if (value != null) {
      setState(
        () => _targetDate = LocalDate(value.year, value.month, value.day),
      );
    }
  }

  void _submit() {
    final priority = int.tryParse(_priority.text.trim());
    if (_name.text.trim().isEmpty ||
        _target.text.trim().isEmpty ||
        priority == null ||
        priority < 0 ||
        (_tracking == GoalTrackingMode.linkedAccounts && _pockets.isEmpty)) {
      return;
    }
    Navigator.pop(
      context,
      _GoalDraft(
        name: _name.text.trim(),
        type: _type,
        target: _target.text.trim(),
        plannedMonthly: _monthly.text.trim(),
        targetDate: _targetDate,
        trackingMode: _tracking,
        priority: priority,
        pocketIds: _pockets,
      ),
    );
  }
}

class _ContributionEditor extends StatefulWidget {
  const _ContributionEditor({required this.finance});
  final LocalFinanceSnapshot finance;

  @override
  State<_ContributionEditor> createState() => _ContributionEditorState();
}

class _ContributionEditorState extends State<_ContributionEditor> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  late LocalDate _date;
  EntityId? _transactionId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = LocalDate(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addGoalContributionAction),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.goalContributionAmountLabel,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                '${l10n.goalContributionDateLabel}: '
                '${EquisFormatters.date(context, _date)}',
              ),
            ),
            if (widget.finance.recentTransactions.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<EntityId?>(
                initialValue: _transactionId,
                decoration: InputDecoration(
                  labelText: l10n.goalContributionTransactionLabel,
                ),
                items: [
                  const DropdownMenuItem<EntityId?>(
                    value: null,
                    child: Text('—'),
                  ),
                  for (final transaction in widget.finance.recentTransactions)
                    DropdownMenuItem<EntityId?>(
                      value: transaction.id,
                      child: Text(
                        transaction.title ??
                            '${transaction.financialDate} · ${transaction.type.stored}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _transactionId = value),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: l10n.goalContributionNotesLabel,
              ),
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
          onPressed: () {
            if (_amount.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _ContributionDraft(
                amount: _amount.text.trim(),
                date: _date,
                transactionId: _transactionId,
                notes: _notes.text.trim(),
              ),
            );
          },
          child: Text(l10n.saveAction),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date.toUtcDate(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      setState(
        () => _date = LocalDate(selected.year, selected.month, selected.day),
      );
    }
  }
}

final class _GoalDraft {
  const _GoalDraft({
    required this.name,
    required this.type,
    required this.target,
    required this.plannedMonthly,
    required this.trackingMode,
    required this.priority,
    required this.pocketIds,
    this.targetDate,
  });
  final String name;
  final GoalType type;
  final String target;
  final String plannedMonthly;
  final LocalDate? targetDate;
  final GoalTrackingMode trackingMode;
  final int priority;
  final Set<EntityId> pocketIds;
}

final class _ContributionDraft {
  const _ContributionDraft({
    required this.amount,
    required this.date,
    this.transactionId,
    this.notes,
  });
  final String amount;
  final LocalDate date;
  final EntityId? transactionId;
  final String? notes;
}

String _goalTypeLabel(AppLocalizations l10n, GoalType type) => switch (type) {
  GoalType.emergencyFund => l10n.emergencyFundGoalType,
  GoalType.vacation => l10n.vacationGoalType,
  GoalType.vehicle => l10n.vehicleGoalType,
  GoalType.home => l10n.homeGoalType,
  GoalType.debtPayoff => l10n.debtPayoffGoalType,
  GoalType.investment => l10n.investmentGoalType,
  GoalType.retirement => l10n.retirementGoalType,
  GoalType.education => l10n.educationGoalType,
  GoalType.custom => l10n.customGoalType,
};

String _trackingLabel(AppLocalizations l10n, GoalTrackingMode mode) =>
    switch (mode) {
      GoalTrackingMode.manual => l10n.manualGoalTracking,
      GoalTrackingMode.linkedAccounts => l10n.linkedAccountsGoalTracking,
      GoalTrackingMode.transactions => l10n.transactionsGoalTracking,
    };

String _eventLabel(AppLocalizations l10n, CashFlowEventType type) =>
    switch (type) {
      CashFlowEventType.recurringIncome => l10n.recurringIncomeProjectionType,
      CashFlowEventType.recurringExpense => l10n.recurringExpenseProjectionType,
      CashFlowEventType.installment => l10n.installmentProjectionType,
      CashFlowEventType.cardStatement => l10n.cardStatementProjectionType,
      CashFlowEventType.goalContribution => l10n.goalContributionProjectionType,
    };

IconData _goalIcon(GoalType type) => switch (type) {
  GoalType.emergencyFund => Icons.shield_outlined,
  GoalType.vacation => Icons.flight_outlined,
  GoalType.vehicle => Icons.directions_car_outlined,
  GoalType.home => Icons.home_outlined,
  GoalType.debtPayoff => Icons.trending_down,
  GoalType.investment => Icons.show_chart,
  GoalType.retirement => Icons.beach_access_outlined,
  GoalType.education => Icons.school_outlined,
  GoalType.custom => Icons.flag_outlined,
};

IconData _eventIcon(CashFlowEventType type) => switch (type) {
  CashFlowEventType.recurringIncome => Icons.arrow_downward,
  CashFlowEventType.recurringExpense => Icons.arrow_upward,
  CashFlowEventType.installment => Icons.calendar_month_outlined,
  CashFlowEventType.cardStatement => Icons.credit_card_outlined,
  CashFlowEventType.goalContribution => Icons.flag_outlined,
};

String _money(BuildContext context, CurrencyCode currency, int minor) =>
    EquisFormatters.moneyMinor(context, currency: currency, minor: minor);

String _signedMoney(BuildContext context, CurrencyCode currency, int minor) =>
    '${minor >= 0 ? '+' : '−'}${_money(context, currency, minor.abs())}';
