import 'package:equis/core/config/app_config.dart';
import 'package:equis/infrastructure/persistence/database/local_database_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local lifecycle does not require cloud configuration', () async {
    const config = AppConfig(
      environment: 'test',
      supabaseUrl: '',
      supabaseAnonKey: '',
    );
    final lifecycle = PendingEncryptedDatabaseLifecycle();

    expect(config.cloudConfigured, isFalse);
    await lifecycle.initialize();
    expect(lifecycle.state, LocalDatabaseState.ready);
  });
}
