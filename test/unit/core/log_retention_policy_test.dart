import 'dart:convert';
import 'dart:io';

import 'package:equis/core/logging/bounded_log_writer.dart';
import 'package:equis/core/logging/log_retention_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('equis-logs-');
  });

  tearDown(() => temporary.delete(recursive: true));

  test('removes logs older than seven days and caps aggregate bytes', () async {
    final old = File('${temporary.path}${Platform.pathSeparator}old.jsonl');
    final newest = File(
      '${temporary.path}${Platform.pathSeparator}newest.jsonl',
    );
    final second = File(
      '${temporary.path}${Platform.pathSeparator}second.jsonl',
    );
    await old.writeAsBytes(List.filled(3, 1));
    await second.writeAsBytes(List.filled(6, 2));
    await newest.writeAsBytes(List.filled(6, 3));
    final now = DateTime.utc(2026, 8, 22, 12);
    await old.setLastModified(now.subtract(const Duration(days: 8)));
    await second.setLastModified(now.subtract(const Duration(hours: 2)));
    await newest.setLastModified(now.subtract(const Duration(hours: 1)));

    final retained = await const LogRetentionPolicy(
      maximumBytes: 10,
      maximumAge: Duration(days: 7),
    ).prepare(temporary, now: now);

    expect(retained, 6);
    expect(await newest.exists(), isTrue);
    expect(await second.exists(), isFalse);
    expect(await old.exists(), isFalse);
  });

  test(
    'writes only complete UTF-8 JSON Lines within its byte budget',
    () async {
      final file = File(
        '${temporary.path}${Platform.pathSeparator}equis.jsonl',
      );
      final writer = BoundedLogWriter(
        file.openWrite(),
        byteBudget: utf8.encode('{"event":"ok"}\n').length,
      );

      writer.writeLine('{"event":"ok"}');
      writer.writeLine('{"event":"must_be_dropped"}');
      await writer.close();

      expect(await file.readAsString(), '{"event":"ok"}\n');
      expect(await file.length(), lessThanOrEqualTo(15));
    },
  );
}
