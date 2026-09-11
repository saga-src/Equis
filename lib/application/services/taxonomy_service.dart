import '../ports/foundational_repositories.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/taxonomy/tag.dart';

final class TaxonomyService {
  const TaxonomyService({required this.categories, required this.tags});

  final CategoryRepository categories;
  final TagRepository tags;

  Future<void> seedDefaults(EntityId vaultId, UtcInstant now) async {
    for (final template in _defaultCategories) {
      await categories.save(
        CategoryNode(
          id: EntityId.parse(template.id),
          vaultId: vaultId,
          parentId: template.parentId == null
              ? null
              : EntityId.parse(template.parentId!),
          type: template.type,
          systemKey: template.key,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<CategoryNode> createCategory({
    required EntityId vaultId,
    required CategoryType type,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
    EntityId? parentId,
  }) async {
    if (parentId != null) {
      final parent = await categories.find(parentId);
      if (parent == null || parent.vaultId != vaultId || parent.type != type) {
        throw StateError(
          'Parent category must exist in the same vault and type.',
        );
      }
    }
    final category = CategoryNode(
      id: EntityId.generate(),
      vaultId: vaultId,
      parentId: parentId,
      type: type,
      customName: name,
      customNameEnUs: _optional(nameEnUs),
      customNamePtBr: _optional(namePtBr),
      createdAt: now,
      updatedAt: now,
    );
    await categories.save(category);
    return category;
  }

  Future<void> validateReparent(
    CategoryNode category,
    EntityId? newParentId,
  ) async {
    if (newParentId == null) return;
    final all = await categories.listForVault(category.vaultId);
    final byId = {for (final node in all) node.id: node};
    var cursor = newParentId;
    final visited = <EntityId>{};
    while (true) {
      if (cursor == category.id) {
        throw StateError('Category hierarchy cycle detected.');
      }
      if (!visited.add(cursor)) {
        throw StateError('Existing category hierarchy contains a cycle.');
      }
      final parent = byId[cursor];
      if (parent == null) throw StateError('Parent category does not exist.');
      if (parent.type != category.type) {
        throw StateError('Parent category type must match.');
      }
      if (parent.parentId == null) return;
      cursor = parent.parentId!;
    }
  }

  Future<CategoryNode> reparentCategory(
    CategoryNode category,
    EntityId? newParentId, {
    required UtcInstant now,
  }) async {
    await validateReparent(category, newParentId);
    final revised = category.reparent(newParentId, at: now);
    await categories.save(revised);
    return revised;
  }

  Future<CategoryNode> archiveUserCategory(
    CategoryNode category, {
    required UtcInstant now,
  }) async {
    if (category.systemKey != null) {
      throw StateError('System categories cannot be archived.');
    }
    final all = await categories.listForVault(category.vaultId);
    if (all.any(
      (candidate) =>
          candidate.parentId == category.id &&
          !candidate.archived &&
          candidate.deletedAt == null,
    )) {
      throw StateError('Archive child categories first.');
    }
    final revised = category.revise(archived: true, at: now);
    await categories.save(revised);
    return revised;
  }

  Future<Tag> createTag({
    required EntityId vaultId,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
    String? color,
  }) async {
    final tag = Tag(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: name,
      nameEnUs: _optional(nameEnUs),
      namePtBr: _optional(namePtBr),
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await tags.save(tag);
    return tag;
  }

  Future<CategoryNode> updateCategoryNames({
    required CategoryNode category,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
  }) async {
    if (category.systemKey != null) {
      throw StateError('System category names cannot be changed.');
    }
    final revised = category.withLocalizedNames(
      fallback: name.trim(),
      enUs: _optional(nameEnUs),
      ptBr: _optional(namePtBr),
      at: now,
    );
    await categories.save(revised);
    return revised;
  }

  Future<Tag> updateTagNames({
    required Tag tag,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
  }) async {
    final revised = tag.withLocalizedNames(
      fallback: name.trim(),
      enUs: _optional(nameEnUs),
      ptBr: _optional(namePtBr),
      at: now,
    );
    await tags.save(revised);
    return revised;
  }
}

String? _optional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

final class _CategoryTemplate {
  const _CategoryTemplate(this.id, this.key, this.type, [this.parentId]);
  final String id;
  final String key;
  final CategoryType type;
  final String? parentId;
}

const _expenseRootId = '01900000-0000-7000-8000-000000000001';
const _incomeRootId = '01900000-0000-7000-8000-000000000002';

const _defaultCategories = <_CategoryTemplate>[
  _CategoryTemplate(_expenseRootId, 'category.expenses', CategoryType.expense),
  _CategoryTemplate(_incomeRootId, 'category.income', CategoryType.income),
  _CategoryTemplate(
    '01900000-0000-7000-8000-000000000003',
    'category.food',
    CategoryType.expense,
    _expenseRootId,
  ),
  _CategoryTemplate(
    '01900000-0000-7000-8000-000000000004',
    'category.housing',
    CategoryType.expense,
    _expenseRootId,
  ),
  _CategoryTemplate(
    '01900000-0000-7000-8000-000000000005',
    'category.transport',
    CategoryType.expense,
    _expenseRootId,
  ),
  _CategoryTemplate(
    '01900000-0000-7000-8000-000000000006',
    'category.salary',
    CategoryType.income,
    _incomeRootId,
  ),
  _CategoryTemplate(
    '01900000-0000-7000-8000-000000000007',
    'category.other_income',
    CategoryType.income,
    _incomeRootId,
  ),
];
