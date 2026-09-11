import 'package:flutter/material.dart';
import '../formatting/equis_formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/app_providers.dart';
import '../../app/theme/equis_theme.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/recurring/recurrence_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../l10n/app_localizations.dart';
import '../formatting/taxonomy_labels.dart';
import '../shared/equis_glass.dart';
import 'recurring_controller.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(localFinanceControllerProvider).valueOrNull;
    final recurring = ref.watch(recurringControllerProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.recurringTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.upcomingTabLabel),
              Tab(text: l10n.recurringRulesTabLabel),
            ],
          ),
        ),
        floatingActionButton: snapshot?.vault == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _create(context, ref, snapshot!),
                icon: const Icon(Icons.add),
                label: Text(l10n.addRecurringAction),
              ),
        body: snapshot?.vault == null
            ? Center(child: Text(l10n.setupRequiredMessage))
            : recurring.error != null && recurring.rules.isEmpty
            ? Center(child: Text(l10n.recurringLoadFailedMessage))
            : TabBarView(
                children: [
                  _UpcomingList(state: recurring),
                  _RulesList(state: recurring),
                ],
              ),
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    LocalFinanceSnapshot snapshot,
  ) async {
    final draft = await showDialog<_RecurringDraft>(
      context: context,
      builder: (context) => _RecurringEditor(snapshot: snapshot),
    );
    if (draft == null) return;
    await ref
        .read(recurringControllerProvider.notifier)
        .create(
          name: draft.name,
          type: draft.type,
          source: draft.source,
          destination: draft.destination,
          amountText: draft.amount,
          categoryId: draft.categoryId,
          startsOn: draft.startsOn,
          endsOn: draft.endsOn,
          pattern: draft.pattern,
          timezone: snapshot.vault!.timezone,
          title: draft.title,
          notes: draft.notes,
        );
  }
}

