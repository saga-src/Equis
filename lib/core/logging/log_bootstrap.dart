import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:equis/core/logging/structured_log_sink.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'bounded_log_writer.dart';
import 'log_retention_policy.dart';

final class LogBootstrap extends WidgetsBindingObserver {
  LogBootstrap._(this._subscription, this._writer);

  static const _maximumBytes = 10 * 1024 * 1024;
  static const _maximumAge = Duration(days: 7);
  static const _retention = LogRetentionPolicy(
    maximumBytes: _maximumBytes,
    maximumAge: _maximumAge,
  );

  final StreamSubscription<LogRecord> _subscription;
  final BoundedLogWriter _writer;

  static Future<LogBootstrap> initialize() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final logDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}logs',
    );
    await logDirectory.create(recursive: true);
    final retainedBytes = await _retention.prepare(logDirectory);

    final logFile = File(
      '${logDirectory.path}${Platform.pathSeparator}equis.jsonl',
    );
    final fileSink = logFile.openWrite(mode: FileMode.append, encoding: utf8);
    final writer = BoundedLogWriter(
      fileSink,
      byteBudget: _maximumBytes - retainedBytes,
    );
    final structuredSink = StructuredLogSink(writer.writeLine);
    Logger.root.level = Level.INFO;
    final subscription = Logger.root.onRecord.listen(structuredSink.handle);
    return LogBootstrap._(subscription, writer);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _writer.close();
  }
}
