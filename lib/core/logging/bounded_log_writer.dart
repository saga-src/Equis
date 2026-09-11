import 'dart:convert';
import 'dart:io';

/// Appends complete UTF-8 JSON Lines records without exceeding the configured
/// byte budget. Once exhausted, logging fails closed by dropping new records.
final class BoundedLogWriter {
  BoundedLogWriter(this._sink, {required int byteBudget})
    : _remainingBytes = byteBudget;

  final IOSink _sink;
  int _remainingBytes;

  int get remainingBytes => _remainingBytes;

  void writeLine(String line) {
    final bytes = utf8.encode('$line\n');
    if (bytes.length > _remainingBytes) return;
    _sink.add(bytes);
    _remainingBytes -= bytes.length;
  }

  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}
