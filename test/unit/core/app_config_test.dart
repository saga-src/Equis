import 'package:equis/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud remains optional when configuration is absent', () {
    const config = AppConfig(
      environment: 'test',
      supabaseUrl: '',
      supabaseAnonKey: '',
    );

    expect(config.cloudConfigured, isFalse);
  });

  test(
    'local intelligence can be disabled independently of cloud and ledger',
    () {
      const config = AppConfig(
        environment: 'test',
        supabaseUrl: '',
        supabaseAnonKey: '',
        localIntelligenceEnabled: false,
      );

      expect(config.localIntelligenceEnabled, isFalse);
      expect(config.cloudConfigured, isFalse);
    },
  );
}
