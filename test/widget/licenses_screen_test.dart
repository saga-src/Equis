import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/settings/licenses_screen.dart';
import 'package:equis/presentation/settings/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in [const Locale('en', 'US'), const Locale('pt', 'BR')]) {
    for (final width in [360.0, 1280.0]) {
      testWidgets(
        'Settings license overview and bundled font notice: $locale $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            ProviderScope(child: _app(locale, const SettingsScreen())),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('settings-licenses')),
            150,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.tap(find.byKey(const Key('settings-licenses')));
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(LicensesScreen)),
          );
          expect(find.text('Saga-SAL-1.0'), findsOneWidget);
          expect(find.text(l.licensesDependenciesTitle), findsOneWidget);
          await tester.tap(find.text(l.licensesFontsTitle));
          await tester.pumpAndSettle();
          for (final font in [
            'Inter',
            'JetBrains Mono',
            'Geist Sans',
            'Space Grotesk',
          ]) {
            expect(find.text(font), findsOneWidget);
          }
          // Cached asset futures cannot cross independent fake-async test zones.
          rootBundle.evict('assets/licenses/Inter-OFL-1.1.txt');
          await tester.tap(find.text('Inter'));
          await tester.pump();
          await tester.runAsync(() async {
            await rootBundle.loadString('assets/licenses/Inter-OFL-1.1.txt');
          });
          await tester.pumpAndSettle();
          expect(find.byType(SelectableText), findsOneWidget);
          expect(
            tester.widget<SelectableText>(find.byType(SelectableText)).data,
            contains('SIL OPEN FONT LICENSE'),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'dependency search preserves complete notice and retry: $locale',
      (tester) async {
        var attempts = 0;
        await tester.pumpWidget(
          _app(
            locale,
            DependencyLicensesScreen(
              load: () async {
                if (attempts++ == 0) throw StateError('Registry failed');
                return {
                  'flutter': [
                    LicenseEntryWithLineBreaks([
                      'flutter',
                    ], 'Copyright Flutter\n\nComplete license text'),
                  ],
                  'sqlite3': [
                    LicenseEntryWithLineBreaks(['sqlite3'], 'SQLite notice'),
                  ],
                };
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(DependencyLicensesScreen)),
        );
        await tester.tap(find.text(l.budgetRetryAction));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'FLUT');
        await tester.pumpAndSettle();
        expect(find.text('flutter'), findsOneWidget);
        expect(find.text('sqlite3'), findsNothing);
        await tester.tap(find.text('flutter'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText)).data,
          'Copyright Flutter\n\nComplete license text',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _app(Locale locale, Widget home) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
    child: child!,
  ),
  home: home,
);
