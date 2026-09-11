import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('financial intelligence has no network or cloud dependency', () {
    final files = <File>[
      ...Directory(
        'lib/domain/intelligence',
      ).listSync(recursive: true).whereType<File>(),
      File('lib/application/services/financial_intelligence_service.dart'),
      ...Directory(
        'lib/presentation/intelligence',
      ).listSync(recursive: true).whereType<File>(),
    ];
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains("package:http")));
    expect(source, isNot(contains('supabase')));
    expect(source, isNot(contains('openai')));
    expect(source, isNot(contains('dart:io')));
    expect(source, isNot(contains('WebSocket')));
  });
}
