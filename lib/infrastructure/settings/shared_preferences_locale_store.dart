import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesLocaleStore {
  const SharedPreferencesLocaleStore(this.preferences);
  static const preferenceKey = 'equis.appearance.locale';
  final SharedPreferences preferences;

  static Future<SharedPreferencesLocaleStore> create() async =>
      SharedPreferencesLocaleStore(await SharedPreferences.getInstance());

  Locale load(Locale systemLocale) =>
      switch (preferences.getString(preferenceKey)) {
        'pt-BR' => const Locale('pt', 'BR'),
        'en-US' => const Locale('en', 'US'),
        _ =>
          systemLocale.languageCode == 'pt'
              ? const Locale('pt', 'BR')
              : const Locale('en', 'US'),
      };

  Future<void> save(Locale locale) async {
    final saved = await preferences.setString(
      preferenceKey,
      locale.languageCode == 'pt' ? 'pt-BR' : 'en-US',
    );
    if (!saved) throw StateError('Locale preference could not be saved');
  }
}