class _UpcomingList extends ConsumerWidget {
  const _UpcomingList({required this.state});
  final RecurringState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (state.loading && state.upcoming.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.upcoming.isEmpty) {
      return Center(child: Text(l10n.noUpcomingOccurrencesMessage));
    }
    return RefreshIndicator(
      onRefresh: ref.read(recurringControllerProvider.notifier).reload,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: state.upcoming.length,
        itemBuilder: (context, index) {
          final occurrence = state.upcoming[index];
          return EquisGlassCard(
            child: ListTile(
              leading: const Icon(Icons.event_repeat_outlined),
              title: Text(
                occurrence.schedule.template.title ??
                    occurrence.schedule.rule.name,
              ),
              subtitle: Text(
                '${occurrence.scheduledDate} · ${_occurrenceState(l10n, occurrence.state)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _amount(context, occurrence.schedule.template),
                    style: EquisTypography.numeric,
                  ),
                  if (occurrence.state == ScheduledOccurrenceState.scheduled ||
                      occurrence.state == ScheduledOccurrenceState.pending)
                    PopupMenuButton<_OccurrenceAction>(
                      onSelected: (action) =>
                          _act(context, ref, occurrence, action),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _OccurrenceAction.confirm,
                          child: Text(l10n.confirmOccurrenceAction),
                        ),
                        PopupMenuItem(
                          value: _OccurrenceAction.skip,
                          child: Text(l10n.skipOccurrenceAction),
                        ),
                        PopupMenuItem(
                          value: _OccurrenceAction.reschedule,
                          child: Text(l10n.rescheduleOccurrenceAction),
                        ),
                        PopupMenuItem(
                          value: _OccurrenceAction.modifyOne,
                          child: Text(l10n.modifyOneOccurrenceAction),
                        ),
                        PopupMenuItem(
                          value: _OccurrenceAction.modifyFuture,
                          child: Text(l10n.modifyFutureOccurrencesAction),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    ScheduledOccurrence occurrence,
    _OccurrenceAction action,
  ) async {
    final controller = ref.read(recurringControllerProvider.notifier);
    switch (action) {
      case _OccurrenceAction.confirm:
        await controller.confirm(occurrence);
      case _OccurrenceAction.skip:
        await controller.skip(occurrence);
      case _OccurrenceAction.reschedule:
        final date = await _pickDate(context, occurrence.scheduledDate);
        if (date != null) await controller.reschedule(occurrence, date);
      case _OccurrenceAction.modifyOne:
        final edit = await showDialog<_OccurrenceEdit>(
          context: context,
          builder: (context) => _OccurrenceEditor(occurrence: occurrence),
        );
        if (edit != null) {
          await controller.modifyOne(
            occurrence,
            amountText: edit.amount,
            title: edit.title,
          );
        }
      case _OccurrenceAction.modifyFuture:
        final edit = await showDialog<_OccurrenceEdit>(
          context: context,
          builder: (context) =>
              _OccurrenceEditor(occurrence: occurrence, includePattern: true),
        );
        if (edit != null) {
          await controller.modifyFuture(
            occurrence,
            amountText: edit.amount,
            title: edit.title,
            pattern: edit.pattern,
          );
        }
    }
  }
}

enum _OccurrenceAction { confirm, skip, reschedule, modifyOne, modifyFuture }

class _RulesList extends ConsumerWidget {
  const _RulesList({required this.state});
  final RecurringState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (state.rules.isEmpty) {
      return Center(child: Text(l10n.noRecurringRulesMessage));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: state.rules.length,
      itemBuilder: (context, index) {
        final schedule = state.rules[index];
        return EquisGlassCard(
          child: ListTile(
            leading: Icon(
              schedule.rule.enabled ? Icons.repeat : Icons.event_busy_outlined,
            ),
            title: Text(schedule.rule.name),
            subtitle: Text(
              '${_patternLabel(l10n, schedule.rule.pattern)} · ${schedule.rule.startsOn}',
            ),
            trailing: schedule.rule.enabled
                ? IconButton(
                    tooltip: l10n.endRecurrenceAction,
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: () async {
                      final now = DateTime.now();
                      final date = await _pickDate(
                        context,
                        LocalDate(now.year, now.month, now.day),
                      );
                      if (date != null) {
                        await ref
                            .read(recurringControllerProvider.notifier)
                            .end(schedule, date);
                      }
                    },
                  )
                : Chip(label: Text(l10n.endedRecurrenceLabel)),
          ),
        );
      },
    );
  }
}

class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({required this.snapshot});
  final LocalFinanceSnapshot snapshot;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  LedgerTransactionType _type = LedgerTransactionType.expense;
  EntityId? _sourceId;
  EntityId? _destinationId;
  EntityId? _categoryId;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  int _interval = 1;
  late LocalDate _startsOn;
  LocalDate? _endsOn;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startsOn = LocalDate(now.year, now.month, now.day);
    _sourceId = _pockets.firstOrNull?.pocket.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<_PocketOption> get _pockets => [
    for (final aggregate in widget.snapshot.accounts)
      for (final pocket in aggregate.pockets.where(
        (pocket) => !pocket.archived,
      ))
        _PocketOption(
          '${aggregate.account.name} · ${pocket.currency.value}',
          LedgerPocket(
            id: pocket.id,
            currency: pocket.currency,
            nature: aggregate.account.nature,
          ),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = _pockets
        .where((option) => option.pocket.id == _sourceId)
        .firstOrNull;
    final destinations = source == null
        ? const <_PocketOption>[]
        : _pockets
              .where(
                (option) =>
                    option.pocket.id != source.pocket.id &&
                    option.pocket.currency == source.pocket.currency &&
                    option.pocket.nature == source.pocket.nature,
              )
              .toList();
    final categoryType = _type == LedgerTransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    final categories = widget.snapshot.categories
        .where((category) => category.type == categoryType)
        .toList();
    return AlertDialog(
      title: Text(l10n.addRecurringAction),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.recurrenceNameLabel,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LedgerTransactionType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l10n.transactionTypeLabel,
                ),
                items: [
                  DropdownMenuItem(
                    value: LedgerTransactionType.expense,
                    child: Text(l10n.expenseTypeLabel),
                  ),
                  DropdownMenuItem(
                    value: LedgerTransactionType.income,
                    child: Text(l10n.incomeTypeLabel),
                  ),
                  DropdownMenuItem(
                    value: LedgerTransactionType.transfer,
                    child: Text(l10n.transferTypeLabel),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _type = value!;
                  _categoryId = null;
                  _destinationId = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EntityId>(
                initialValue: _sourceId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.fromAccountLabel),
                items: [
                  for (final option in _pockets)
                    DropdownMenuItem(
                      value: option.pocket.id,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _sourceId = value;
                  _destinationId = null;
                }),
              ),
              if (_type == LedgerTransactionType.transfer) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<EntityId>(
                  initialValue: _destinationId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.toAccountLabel),
                  items: [
                    for (final option in destinations)
                      DropdownMenuItem(
                        value: option.pocket.id,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _destinationId = value),
                ),
              ] else ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<EntityId>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.categoryLabel),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(categoryLabel(context, category)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: l10n.amountLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: InputDecoration(labelText: l10n.payeeLabel),
              ),
              const SizedBox(height: 12),
              _DateInput(
                label: l10n.recurrenceStartsLabel,
                value: _startsOn,
                onChanged: (date) => setState(() => _startsOn = date!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<RecurrenceFrequency>(
                      initialValue: _frequency,
                      decoration: InputDecoration(
                        labelText: l10n.frequencyLabel,
                      ),
                      items: [
                        for (final frequency in RecurrenceFrequency.values)
                          DropdownMenuItem(
                            value: frequency,
                            child: Text(_frequencyLabel(l10n, frequency)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _frequency = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<int>(
                      initialValue: _interval,
                      decoration: InputDecoration(
                        labelText: l10n.intervalLabel,
                      ),
                      items: [
                        for (var value = 1; value <= 12; value++)
                          DropdownMenuItem(value: value, child: Text('$value')),
                      ],
                      onChanged: (value) => setState(() => _interval = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DateInput(
                label: l10n.recurrenceEndsLabel,
                value: _endsOn,
                optional: true,
                onChanged: (date) => setState(() => _endsOn = date),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: InputDecoration(labelText: l10n.notesLabel),
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
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.createRecurringAction),
        ),
      ],
    );
  }

  void _submit() {
    final source = _pockets
        .where((option) => option.pocket.id == _sourceId)
        .firstOrNull;
    final destination = _pockets
        .where((option) => option.pocket.id == _destinationId)
        .firstOrNull;
    final valid =
        _name.text.trim().isNotEmpty &&
        _amount.text.trim().isNotEmpty &&
        source != null &&
        (_type == LedgerTransactionType.transfer
            ? destination != null
            : _categoryId != null) &&
        (_endsOn == null || _endsOn!.compareTo(_startsOn) >= 0);
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).requiredFieldMessage),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _RecurringDraft(
        name: _name.text.trim(),
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        type: _type,
        source: source.pocket,
        destination: destination?.pocket,
        categoryId: _categoryId,
        amount: _amount.text,
        startsOn: _startsOn,
        endsOn: _endsOn,
        pattern: RecurrencePattern(frequency: _frequency, interval: _interval),
      ),
    );
  }
}

class _OccurrenceEditor extends StatefulWidget {
  const _OccurrenceEditor({
    required this.occurrence,
    this.includePattern = false,
  });
  final ScheduledOccurrence occurrence;
  final bool includePattern;

  @override
  State<_OccurrenceEditor> createState() => _OccurrenceEditorState();
}

class _OccurrenceEditorState extends State<_OccurrenceEditor> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late RecurrenceFrequency _frequency;
  late int _interval;

  @override
  void initState() {
    super.initState();
    final template = widget.occurrence.schedule.template;
    _title = TextEditingController(text: template.title);
    _amount = TextEditingController(text: _amountText(template));
    _frequency = widget.occurrence.schedule.rule.pattern.frequency;
    _interval = widget.occurrence.schedule.rule.pattern.interval;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.includePattern
            ? l10n.modifyFutureOccurrencesAction
            : l10n.modifyOneOccurrenceAction,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: l10n.payeeLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l10n.amountLabel),
            ),
            if (widget.includePattern) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<RecurrenceFrequency>(
                initialValue: _frequency,
                decoration: InputDecoration(labelText: l10n.frequencyLabel),
                items: [
                  for (final frequency in RecurrenceFrequency.values)
                    DropdownMenuItem(
                      value: frequency,
                      child: Text(_frequencyLabel(l10n, frequency)),
                    ),
                ],
                onChanged: (value) => setState(() => _frequency = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _interval,
                decoration: InputDecoration(labelText: l10n.intervalLabel),
                items: [
                  for (var value = 1; value <= 12; value++)
                    DropdownMenuItem(value: value, child: Text('$value')),
                ],
                onChanged: (value) => setState(() => _interval = value!),
              ),
            ],
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
              _OccurrenceEdit(
                amount: _amount.text,
                title: _title.text,
                pattern: RecurrencePattern(
                  frequency: _frequency,
                  interval: _interval,
                ),
              ),
            );
          },
          child: Text(l10n.applyAction),
        ),
      ],
    );
  }
}

