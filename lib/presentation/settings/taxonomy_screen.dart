import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/formatting/taxonomy_labels.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TaxonomyScreen extends ConsumerWidget {
  const TaxonomyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(localFinanceControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageCategoriesTagsAction)),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text(l10n.localVaultErrorMessage)),
        data: (snapshot) {
          if (snapshot?.vault == null) {
            return Center(child: Text(l10n.setupRequiredMessage));
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _SectionHeader(
                title: l10n.categoriesTitle,
                actionLabel: l10n.addCategoryAction,
                onPressed: () =>
                    _addCategory(context, ref, snapshot!.categories),
              ),
              const SizedBox(height: 8),
              _CategoryGroup(
                title: l10n.expenseCategoriesTitle,
                rows: _hierarchy(snapshot!.categories, CategoryType.expense),
              ),
              const SizedBox(height: 12),
              _CategoryGroup(
                title: l10n.incomeCategoriesTitle,
                rows: _hierarchy(snapshot.categories, CategoryType.income),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: l10n.tagsTitle,
                actionLabel: l10n.addTagAction,
                onPressed: () => _addTag(context, ref),
              ),
              const SizedBox(height: 8),
              EquisGlassCard(
                child: snapshot.tags.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.noTagsMessage),
                      )
                    : Column(
                        children: [
                          for (final tag in snapshot.tags)
                            ListTile(
                              leading: const Icon(Icons.sell_outlined),
                              title: Text(tagLabel(context, tag)),
                              trailing: IconButton(
                                tooltip: l10n.editTranslationsAction,
                                icon: const Icon(Icons.translate_outlined),
                                onPressed: () => _editTag(context, ref, tag),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addCategory(
    BuildContext context,
    WidgetRef ref,
    List<CategoryNode> categories,
  ) async {
    final result = await showDialog<_NewCategory>(
      context: context,
      builder: (_) => _CategoryDialog(categories: categories),
    );
    if (result != null) {
      await ref
          .read(localFinanceControllerProvider.notifier)
          .createCategory(
            type: result.type,
            name: result.name,
            nameEnUs: result.nameEnUs,
            namePtBr: result.namePtBr,
            parentId: result.parentId,
          );
    }
  }

  Future<void> _addTag(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_LocalizedNames>(
      context: context,
      builder: (_) => const _LocalizedNamesDialog(isTag: true),
    );
    if (result != null) {
      await ref
          .read(localFinanceControllerProvider.notifier)
          .createTag(
            name: result.fallback,
            nameEnUs: result.enUs,
            namePtBr: result.ptBr,
          );
    }
  }

  Future<void> _editTag(BuildContext context, WidgetRef ref, Tag tag) async {
    final result = await showDialog<_LocalizedNames>(
      context: context,
      builder: (_) => _LocalizedNamesDialog(
        isTag: true,
        initial: _LocalizedNames(
          fallback: tag.name,
          enUs: tag.nameEnUs,
          ptBr: tag.namePtBr,
        ),
      ),
    );
    if (result != null) {
      await ref
          .read(localFinanceControllerProvider.notifier)
          .updateTagNames(
            tag: tag,
            name: result.fallback,
            nameEnUs: result.enUs,
            namePtBr: result.ptBr,
          );
    }
  }

  static Future<void> editCategory(
    BuildContext context,
    WidgetRef ref,
    CategoryNode category,
  ) async {
    final result = await showDialog<_LocalizedNames>(
      context: context,
      builder: (_) => _LocalizedNamesDialog(
        isTag: false,
        initial: _LocalizedNames(
          fallback: category.customName ?? '',
          enUs: category.customNameEnUs,
          ptBr: category.customNamePtBr,
        ),
      ),
    );
    if (result != null) {
      await ref
          .read(localFinanceControllerProvider.notifier)
          .updateCategoryNames(
            category: category,
            name: result.fallback,
            nameEnUs: result.enUs,
            namePtBr: result.ptBr,
          );
    }
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.categories});
  final List<CategoryNode> categories;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _name = TextEditingController();
  final _nameEnUs = TextEditingController();
  final _namePtBr = TextEditingController();
  CategoryType _type = CategoryType.expense;
  EntityId? _parentId;

  @override
  void dispose() {
    _name.dispose();
    _nameEnUs.dispose();
    _namePtBr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parents = widget.categories
        .where((category) => category.type == _type)
        .toList();
    return AlertDialog(
      title: Text(l10n.addCategoryAction),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LocalizedNameFields(
                fallback: _name,
                enUs: _nameEnUs,
                ptBr: _namePtBr,
                fallbackLabel: l10n.categoryNameLabel,
              ),
              const SizedBox(height: 12),
              SegmentedButton<CategoryType>(
                segments: [
                  ButtonSegment(
                    value: CategoryType.expense,
                    label: Text(l10n.expenseTypeLabel),
                  ),
                  ButtonSegment(
                    value: CategoryType.income,
                    label: Text(l10n.incomeTypeLabel),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (value) => setState(() {
                  _type = value.single;
                  _parentId = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(_type),
                initialValue: _parentId?.value,
                decoration: InputDecoration(
                  labelText: l10n.parentCategoryLabel,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.noParentLabel),
                  ),
                  for (final parent in parents)
                    DropdownMenuItem(
                      value: parent.id.value,
                      child: Text(categoryLabel(context, parent)),
                    ),
                ],
                onChanged: (value) => setState(
                  () =>
                      _parentId = value == null ? null : EntityId.parse(value),
                ),
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
          onPressed: () {
            final value = _name.text.trim();
            if (value.isNotEmpty) {
              Navigator.pop(
                context,
                _NewCategory(
                  name: value,
                  nameEnUs: _optionalText(_nameEnUs),
                  namePtBr: _optionalText(_namePtBr),
                  type: _type,
                  parentId: _parentId,
                ),
              );
            }
          },
          child: Text(l10n.addCategoryAction),
        ),
      ],
    );
  }
}

class _LocalizedNamesDialog extends StatefulWidget {
  const _LocalizedNamesDialog({required this.isTag, this.initial});
  final bool isTag;
  final _LocalizedNames? initial;

  @override
  State<_LocalizedNamesDialog> createState() => _LocalizedNamesDialogState();
}

class _LocalizedNamesDialogState extends State<_LocalizedNamesDialog> {
  late final TextEditingController _fallback;
  late final TextEditingController _enUs;
  late final TextEditingController _ptBr;

  @override
  void initState() {
    super.initState();
    _fallback = TextEditingController(text: widget.initial?.fallback);
    _enUs = TextEditingController(text: widget.initial?.enUs);
    _ptBr = TextEditingController(text: widget.initial?.ptBr);
  }

  @override
  void dispose() {
    _fallback.dispose();
    _enUs.dispose();
    _ptBr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(
        editing
            ? l10n.editTranslationsAction
            : widget.isTag
            ? l10n.addTagAction
            : l10n.addCategoryAction,
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: _LocalizedNameFields(
            fallback: _fallback,
            enUs: _enUs,
            ptBr: _ptBr,
            fallbackLabel: widget.isTag
                ? l10n.tagNameLabel
                : l10n.categoryNameLabel,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: () {
            final fallback = _fallback.text.trim();
            if (fallback.isNotEmpty) {
              Navigator.pop(
                context,
                _LocalizedNames(
                  fallback: fallback,
                  enUs: _optionalText(_enUs),
                  ptBr: _optionalText(_ptBr),
                ),
              );
            }
          },
          child: Text(
            editing
                ? l10n.saveAction
                : widget.isTag
                ? l10n.addTagAction
                : l10n.addCategoryAction,
          ),
        ),
      ],
    );
  }
}

class _LocalizedNameFields extends StatelessWidget {
  const _LocalizedNameFields({
    required this.fallback,
    required this.enUs,
    required this.ptBr,
    required this.fallbackLabel,
  });
  final TextEditingController fallback;
  final TextEditingController enUs;
  final TextEditingController ptBr;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: fallback,
          autofocus: true,
          decoration: InputDecoration(labelText: fallbackLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: enUs,
          decoration: InputDecoration(labelText: l10n.englishNameLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: ptBr,
          decoration: InputDecoration(labelText: l10n.portugueseNameLabel),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.localizedNamesHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String? _optionalText(TextEditingController controller) {
  final value = controller.text.trim();
  return value.isEmpty ? null : value;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
  });
  final String title;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: Text(actionLabel),
      ),
    ],
  );
}

class _CategoryGroup extends ConsumerWidget {
  const _CategoryGroup({required this.title, required this.rows});
  final String title;
  final List<_CategoryRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return EquisGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.only(
                left: 16 + row.depth * 24,
                right: 8,
              ),
              leading: Icon(
                row.node.systemKey == null
                    ? Icons.folder_outlined
                    : Icons.lock_outline,
              ),
              title: Text(categoryLabel(context, row.node)),
              subtitle: row.node.systemKey == null
                  ? null
                  : Text(l10n.systemCategoryLabel),
              trailing: row.node.systemKey != null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.editTranslationsAction,
                          icon: const Icon(Icons.translate_outlined),
                          onPressed: () => TaxonomyScreen.editCategory(
                            context,
                            ref,
                            row.node,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.archiveCategoryAction,
                          icon: const Icon(Icons.archive_outlined),
                          onPressed: () async {
                            try {
                              await ref
                                  .read(localFinanceControllerProvider.notifier)
                                  .archiveCategory(row.node);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.categoryArchiveFailedMessage,
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

final class _NewCategory {
  const _NewCategory({
    required this.name,
    required this.type,
    this.nameEnUs,
    this.namePtBr,
    this.parentId,
  });
  final String name;
  final String? nameEnUs;
  final String? namePtBr;
  final CategoryType type;
  final EntityId? parentId;
}

final class _LocalizedNames {
  const _LocalizedNames({required this.fallback, this.enUs, this.ptBr});
  final String fallback;
  final String? enUs;
  final String? ptBr;
}

final class _CategoryRow {
  const _CategoryRow(this.node, this.depth);
  final CategoryNode node;
  final int depth;
}

List<_CategoryRow> _hierarchy(
  List<CategoryNode> categories,
  CategoryType type,
) {
  final nodes = categories.where((node) => node.type == type).toList();
  final ids = nodes.map((node) => node.id).toSet();
  final children = <EntityId, List<CategoryNode>>{};
  final roots = <CategoryNode>[];
  for (final node in nodes) {
    if (node.parentId == null || !ids.contains(node.parentId)) {
      roots.add(node);
    } else {
      children.putIfAbsent(node.parentId!, () => []).add(node);
    }
  }
  final result = <_CategoryRow>[];
  void visit(CategoryNode node, int depth) {
    result.add(_CategoryRow(node, depth));
    for (final child in children[node.id] ?? const <CategoryNode>[]) {
      visit(child, depth + 1);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return result;
}
