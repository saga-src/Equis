import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/settings/update_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows recovery guidance when Windows registration is invalid', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(null),
          windowsUpdateRegistrationIssueProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: UpdateCard()),
        ),
      ),
    );

    expect(find.text('App updates'), findsOneWidget);
    expect(find.textContaining('registration does not match'), findsOneWidget);
    expect(find.textContaining('official installer'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
