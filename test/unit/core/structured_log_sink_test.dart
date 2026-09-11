import 'dart:convert';

import 'package:equis/core/logging/privacy_safe_log_event.dart';
import 'package:equis/core/logging/structured_log_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  test('writes only allow-listed metadata and redacts identifiers', () {
    final lines = <String>[];
    final sink = StructuredLogSink(lines.add);
    final record = LogRecord(
      Level.WARNING,
      'sync_retry',
      'test',
      null,
      null,
      null,
      const PrivacySafeLogEvent(
        component: 'sync',
        event: 'sync_retry',
        attributes: {
          'record_id': '019c3e73-7ec8-7b41-a8ad-9a41498dd476',
          'attempt': 3,
          'merchant': 'must-not-be-logged',
          'amount_minor': 12500,
        },
      ),
    );

    sink.handle(record);

    final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(decoded['event'], 'sync_retry');
    expect(decoded['attempt'], 3);
    expect(decoded['record_id'], '…498dd476');
    expect(decoded, isNot(contains('merchant')));
    expect(decoded, isNot(contains('amount_minor')));
  });

  test('drops arbitrary log messages', () {
    final lines = <String>[];
    final sink = StructuredLogSink(lines.add);

    sink.handle(LogRecord(Level.INFO, 'potentially sensitive text', 'test'));

    expect(lines, isEmpty);
  });

  test('redacts secret-shaped labels even in allow-listed positions', () {
    final lines = <String>[];
    final sink = StructuredLogSink(lines.add);
    const recovery =
        'equis-recovery-v1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.signature-material';

    sink.handle(
      LogRecord(
        Level.SEVERE,
        'ignored',
        'test',
        null,
        null,
        null,
        const PrivacySafeLogEvent(
          component: jwt,
          event: recovery,
          attributes: {
            'operation': recovery,
            'error_code': jwt,
            'password': 'must-never-appear',
            'encryption_key': 'must-never-appear-either',
          },
        ),
      ),
    );

    expect(lines.single, isNot(contains(recovery)));
    expect(lines.single, isNot(contains(jwt)));
    expect(lines.single, isNot(contains('must-never-appear')));
    final decoded = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(decoded['component'], 'redacted');
    expect(decoded['event'], 'redacted');
    expect(decoded['operation'], 'redacted');
    expect(decoded['error_code'], 'redacted');
  });
}
