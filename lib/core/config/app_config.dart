final class AppConfig {
  const AppConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.localIntelligenceEnabled = true,
    this.economicSeriesReadEnabled = false,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      environment: String.fromEnvironment(
        'EQUIS_ENVIRONMENT',
        defaultValue: 'development',
      ),
      supabaseUrl: String.fromEnvironment('EQUIS_SUPABASE_URL'),
      supabaseAnonKey: String.fromEnvironment('EQUIS_SUPABASE_ANON_KEY'),
      localIntelligenceEnabled: bool.fromEnvironment(
        'EQUIS_LOCAL_INTELLIGENCE_ENABLED',
        defaultValue: true,
      ),
      economicSeriesReadEnabled: bool.fromEnvironment(
        'EQUIS_ECONOMIC_SERIES_READ_ENABLED',
        defaultValue: true,
      ),
    );
  }

  final String environment;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final bool localIntelligenceEnabled;
  final bool economicSeriesReadEnabled;

  bool get cloudConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
