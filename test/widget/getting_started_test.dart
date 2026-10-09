import 'package:equis/app/equis_app.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/application/services/getting_started_service.dart';
import 'package:equis/infrastructure/settings/shared_preferences_experience_store.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/guide/getting_started_screen.dart';
import 'package:equis/presentation/guide/welcome_screen.dart';
import 'package:equis/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final locale in [const Locale('pt', 'BR'), const Locale('en', 'US')]) {
    for (final width in [360.0, 1280.0]) {
      testWidgets(
        'welcome skip, restart and manual guide work with keyboard/large text: $locale $width',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final semantics = tester.ensureSemantics();
          try {
            final prefs = SharedPreferencesExperienceStore(
              await SharedPreferences.getInstance(),
              installationNamespace: '$locale-$width',
            );
            final router = GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (context, state) =>
                      const Scaffold(body: Text('Home fixture')),
                ),
                GoRoute(
                  path: '/welcome',
                  builder: (context, state) => const WelcomeScreen(),
                ),
                GoRoute(
                  path: '/guide',
                  builder: (context, state) => const GettingStartedScreen(),
                ),
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsScreen(),
                ),
                for (final route in [
                  '/accounts',
                  '/transactions/new',
                  '/cloud-account',
                  '/taxonomy',
                  '/recurring',
                  '/budgets',
                  '/portability',
                  '/vault-sync',
                ])
                  GoRoute(
                    path: route,
                    builder: (context, state) => Scaffold(body: Text(route)),
                  ),
              ],
            );
            addTearDown(router.dispose);
            Widget app(WelcomeGuideGate gate) => ProviderScope(
              overrides: [
                appRouterProvider.overrideWithValue(router),
                localeProvider.overrideWith((ref) => locale),
                welcomeGuideGateProvider.overrideWithValue(gate),
              ],
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: const EquisApp(),
              ),
            );
            await tester.pumpWidget(app(WelcomeGuideGate(prefs)));
            await tester.pumpAndSettle();
            expect(find.byType(WelcomeScreen), findsOneWidget);
            expect(await prefs.hasSeenGuide(), isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.ensureVisible(find.byKey(const Key('welcome-skip')));
            await tester.tap(find.byKey(const Key('welcome-skip')));
            await tester.pumpAndSettle();
            expect(find.text('Home fixture'), findsOneWidget);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(app(WelcomeGuideGate(prefs)));
            await tester.pumpAndSettle();
            expect(find.byType(WelcomeScreen), findsNothing);
            router.go('/settings');
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const Key('settings-getting-started')),
            );
            await tester.tap(find.byKey(const Key('settings-getting-started')));
            await tester.pumpAndSettle();
            expect(find.byType(GettingStartedScreen), findsOneWidget);
            final l10n = AppLocalizations.of(
              tester.element(find.byType(GettingStartedScreen)),
            );
            expect(find.text(l10n.guideVaultsBody), findsOneWidget);
            final open = find.text(l10n.createLocalVaultAction);
            await tester.ensureVisible(open);
            await tester.pumpAndSettle();
            await tester.tap(open);
            await tester.pumpAndSettle();
            expect(find.text('Home fixture'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
