import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/settings/portability_screen.dart';
import 'package:equis/presentation/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings exposes backup and export navigation', (tester) async {
    await tester.pumpWidget(_app(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('portability-settings')), findsOneWidget);
    expect(find.text('Backup and export'), findsOneWidget);
  });

  testWidgets('empty profile exposes restore but not backup creation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const PortabilityScreen()));
    await tester.pumpAndSettle();

    final restore = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Restore backup'),
    );
    final create = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Create encrypted backup'),
    );
    expect(restore.enabled, isTrue);
    expect(create.enabled, isFalse);
    expect(find.text('Export vault as JSON'), findsOneWidget);
    expect(find.text('Export transactions as CSV'), findsOneWidget);
  });
}

Widget _app(Widget child) => ProviderScope(
  overrides: [localeProvider.overrideWith((ref) => const Locale('en', 'US'))],
  child: MaterialApp(
    locale: const Locale('en', 'US'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);
