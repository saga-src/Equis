import 'package:equis/infrastructure/settings/shared_preferences_locale_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('restores selected language after reopening preferences', () async {
    final first = await SharedPreferencesLocaleStore.create();
    await first.save(const Locale('pt', 'BR'));
    final restarted = await SharedPreferencesLocaleStore.create();
    expect(restarted.load(const Locale('en', 'US')), const Locale('pt', 'BR'));
    await restarted.save(const Locale('en', 'US'));
    expect(
      (await SharedPreferencesLocaleStore.create()).load(
        const Locale('pt', 'BR'),
      ),
      const Locale('en', 'US'),
    );
  });
  test(
    'falls back to supported system language only without a valid selection',
    () async {
      final store = await SharedPreferencesLocaleStore.create();
      expect(store.load(const Locale('pt', 'PT')), const Locale('pt', 'BR'));
      await store.preferences.setString(
        SharedPreferencesLocaleStore.preferenceKey,
        'bad',
      );
      expect(store.load(const Locale('fr', 'FR')), const Locale('en', 'US'));
    },
  );
}
