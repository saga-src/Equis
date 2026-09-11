import 'dart:io';

/// Enforces both the age and aggregate disk budget for privacy-safe log files.
final class LogRetentionPolicy {
  const LogRetentionPolicy({
    required this.maximumBytes,
    required this.maximumAge,
  });

  final int maximumBytes;
  final Duration maximumAge;

  Future<int> prepare(Directory directory, {DateTime? now}) async {
    final threshold = (now ?? DateTime.now()).subtract(maximumAge);
    final files = <({File file, FileStat stat})>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(threshold)) {
        await entity.delete();
      } else {
        files.add((file: entity, stat: stat));
      }
    }
    files.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    var retainedBytes = 0;
    for (final item in files) {
      if (item.stat.size > maximumBytes - retainedBytes) {
        await item.file.delete();
      } else {
        retainedBytes += item.stat.size;
      }
    }
    return retainedBytes;
  }
}
