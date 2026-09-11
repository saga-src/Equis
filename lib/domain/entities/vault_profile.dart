import '../shared/currency.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

final class VaultProfile {
  VaultProfile({
    required this.id,
    required this.name,
    required this.baseCurrency,
    required this.locale,
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 1,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final String name;
  final CurrencyCode baseCurrency;
  final String locale;
  final String timezone;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;
  final int revision;

  VaultProfile revise({
    String? name,
    CurrencyCode? baseCurrency,
    String? locale,
    String? timezone,
    required UtcInstant at,
  }) => VaultProfile(
    id: id,
    name: name ?? this.name,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    locale: locale ?? this.locale,
    timezone: timezone ?? this.timezone,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
    revision: revision + 1,
  );
}
