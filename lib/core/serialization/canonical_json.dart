import 'dart:convert';

final class CanonicalJson {
  const CanonicalJson._();

  static String encode(Object? value) => _encode(value);

  static List<int> encodeUtf8(Object? value) => utf8.encode(encode(value));

  static String _encode(Object? value) {
    if (value == null || value is bool || value is int || value is String) {
      return jsonEncode(value);
    }
    if (value is double) {
      if (!value.isFinite) {
        throw ArgumentError.value(value, 'value', 'Must be finite.');
      }
      return jsonEncode(value);
    }
    if (value is List) return '[${value.map(_encode).join(',')}]';
    if (value is Map) {
      final keys = <String>[];
      for (final key in value.keys) {
        if (key is! String) {
          throw ArgumentError.value(key, 'key', 'JSON keys must be strings.');
        }
        keys.add(key);
      }
      keys.sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_encode(value[key])}').join(',')}}';
    }
    throw ArgumentError.value(
      value,
      'value',
      'Canonical JSON accepts only JSON-native values.',
    );
  }
}
