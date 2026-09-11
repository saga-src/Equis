import 'package:equis/infrastructure/persistence/database/local_database_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'database lifecycle seam has deterministic startup and shutdown',
    () async {
      final lifecycle = PendingEncryptedDatabaseLifecycle();
      expect(lifecycle.state, LocalDatabaseState.notInitialized);

      await lifecycle.initialize();
      expect(lifecycle.state, LocalDatabaseState.ready);

      await lifecycle.close();
      expect(lifecycle.state, LocalDatabaseState.closed);
    },
  );
}
