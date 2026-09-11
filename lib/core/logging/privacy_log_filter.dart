import 'package:equis/core/logging/privacy_safe_log_event.dart';

final class PrivacyLogFilter {
  const PrivacyLogFilter();

  static final _safeLabelPattern = RegExp(r'^[a-z][a-z0-9_.:-]{0,47}$');
  static final _sensitiveShape = RegExp(
    r'(^equis-recovery-|^eyJ[a-zA-Z0-9_-]+\.|^[a-fA-F0-9]{48,}$)',
  );

  static const allowedAttributeKeys = {
    'attempt',
    'correlation_id',
    'duration_ms',
    'entity_type',
    'error_code',
    'operation',
    'record_id',
    'revision',
    'sync_state',
  };

  Map<String, Object?> sanitize(PrivacySafeLogEvent event) {
    final sanitized = <String, Object?>{};
    for (final entry in event.attributes.entries) {
      if (!allowedAttributeKeys.contains(entry.key)) {
        continue;
      }
      sanitized[entry.key] = switch (entry.key) {
        'record_id' || 'correlation_id' => _redactIdentifier(entry.value),
        'attempt' ||
        'duration_ms' ||
        'revision' => entry.value is num ? entry.value : 'redacted',
        _ => _safeScalar(entry.value),
      };
    }
    return sanitized;
  }

  Object? _safeScalar(Object? value) {
    if (value == null || value is bool || value is num) {
      return value;
    }
    final text = value.toString();
    return sanitizeLabel(text);
  }

  String sanitizeLabel(String value) {
    if (!_safeLabelPattern.hasMatch(value) || _sensitiveShape.hasMatch(value)) {
      return 'redacted';
    }
    return value;
  }

  String _redactIdentifier(Object? value) {
    final text = value?.toString() ?? '';
    if (text.length <= 8) {
      return 'redacted';
    }
    return '…${text.substring(text.length - 8)}';
  }
}
