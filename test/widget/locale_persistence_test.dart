import 'package:equis/app/equis_app.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/infrastructure/settings/shared_preferences_locale_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings language survives a fresh application scope', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferencesLocaleStore.create();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final first = ProviderContainer(
      overrides: [localePreferenceStoreProvider.overrideWithValue(store)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: first, child: const EquisApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('language-pt-BR')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-pt-BR')));
    await tester.pumpAndSettle();
    expect(
      store.preferences.getString(SharedPreferencesLocaleStore.preferenceKey),
      'pt-BR',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    final restarted = ProviderContainer(
      overrides: [
        localeProvider.overrideWith(
          (ref) => store.load(const Locale('en', 'US')),
        ),
        localePreferenceStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(restarted.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: restarted, child: const EquisApp()),
    );
    await tester.pumpAndSettle();
    expect(restarted.read(localeProvider), const Locale('pt', 'BR'));
    expect(tester.takeException(), isNull);
  });
}
