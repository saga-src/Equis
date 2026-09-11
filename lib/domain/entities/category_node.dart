import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum CategoryType { expense, income }

final class CategoryNode {
  CategoryNode({
    required this.id,
    required this.vaultId,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.systemKey,
    this.customName,
    this.customNameEnUs,
    this.customNamePtBr,
    this.archived = false,
    this.sortOrder = 0,
    this.deletedAt,
    this.revision = 1,
  }) {
    if (systemKey == null &&
        (customName == null || customName!.trim().isEmpty)) {
      throw ArgumentError('A category needs either systemKey or customName.');
    }
    if (parentId == id) throw ArgumentError('A category cannot parent itself.');
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final EntityId? parentId;
  final CategoryType type;
  final String? systemKey;
  final String? customName;
  final String? customNameEnUs;
  final String? customNamePtBr;
  final bool archived;
  final int sortOrder;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  CategoryNode revise({
    EntityId? parentId,
    String? customName,
    String? customNameEnUs,
    String? customNamePtBr,
    bool? archived,
    required UtcInstant at,
  }) => CategoryNode(
    id: id,
    vaultId: vaultId,
    parentId: parentId ?? this.parentId,
    type: type,
    systemKey: systemKey,
    customName: customName ?? this.customName,
    customNameEnUs: customNameEnUs ?? this.customNameEnUs,
    customNamePtBr: customNamePtBr ?? this.customNamePtBr,
    archived: archived ?? this.archived,
    sortOrder: sortOrder,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
  );

  CategoryNode reparent(EntityId? value, {required UtcInstant at}) =>
      CategoryNode(
        id: id,
        vaultId: vaultId,
        parentId: value,
        type: type,
        systemKey: systemKey,
        customName: customName,
        customNameEnUs: customNameEnUs,
        customNamePtBr: customNamePtBr,
        archived: archived,
        sortOrder: sortOrder,
        revision: revision + 1,
        createdAt: createdAt,
        updatedAt: at,
        deletedAt: deletedAt,
      );

  CategoryNode withLocalizedNames({
    required String fallback,
    required String? enUs,
    required String? ptBr,
    required UtcInstant at,
  }) => CategoryNode(
    id: id,
    vaultId: vaultId,
    parentId: parentId,
    type: type,
    systemKey: systemKey,
    customName: fallback,
    customNameEnUs: enUs,
    customNamePtBr: ptBr,
    archived: archived,
    sortOrder: sortOrder,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}
