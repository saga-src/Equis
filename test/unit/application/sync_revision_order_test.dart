import 'package:equis/application/sync/sync_revision_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int compare(
    int a,
    int b,
    Map<String, Object?> local,
    Map<String, Object?> remote,
  ) => compareSyncRevisions(
    localRevision: a,
    remoteRevision: b,
    local: local,
    remote: remote,
  );

  test('revision priority is independent of device clock', () {
    expect(
      compare(7, 6, {'updated_at': 1}, {'updated_at': 999}),
      greaterThan(0),
    );
    expect(compare(6, 7, {'updated_at': 999}, {'updated_at': 1}), lessThan(0));
  });
  test(
    'equal revisions use edit time and an orientation-independent tie break',
    () {
      expect(
        compare(
          7,
          7,
          {
            'root': {'updated_at': 200},
          },
          {
            'root': {'updated_at': 100},
          },
        ),
        greaterThan(0),
      );
      const a = {
        'root': {'updated_at': 200, 'name': 'A'},
      };
      const b = {
        'root': {'name': 'B', 'updated_at': 200},
      };
      expect(compare(7, 7, a, b).sign, -compare(7, 7, b, a).sign);
      expect(compare(7, 7, a, a), 0);
      expect(
        compare(7, 7, a, {
          'root': {'name': 'A', 'updated_at': 200},
        }),
        0,
      );
    },
  );
}