class _DateInput extends StatelessWidget {
  const _DateInput({
    required this.label,
    required this.value,
    required this.onChanged,
    this.optional = false,
  });
  final String label;
  final LocalDate? value;
  final ValueChanged<LocalDate?> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final selected = await _pickDate(context, value ?? _localToday());
      if (selected != null) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: optional && value != null
            ? IconButton(
                tooltip: AppLocalizations.of(context).clearValueAction,
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.clear),
              )
            : const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(value?.toString() ?? '—'),
    ),
  );
}

Future<LocalDate?> _pickDate(BuildContext context, LocalDate initial) async {
  final selected = await showDatePicker(
    context: context,
    firstDate: DateTime(1900),
    lastDate: DateTime(9999, 12, 31),
    initialDate: initial.toUtcDate(),
  );
  return selected == null
      ? null
      : LocalDate(selected.year, selected.month, selected.day);
}

LocalDate _localToday() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}

String _amountText(RecurringTemplate template) {
  final amount = template.movements.first.amountMinor.abs();
  return '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}';
}

String _amount(BuildContext context, RecurringTemplate template) {
  final movement = template.movements.first;
  return EquisFormatters.moneyMinor(
    context,
    currency: movement.pocket.currency,
    minor: movement.amountMinor.abs(),
  );
}

