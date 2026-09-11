import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release source contains no administrative key or private-key material',
    () {
      final roots = ['lib', 'android', 'windows'];
      final source = roots
          .expand(
            (root) =>
                Directory(root).listSync(recursive: true).whereType<File>(),
          )
          .where(
            (file) => const {
              '.dart',
              '.kt',
              '.kts',
              '.xml',
              '.cpp',
              '.h',
            }.any(file.path.endsWith),
          )
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(source.toLowerCase(), isNot(contains('service_role')));
      expect(source, isNot(contains('BEGIN PRIVATE KEY')));
      expect(source, isNot(contains('BEGIN RSA PRIVATE KEY')));
      expect(source, isNot(contains('BEGIN OPENSSH PRIVATE KEY')));
    },
  );

  test('production logging has no arbitrary print or debug path', () {
    final dart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(RegExp(r'\bprint\s*\(').hasMatch(dart), isFalse);
    expect(RegExp(r'\bdebugPrint\s*\(').hasMatch(dart), isFalse);
    expect(RegExp(r'\bdeveloper\.log\s*\(').hasMatch(dart), isFalse);
    expect(
      RegExp(r'Logger\s*\(').allMatches(dart),
      hasLength(1),
      reason:
          'Logger construction stays centralized at the bootstrap boundary.',
    );
  });

  test('logging source declares JSONL, ten MiB, and seven-day caps', () {
    final bootstrap = File(
      'lib/core/logging/log_bootstrap.dart',
    ).readAsStringSync();
    final sink = File(
      'lib/core/logging/structured_log_sink.dart',
    ).readAsStringSync();

    expect(bootstrap, contains('10 * 1024 * 1024'));
    expect(bootstrap, contains('Duration(days: 7)'));
    expect(bootstrap, contains('equis.jsonl'));
    expect(sink, contains('jsonEncode'));
    expect(sink, contains('PrivacySafeLogEvent'));
  });
}
