import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum AccountNature { asset, liability }

enum AccountType {
  checking,
  savings,
  cash,
  creditCard('credit_card'),
  digitalWallet('digital_wallet'),
  investment,
  loan,
  mortgage,
  financing,
  otherAsset('other_asset'),
  otherLiability('other_liability'),
  custom;

  const AccountType([String? storageValue]) : storageValue = storageValue ?? '';

  final String storageValue;

  String get stored => storageValue.isEmpty ? name : storageValue;

  static AccountType fromStorage(String value) =>
      values.singleWhere((type) => type.stored == value);
}

final class AccountProfile {
  AccountProfile({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.type,
    required this.nature,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.includeInNetWorth = true,
    this.archived = false,
    this.openedOn,
    this.closedOn,
    this.sortOrder = 0,
    this.deletedAt,
    this.revision = 1,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final String? institution;
  final AccountType type;
  final AccountNature nature;
  final bool includeInNetWorth;
  final bool archived;
  final LocalDate? openedOn;
  final LocalDate? closedOn;
  final int sortOrder;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  AccountProfile revise({
    String? name,
    String? institution,
    bool? includeInNetWorth,
    bool? archived,
    LocalDate? closedOn,
    required UtcInstant at,
  }) => AccountProfile(
    id: id,
    vaultId: vaultId,
    name: name ?? this.name,
    institution: institution ?? this.institution,
    type: type,
    nature: nature,
    includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
    archived: archived ?? this.archived,
    openedOn: openedOn,
    closedOn: closedOn ?? this.closedOn,
    sortOrder: sortOrder,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}