String _patternLabel(AppLocalizations l10n, RecurrencePattern pattern) =>
    pattern.interval == 1
    ? _frequencyLabel(l10n, pattern.frequency)
    : l10n.customIntervalLabel(
        pattern.interval,
        _frequencyLabel(l10n, pattern.frequency),
      );

String _frequencyLabel(AppLocalizations l10n, RecurrenceFrequency frequency) =>
    switch (frequency) {
      RecurrenceFrequency.daily => l10n.dailyFrequencyLabel,
      RecurrenceFrequency.weekly => l10n.weeklyFrequencyLabel,
      RecurrenceFrequency.monthly => l10n.monthlyFrequencyLabel,
      RecurrenceFrequency.yearly => l10n.yearlyFrequencyLabel,
    };

String _occurrenceState(
  AppLocalizations l10n,
  ScheduledOccurrenceState state,
) => switch (state) {
  ScheduledOccurrenceState.scheduled => l10n.scheduledOccurrenceLabel,
  ScheduledOccurrenceState.pending => l10n.pendingOccurrenceLabel,
  ScheduledOccurrenceState.confirmed => l10n.confirmedOccurrenceLabel,
  ScheduledOccurrenceState.skipped => l10n.skippedOccurrenceLabel,
};

final class _PocketOption {
  const _PocketOption(this.label, this.pocket);
  final String label;
  final LedgerPocket pocket;
}

final class _RecurringDraft {
  const _RecurringDraft({
    required this.name,
    required this.type,
    required this.source,
    required this.amount,
    required this.startsOn,
    required this.pattern,
    this.destination,
    this.categoryId,
    this.endsOn,
    this.title,
    this.notes,
  });
  final String name;
  final LedgerTransactionType type;
  final LedgerPocket source;
  final LedgerPocket? destination;
  final EntityId? categoryId;
  final String amount;
  final LocalDate startsOn;
  final LocalDate? endsOn;
  final RecurrencePattern pattern;
  final String? title;
  final String? notes;
}

final class _OccurrenceEdit {
  const _OccurrenceEdit({
    required this.amount,
    required this.title,
    required this.pattern,
  });
  final String amount;
  final String title;
  final RecurrencePattern pattern;
}
