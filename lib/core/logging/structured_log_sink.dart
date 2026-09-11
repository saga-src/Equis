import 'dart:convert';

import 'package:equis/core/logging/privacy_log_filter.dart';
import 'package:equis/core/logging/privacy_safe_log_event.dart';
import 'package:logging/logging.dart';

final class StructuredLogSink {
  StructuredLogSink(this._writeLine, [this._filter = const PrivacyLogFilter()]);

  final void Function(String line) _writeLine;
  final PrivacyLogFilter _filter;

  void handle(LogRecord record) {
    final event = record.object;
    if (event is! PrivacySafeLogEvent) {
      return;
    }

    _writeLine(
      jsonEncode({
        'timestamp': record.time.toUtc().toIso8601String(),
        'level': record.level.name.toLowerCase(),
        'component': _filter.sanitizeLabel(event.component),
        'event': _filter.sanitizeLabel(event.event),
        ..._filter.sanitize(event),
      }),
    );
  }
}
