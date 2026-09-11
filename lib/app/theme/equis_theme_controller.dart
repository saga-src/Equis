import 'package:equis/app/theme/equis_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class EquisThemePreferenceStore {
  Future<EquisThemeVariant> load();

  Future<void> save(EquisThemeVariant variant);
}

final class EquisThemeController extends StateNotifier<EquisThemeVariant> {
  EquisThemeController({
    EquisThemeVariant initialTheme = EquisThemeVariant.obsidian,
    EquisThemePreferenceStore? preferenceStore,
  }) : _store = preferenceStore,
       super(initialTheme);

  final EquisThemePreferenceStore? _store;

  Future<void> select(EquisThemeVariant variant) async {
    if (state == variant) return;
    state = variant;
    await _store?.save(variant);
  }
}
