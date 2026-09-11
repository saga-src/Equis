import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all supported ARB variants expose exactly the same messages', () {
    final files = [
      File('lib/l10n/app_en.arb'),
      File('lib/l10n/app_en_US.arb'),
      File('lib/l10n/app_pt.arb'),
      File('lib/l10n/app_pt_BR.arb'),
    ];
    Set<String>? expected;
    for (final file in files) {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final keys = json.keys.where((key) => !key.startsWith('@')).toSet();
      expected ??= keys;
      expect(keys, expected, reason: file.path);
      for (final key in keys) {
        expect(
          (json[key] as String).trim(),
          isNotEmpty,
          reason: '$key in ${file.path}',
        );
      }
    }
  });

  test('presentation source has no unapproved literal Text labels', () {
    final literals = <String>[];
    final pattern = RegExp(
      r'''Text\(\s*(?:const\s+)?['"]([^'$][^'"]*)['"]''',
      multiLine: true,
    );
    for (final file
        in Directory('lib/presentation')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        final value = match.group(1)!;
        if (!{'—', 'BRL', 'USD'}.contains(value)) {
          literals.add('${file.path}: $value');
        }
      }
      expect(
        source,
        isNot(contains('subtitle: Text(aggregate.account.nature.name)')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('Text(conflict.entityType.wireName)')),
        reason: file.path,
      );
    }
    expect(literals, isEmpty);
  });
}
