import 'dart:async';
import 'infrastructure/updates/app_update_service.dart';
import 'infrastructure/updates/update_installer.dart';
import 'presentation/settings/update_card.dart';
import 'l10n/app_localizations.dart';

import 'package:equis/app/equis_app.dart';
import 'package:equis/app/vault_workspace.dart';
import 'package:equis/app/workspace_host.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/providers/local_app_dependencies.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/app/theme/equis_theme_controller.dart';
import 'package:equis/core/logging/log_bootstrap.dart';
import 'package:equis/core/logging/privacy_safe_log_event.dart';
import 'package:equis/background/android_background_jobs.dart';
import 'package:equis/infrastructure/settings/shared_preferences_theme_store.dart';
import 'package:equis/infrastructure/settings/shared_preferences_locale_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never open/migrate a vault from a partially replaced portable installation.
  if (await UpdateInstaller.replacementInterrupted()) {
    runApp(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  AppLocalizations.of(context).updateRecoveryRequired,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final logBootstrap = await LogBootstrap.initialize();
  final logger = Logger('bootstrap');
  SharedPreferencesThemeStore? themeStore;
  var initialTheme = EquisThemeVariant.obsidian;
  try {
    themeStore = await SharedPreferencesThemeStore.create();
    initialTheme = await themeStore.load();
  } catch (_) {
    logger.warning(
      const PrivacySafeLogEvent(
        component: 'appearance',
        event: 'theme_preference_load_failed',
        attributes: {'error_code': 'local_preference_unavailable'},
      ),
    );
  }
  LocalAppDependencies? localDependencies;
  VaultWorkspace? workspace;
  try {
    workspace = await VaultWorkspace.open();
    localDependencies = workspace.active;
    await AndroidBackgroundJobs.initializeAndSchedule();
  } catch (_) {
    logger.severe(
      const PrivacySafeLogEvent(
        component: 'database',
        event: 'local_vault_open_failed',
        attributes: {'error_code': 'encrypted_database_initialization_failed'},
      ),
    );
  }

  FlutterError.onError = (details) {
    logger.severe(
      const PrivacySafeLogEvent(
        component: 'flutter',
        event: 'framework_error',
        attributes: {'error_code': 'unhandled_framework_error'},
      ),
    );
  };

  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  var supportedLocale = locale.languageCode == 'pt'
      ? const Locale('pt', 'BR')
      : const Locale('en', 'US');
  SharedPreferencesLocaleStore? localeStore;
  try {
    localeStore = await SharedPreferencesLocaleStore.create();
    supportedLocale = localeStore.load(locale);
  } catch (_) {
    // Retain the system language if preferences are temporarily unavailable.
  }
  final dependencies = localDependencies;
  final preferences = themeStore;
  AppUpdateService? updateService;
  try {
    updateService = await AppUpdateService.create(
      await UpdateInstaller.platform(),
    );
  } catch (_) {
    /* Updates never prevent offline access. */
  }
  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          overrides: [
            appUpdateServiceProvider.overrideWithValue(updateService),
            localeProvider.overrideWith((ref) => supportedLocale),
            localePreferenceStoreProvider.overrideWithValue(localeStore),
            themeVariantProvider.overrideWith(
              (ref) => EquisThemeController(
                initialTheme: initialTheme,
                preferenceStore: preferences,
              ),
            ),
            if (dependencies != null)
              localAppDependenciesProvider.overrideWithValue(dependencies),
          ],
          child: workspace == null
              ? const EquisApp()
              : WorkspaceHost(
                  workspace: workspace,
                  updateService: updateService,
                  initialLocale: supportedLocale,
                  initialTheme: initialTheme,
                  themeStore: preferences,
                  localeStore: localeStore,
                ),
        ),
      );
    },
    (error, stackTrace) {
      logger.severe(
        const PrivacySafeLogEvent(
          component: 'dart',
          event: 'uncaught_zone_error',
          attributes: {'error_code': 'unhandled_zone_error'},
        ),
      );
    },
  );

  WidgetsBinding.instance.addObserver(logBootstrap);
}
