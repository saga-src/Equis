import 'package:uuid/uuid.dart';

final class EntityId {
  factory EntityId.parse(String value) {
    final canonical = value.toLowerCase();
    if (!_isCanonicalUuidV7(canonical)) {
      throw FormatException('Entity identifier must be UUIDv7.', value);
    }
    return EntityId._(canonical);
  }

  EntityId.generate({Uuid? generator})
    : value = (generator ?? const Uuid()).v7().toLowerCase();

  const EntityId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is EntityId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

bool _isCanonicalUuidV7(String value) {
  if (value.length != 36 ||
      value.codeUnitAt(8) != 45 ||
      value.codeUnitAt(13) != 45 ||
      value.codeUnitAt(18) != 45 ||
      value.codeUnitAt(23) != 45 ||
      value.codeUnitAt(14) != 55) {
    return false;
  }
  final variant = value.codeUnitAt(19);
  if (variant != 56 && variant != 57 && variant != 97 && variant != 98) {
    return false;
  }
  for (var index = 0; index < value.length; index++) {
    if (index == 8 || index == 13 || index == 18 || index == 23) continue;
    final unit = value.codeUnitAt(index);
    final hexadecimal =
        (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102);
    if (!hexadecimal) return false;
  }
  return true;
}
