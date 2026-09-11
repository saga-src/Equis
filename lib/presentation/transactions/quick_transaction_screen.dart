import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../formatting/equis_formatters.dart';

enum QuickTransactionType { expense, income, transfer }

final class QuickAccountOption {
  const QuickAccountOption({required this.label, required this.pocket});
  final String label;
  final LedgerPocket pocket;
}

final class QuickCategoryOption {
  const QuickCategoryOption({
    required this.id,
    required this.label,
    required this.type,
  });
  final EntityId id;
  final String label;
  final CategoryType type;
}

final class QuickTagOption {
  const QuickTagOption({required this.id, required this.label});
  final EntityId id;
  final String label;
}

final class QuickTransactionDraft {
  const QuickTransactionDraft({
    required this.type,
    required this.amountText,
    required this.sourcePocketId,
    required this.date,
    this.destinationPocketId,
    this.categoryId,
    this.tagIds = const [],
    this.title,
    this.notes,
  });

  final QuickTransactionType type;
  final String amountText;
  final EntityId sourcePocketId;
  final EntityId? destinationPocketId;
  final EntityId? categoryId;
  final LocalDate date;
  final List<EntityId> tagIds;
  final String? title;
  final String? notes;
}

class QuickTransactionScreen extends StatefulWidget {
  const QuickTransactionScreen({
    required this.accounts,
    required this.categories,
    required this.tags,
    required this.onSave,
    this.initialDraft,
    this.attachmentSection,
    super.key,
  });

  final List<QuickAccountOption> accounts;
  final List<QuickCategoryOption> categories;
  final List<QuickTagOption> tags;
  final QuickTransactionDraft? initialDraft;
  final Widget? attachmentSection;
  final Future<void> Function(QuickTransactionDraft draft) onSave;

  @override
  State<QuickTransactionScreen> createState() => _QuickTransactionScreenState();
}

