import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

final class Tag {
  Tag({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.nameEnUs,
    this.namePtBr,
    this.color,
    this.deletedAt,
    this.revision = 1,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final String? nameEnUs;
  final String? namePtBr;
  final String? color;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  Tag withLocalizedNames({
    required String fallback,
    required String? enUs,
    required String? ptBr,
    required UtcInstant at,
  }) => Tag(
    id: id,
    vaultId: vaultId,
    name: fallback,
    nameEnUs: enUs,
    namePtBr: ptBr,
    color: color,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}
