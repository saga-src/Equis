import 'dart:convert';

sealed class ThreeWayMergeResult {
  const ThreeWayMergeResult();
}

final class ThreeWayMergeSuccess extends ThreeWayMergeResult {
  const ThreeWayMergeSuccess(this.value);
  final Map<String, Object?> value;
}

final class ThreeWayMergeConflict extends ThreeWayMergeResult {
  ThreeWayMergeConflict(Iterable<String> paths)
    : paths = List<String>.unmodifiable(paths);
  final List<String> paths;
}

final class ThreeWayJsonMerge {
  const ThreeWayJsonMerge();

  ThreeWayMergeResult merge({
    required Map<String, Object?> base,
    required Map<String, Object?> local,
    required Map<String, Object?> remote,
  }) {
    final conflicts = <String>[];
    final value = _mergeMaps(base, local, remote, '', conflicts);
    return conflicts.isEmpty
        ? ThreeWayMergeSuccess(value)
        : ThreeWayMergeConflict(conflicts);
  }

  Map<String, Object?> _mergeMaps(
    Map<String, Object?> base,
    Map<String, Object?> local,
    Map<String, Object?> remote,
    String prefix,
    List<String> conflicts,
  ) {
    final output = <String, Object?>{};
    final keys = {...base.keys, ...local.keys, ...remote.keys}.toList()..sort();
    for (final key in keys) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final baseValue = base.containsKey(key) ? base[key] : _absent;
      final localValue = local.containsKey(key) ? local[key] : _absent;
      final remoteValue = remote.containsKey(key) ? remote[key] : _absent;
      final selected = _mergeValue(
        baseValue,
        localValue,
        remoteValue,
        path,
        conflicts,
      );
      if (!identical(selected, _absent)) output[key] = selected;
    }
    return output;
  }

  Object? _mergeValue(
    Object? base,
    Object? local,
    Object? remote,
    String path,
    List<String> conflicts,
  ) {
    if (_equal(local, remote)) return local;
    if (_equal(local, base)) return remote;
    if (_equal(remote, base)) return local;
    if (base is Map<String, Object?> &&
        local is Map<String, Object?> &&
        remote is Map<String, Object?>) {
      return _mergeMaps(base, local, remote, path, conflicts);
    }
    conflicts.add(path);
    return local;
  }

  bool _equal(Object? left, Object? right) {
    if (identical(left, _absent) || identical(right, _absent)) {
      return identical(left, right);
    }
    return jsonEncode(left) == jsonEncode(right);
  }
}

const _absent = _Absent();

final class _Absent {
  const _Absent();
}
