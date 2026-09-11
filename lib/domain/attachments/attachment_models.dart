import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum AttachmentUploadState {
  local,
  pending,
  uploaded,
  failed;

  static AttachmentUploadState fromStorage(String value) => values.firstWhere(
    (state) => state.name == value,
    orElse: () =>
        throw const FormatException('Invalid attachment upload state.'),
  );
}

enum AttachmentEntityType {
  transaction('transaction'),
  account('account'),
  goal('goal'),
  asset('asset'),
  investmentInstrument('investment_instrument');

  const AttachmentEntityType(this.stored);

  final String stored;

  static AttachmentEntityType fromStorage(String value) => values.firstWhere(
    (type) => type.stored == value,
    orElse: () =>
        throw const FormatException('Invalid attachment entity type.'),
  );
}

final class AttachmentLinkDefinition {
  const AttachmentLinkDefinition({
    required this.entityType,
    required this.entityId,
  });

  final AttachmentEntityType entityType;
  final EntityId entityId;

  @override
  bool operator ==(Object other) =>
      other is AttachmentLinkDefinition &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);
}

final class AttachmentMetadata {
  AttachmentMetadata({
    required this.id,
    required this.vaultId,
    required this.originalFilename,
    required this.mimeType,
    required this.byteSize,
    required this.localPath,
    required this.sha256,
    required this.uploadState,
    required Iterable<AttachmentLinkDefinition> links,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : links = Set<AttachmentLinkDefinition>.unmodifiable(links) {
    if (originalFilename.trim().isEmpty ||
        originalFilename.length > 255 ||
        (mimeType != null &&
            (mimeType!.trim().isEmpty || mimeType!.length > 255)) ||
        byteSize < 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        revision < 1 ||
        links.isEmpty) {
      throw const AttachmentValidationException();
    }
  }

  final EntityId id;
  final EntityId vaultId;
  final String originalFilename;
  final String? mimeType;
  final int byteSize;
  final String? localPath;
  final String sha256;
  final AttachmentUploadState uploadState;
  final Set<AttachmentLinkDefinition> links;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  AttachmentMetadata copyWith({
    AttachmentUploadState? uploadState,
    int? revision,
    UtcInstant? updatedAt,
    UtcInstant? deletedAt,
  }) => AttachmentMetadata(
    id: id,
    vaultId: vaultId,
    originalFilename: originalFilename,
    mimeType: mimeType,
    byteSize: byteSize,
    localPath: localPath,
    sha256: sha256,
    uploadState: uploadState ?? this.uploadState,
    links: links,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

final class AttachmentValidationException implements Exception {
  const AttachmentValidationException();
}
