import 'package:equis/application/sync/three_way_json_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const merger = ThreeWayJsonMerge();

  test('merges unrelated local and remote field changes', () {
    final result = merger.merge(
      base: const {
        'name': 'Old',
        'note': 'Base',
        'nested': {'a': 1, 'b': 2},
      },
      local: const {
        'name': 'Local',
        'note': 'Base',
        'nested': {'a': 1, 'b': 2},
      },
      remote: const {
        'name': 'Old',
        'note': 'Remote',
        'nested': {'a': 1, 'b': 3},
      },
    );

    expect(result, isA<ThreeWayMergeSuccess>());
    expect((result as ThreeWayMergeSuccess).value, {
      'name': 'Local',
      'note': 'Remote',
      'nested': {'a': 1, 'b': 3},
    });
  });

  test('preserves a same-field conflict instead of choosing a winner', () {
    final result = merger.merge(
      base: const {'amount_minor': 100, 'note': 'base'},
      local: const {'amount_minor': 200, 'note': 'base'},
      remote: const {'amount_minor': 300, 'note': 'base'},
    );

    expect(result, isA<ThreeWayMergeConflict>());
    expect((result as ThreeWayMergeConflict).paths, ['amount_minor']);
  });

  test('merges additions and deletions only when they are unambiguous', () {
    final merged =
        merger.merge(
              base: const {'kept': true, 'removed': 1},
              local: const {'kept': true},
              remote: const {'kept': true, 'removed': 1, 'added': 2},
            )
            as ThreeWayMergeSuccess;
    expect(merged.value, {'kept': true, 'added': 2});

    final conflict = merger.merge(
      base: const {'value': 1},
      local: const {},
      remote: const {'value': 2},
    );
    expect((conflict as ThreeWayMergeConflict).paths, ['value']);
  });
}