class _QuickTransactionScreenState extends State<QuickTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late QuickTransactionType _type;
  late LocalDate _date;
  String? _sourceId;
  String? _destinationId;
  String? _categoryId;
  final _tagIds = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDraft;
    _amount = TextEditingController(text: initial?.amountText);
    _title = TextEditingController(text: initial?.title);
    _notes = TextEditingController(text: initial?.notes);
    _type = initial?.type ?? QuickTransactionType.expense;
    final today = DateTime.now();
    _date = initial?.date ?? LocalDate(today.year, today.month, today.day);
    _sourceId =
        initial?.sourcePocketId.value ??
        (widget.accounts.isEmpty
            ? null
            : widget.accounts.first.pocket.id.value);
    _destinationId = initial?.destinationPocketId?.value;
    _categoryId = initial?.categoryId?.value;
    _tagIds.addAll(initial?.tagIds.map((tag) => tag.value) ?? const []);
    _ensureCompatibleDefaults();
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = _categoriesForType;
    final destinations = _compatibleDestinations;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialDraft == null
              ? l10n.addTransactionAction
              : l10n.editTransactionAction,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<QuickTransactionType>(
              segments: [
                ButtonSegment(
                  value: QuickTransactionType.expense,
                  label: Text(l10n.expenseTypeLabel),
                ),
                ButtonSegment(
                  value: QuickTransactionType.income,
                  label: Text(l10n.incomeTypeLabel),
                ),
                ButtonSegment(
                  value: QuickTransactionType.transfer,
                  label: Text(l10n.transferTypeLabel),
                ),
              ],
              selected: {_type},
              onSelectionChanged: widget.initialDraft == null
                  ? (value) => setState(() {
                      _type = value.single;
                      _categoryId = null;
                      _destinationId = null;
                      _ensureCompatibleDefaults();
                    })
                  : null,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _amount,
              autofocus: widget.initialDraft == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l10n.amountLabel),
              validator: _required,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey('source-account'),
              initialValue: _sourceId,
              decoration: InputDecoration(
                labelText: _type == QuickTransactionType.transfer
                    ? l10n.fromAccountLabel
                    : l10n.accountLabel,
              ),
              items: [
                for (final account in widget.accounts)
                  DropdownMenuItem(
                    value: account.pocket.id.value,
                    child: Text(account.label),
                  ),
              ],
              onChanged: (value) => setState(() {
                _sourceId = value;
                _destinationId = null;
                _ensureCompatibleDefaults();
              }),
              validator: _required,
            ),
            if (_type == QuickTransactionType.transfer) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('destination-account'),
                initialValue:
                    destinations.any(
                      (option) => option.pocket.id.value == _destinationId,
                    )
                    ? _destinationId
                    : null,
                decoration: InputDecoration(labelText: l10n.toAccountLabel),
                items: [
                  for (final account in destinations)
                    DropdownMenuItem(
                      value: account.pocket.id.value,
                      child: Text(account.label),
                    ),
                ],
                onChanged: (value) => setState(() => _destinationId = value),
                validator: _required,
              ),
            ] else ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('category'),
                initialValue:
                    categories.any(
                      (category) => category.id.value == _categoryId,
                    )
                    ? _categoryId
                    : null,
                decoration: InputDecoration(labelText: l10n.categoryLabel),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id.value,
                      child: Text(category.label),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
                validator: _required,
              ),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.optionalDetailsLabel),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.dateLabel),
                  subtitle: Text(EquisFormatters.date(context, _date)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _pickDate,
                ),
                TextFormField(
                  controller: _title,
                  decoration: InputDecoration(labelText: l10n.payeeLabel),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: l10n.notesLabel),
                ),
                if (widget.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final tag in widget.tags)
                          FilterChip(
                            label: Text(tag.label),
                            selected: _tagIds.contains(tag.id.value),
                            onSelected: (selected) => setState(() {
                              selected
                                  ? _tagIds.add(tag.id.value)
                                  : _tagIds.remove(tag.id.value);
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (widget.attachmentSection != null) ...[
              const SizedBox(height: 12),
              widget.attachmentSection!,
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.saveLocallyAction),
            ),
          ],
        ),
      ),
    );
  }

  List<QuickCategoryOption> get _categoriesForType => widget.categories
      .where(
        (category) =>
            category.type ==
            (_type == QuickTransactionType.income
                ? CategoryType.income
                : CategoryType.expense),
      )
      .toList(growable: false);

  List<QuickAccountOption> get _compatibleDestinations {
    final source = _account(_sourceId);
    if (source == null) return const [];
    return widget.accounts
        .where(
          (candidate) =>
              candidate.pocket.id != source.pocket.id &&
              candidate.pocket.currency == source.pocket.currency &&
              candidate.pocket.nature == source.pocket.nature,
        )
        .toList(growable: false);
  }

  void _ensureCompatibleDefaults() {
    if (_type == QuickTransactionType.transfer) {
      final destinations = _compatibleDestinations;
      _destinationId ??= destinations.isEmpty
          ? null
          : destinations.first.pocket.id.value;
    } else {
      final categories = _categoriesForType;
      _categoryId ??= categories.isEmpty ? null : categories.first.id.value;
    }
  }

  QuickAccountOption? _account(String? id) {
    if (id == null) return null;
    for (final account in widget.accounts) {
      if (account.pocket.id.value == id) return account;
    }
    return null;
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? AppLocalizations.of(context).requiredFieldMessage
      : null;

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null) {
      setState(
        () => _date = LocalDate(selected.year, selected.month, selected.day),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        QuickTransactionDraft(
          type: _type,
          amountText: _amount.text,
          sourcePocketId: EntityId.parse(_sourceId!),
          destinationPocketId: _destinationId == null
              ? null
              : EntityId.parse(_destinationId!),
          categoryId: _categoryId == null ? null : EntityId.parse(_categoryId!),
          date: _date,
          tagIds: _tagIds.map(EntityId.parse).toList(growable: false),
          title: _emptyToNull(_title.text),
          notes: _emptyToNull(_notes.text),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).transactionSavedMessage),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).transactionSaveFailedMessage,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
