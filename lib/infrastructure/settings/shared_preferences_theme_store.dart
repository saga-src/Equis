import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/app/theme/equis_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesThemeStore implements EquisThemePreferenceStore {
  SharedPreferencesThemeStore(this._preferences);

  static const preferenceKey = 'equis.appearance.theme.v1';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesThemeStore> create() async =>
      SharedPreferencesThemeStore(await SharedPreferences.getInstance());

  @override
  Future<EquisThemeVariant> load() async =>
      EquisThemeVariant.fromStorage(_preferences.getString(preferenceKey));

  @override
  Future<void> save(EquisThemeVariant variant) async {
    await _preferences.setString(preferenceKey, variant.storageValue);
  }
}
