import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/app/theme/equis_theme_controller.dart';
import 'package:equis/infrastructure/settings/shared_preferences_theme_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('theme variants preserve approved palettes and legacy behavior', () {
    final obsidian = EquisTheme.obsidian;
    final light = EquisTheme.trueLight;
    final legacy = EquisTheme.legacy;

    expect(obsidian.canvasColor, EquisColors.voidBackground);
    expect(obsidian.colorScheme.surface, EquisColors.voidElevatedSurface);
    expect(obsidian.colorScheme.onSurface, EquisColors.voidPrimaryText);
    expect(obsidian.colorScheme.primary, EquisColors.voidEmerald);
    expect(obsidian.colorScheme.outline, EquisColors.voidStructure);
    expect(obsidian.textTheme.bodyMedium?.fontFamily, 'Geist Sans');
    expect(obsidian.textTheme.titleLarge?.fontFamily, 'Space Grotesk');
    expect(
      obsidian.extension<EquisVisualEffects>()?.panelTint,
      EquisColors.voidGlassSurface,
    );
    expect(obsidian.extension<EquisVisualEffects>()?.blurSigma, 12);
    expect(light.canvasColor, EquisColors.trueLightBackground);
    expect(light.colorScheme.onSurface, EquisColors.trueLightText);
    expect(light.colorScheme.primary, EquisColors.emerald);
    expect(legacy.scaffoldBackgroundColor, EquisColors.obsidian);
    expect(legacy.cardTheme.color, EquisColors.surface);
    expect(legacy.inputDecorationTheme.filled, isFalse);
    expect(
      _contrast(EquisColors.trueLightText, EquisColors.trueLightBackground),
      greaterThan(7),
    );
    expect(
      _contrast(EquisColors.voidPrimaryText, EquisColors.voidBackground),
      greaterThan(7),
    );
  });

  test('defaults unknown and absent stored values to Obsidian', () async {
    SharedPreferences.setMockInitialValues({});
    var store = await SharedPreferencesThemeStore.create();
    expect(await store.load(), EquisThemeVariant.obsidian);

    SharedPreferences.setMockInitialValues({
      SharedPreferencesThemeStore.preferenceKey: 'removed_theme',
    });
    store = await SharedPreferencesThemeStore.create();
    expect(await store.load(), EquisThemeVariant.obsidian);
  });

  test('controller updates and persists the selected theme', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferencesThemeStore.create();
    final controller = EquisThemeController(preferenceStore: store);

    await controller.select(EquisThemeVariant.trueLight);

    expect(controller.state, EquisThemeVariant.trueLight);
    expect(await store.load(), EquisThemeVariant.trueLight);
  });
}

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final light = first > second ? first : second;
  final dark = first > second ? second : first;
  return (light + 0.05) / (dark + 0.05);
}
