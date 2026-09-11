import 'package:flutter/material.dart';

enum EquisThemeVariant {
  obsidian('obsidian'),
  trueLight('true_light'),
  legacy('legacy');

  const EquisThemeVariant(this.storageValue);

  final String storageValue;

  static EquisThemeVariant fromStorage(String? value) => values.firstWhere(
    (variant) => variant.storageValue == value,
    orElse: () => EquisThemeVariant.obsidian,
  );
}

abstract final class EquisColors {
  // Original v1 tokens retained for True Light and Legacy.
  static const obsidian = Color(0xFF0F172A);
  static const surface = Color(0xFF1E293B);
  static const textPrimary = Color(0xFFE2E8F0);
  static const emerald = Color(0xFF10B981);
  static const trueLightBackground = Color(0xFFEFEFEF);
  static const trueLightSurface = Color(0xFFFFFFFF);
  static const trueLightText = Color(0xFF0F172A);

  // Obsidian Void tokens.
  static const voidBackground = Color(0xFF000000);
  static const voidElevatedSurface = Color(0xFF0A0A0A);
  static const voidSecondarySurface = Color(0xFF141414);
  static const voidMutedSurface = Color(0xFF1A1A1A);
  static const voidAccentSurface = Color(0xFF1F1F1F);
  static const voidPrimaryText = Color(0xFFF8FAFC);
  static const voidSecondaryText = Color(0xFF94A3B8);
  static const voidEmerald = emerald;
  static const voidStructure = Color(0xFF1D283A);
  static const voidGlassSurface = Color(0x990F172A);
  static const voidGlassBorder = Color(0x1AFFFFFF);
}

abstract final class EquisTypography {
  static const interfaceFont = 'Inter';
  static const interfaceFallback = ['Segoe UI', 'Roboto'];
  static const obsidianBodyFont = 'Geist Sans';
  static const obsidianBodyFallback = ['Inter', 'Segoe UI', 'Roboto'];
  static const obsidianHeadingFont = 'Space Grotesk';
  static const numericFont = 'JetBrains Mono';
  static const numericFallback = ['Consolas', 'monospace'];

  static const numeric = TextStyle(
    fontFamily: numericFont,
    fontFamilyFallback: numericFallback,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

@immutable
final class EquisVisualEffects extends ThemeExtension<EquisVisualEffects> {
  const EquisVisualEffects({
    required this.glassEnabled,
    required this.panelTint,
    required this.panelBorder,
    required this.glowStart,
    required this.glowEnd,
    required this.blurSigma,
  });

  final bool glassEnabled;
  final Color panelTint;
  final Color panelBorder;
  final Color glowStart;
  final Color glowEnd;
  final double blurSigma;

  @override
  EquisVisualEffects copyWith({
    bool? glassEnabled,
    Color? panelTint,
    Color? panelBorder,
    Color? glowStart,
    Color? glowEnd,
    double? blurSigma,
  }) => EquisVisualEffects(
    glassEnabled: glassEnabled ?? this.glassEnabled,
    panelTint: panelTint ?? this.panelTint,
    panelBorder: panelBorder ?? this.panelBorder,
    glowStart: glowStart ?? this.glowStart,
    glowEnd: glowEnd ?? this.glowEnd,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  EquisVisualEffects lerp(
    covariant ThemeExtension<EquisVisualEffects>? other,
    double t,
  ) {
    if (other is! EquisVisualEffects) return this;
    return EquisVisualEffects(
      glassEnabled: t < 0.5 ? glassEnabled : other.glassEnabled,
      panelTint: Color.lerp(panelTint, other.panelTint, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      glowStart: Color.lerp(glowStart, other.glowStart, t)!,
      glowEnd: Color.lerp(glowEnd, other.glowEnd, t)!,
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
    );
  }
}

abstract final class EquisTheme {
  static ThemeData forVariant(EquisThemeVariant variant) => switch (variant) {
    EquisThemeVariant.obsidian => obsidian,
    EquisThemeVariant.trueLight => trueLight,
    EquisThemeVariant.legacy => legacy,
  };

  static ThemeData get obsidian {
    const scheme = ColorScheme.dark(
      primary: EquisColors.voidEmerald,
      onPrimary: EquisColors.voidBackground,
      secondary: EquisColors.voidEmerald,
      onSecondary: EquisColors.voidBackground,
      surface: EquisColors.voidElevatedSurface,
      onSurface: EquisColors.voidPrimaryText,
      surfaceContainerLowest: EquisColors.voidBackground,
      surfaceContainerLow: EquisColors.voidElevatedSurface,
      surfaceContainer: EquisColors.voidSecondarySurface,
      surfaceContainerHigh: EquisColors.voidMutedSurface,
      surfaceContainerHighest: EquisColors.voidAccentSurface,
      onSurfaceVariant: EquisColors.voidSecondaryText,
      outline: EquisColors.voidStructure,
      outlineVariant: EquisColors.voidStructure,
      error: Color(0xFFF87171),
      onError: EquisColors.voidBackground,
    );

    return _base(
      brightness: Brightness.dark,
      scheme: scheme,
      scaffoldBackground: Colors.transparent,
      canvasColor: EquisColors.voidBackground,
      cardColor: EquisColors.voidGlassSurface,
      fontFamily: EquisTypography.obsidianBodyFont,
      fontFallback: EquisTypography.obsidianBodyFallback,
      headingFontFamily: EquisTypography.obsidianHeadingFont,
      cardRadius: 12,
      inputRadius: 10,
      controlRadius: 10,
      chipRadius: 8,
      effects: const EquisVisualEffects(
        glassEnabled: true,
        panelTint: EquisColors.voidGlassSurface,
        panelBorder: EquisColors.voidGlassBorder,
        glowStart: Color(0x1410B981),
        glowEnd: Color(0x0A10B981),
        blurSigma: 12,
      ),
    );
  }

  static ThemeData get trueLight {
    const scheme = ColorScheme.light(
      primary: EquisColors.emerald,
      onPrimary: EquisColors.trueLightText,
      secondary: Color(0xFF047857),
      onSecondary: Colors.white,
      surface: EquisColors.trueLightSurface,
      onSurface: EquisColors.trueLightText,
      surfaceContainerHighest: Color(0xFFE2E8F0),
      onSurfaceVariant: Color(0xFF334155),
      outline: Color(0xFF64748B),
      outlineVariant: Color(0xFFCBD5E1),
      error: Color(0xFFB91C1C),
      onError: Colors.white,
    );

    return _base(
      brightness: Brightness.light,
      scheme: scheme,
      scaffoldBackground: Colors.transparent,
      canvasColor: EquisColors.trueLightBackground,
      cardColor: const Color(0xCFFFFFFF),
      fontFamily: EquisTypography.interfaceFont,
      fontFallback: EquisTypography.interfaceFallback,
      effects: const EquisVisualEffects(
        glassEnabled: true,
        panelTint: Color(0xCFFFFFFF),
        panelBorder: Color(0x99FFFFFF),
        glowStart: Color(0x2410B981),
        glowEnd: Color(0x1F38BDF8),
        blurSigma: 14,
      ),
    );
  }

  /// The original v1 theme, retained without the new glass treatment.
  static ThemeData get legacy {
    final scheme = ColorScheme.fromSeed(
      seedColor: EquisColors.emerald,
      brightness: Brightness.dark,
      surface: EquisColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: EquisColors.obsidian,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      fontFamily: EquisTypography.interfaceFont,
      fontFamilyFallback: EquisTypography.interfaceFallback,
      cardTheme: const CardThemeData(
        color: EquisColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: EquisColors.surface,
        indicatorColor: Color(0x3310B981),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: EquisColors.surface,
        indicatorColor: Color(0x3310B981),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: EquisColors.emerald,
        foregroundColor: EquisColors.obsidian,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(48)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      extensions: const [
        EquisVisualEffects(
          glassEnabled: false,
          panelTint: EquisColors.surface,
          panelBorder: Colors.transparent,
          glowStart: Colors.transparent,
          glowEnd: Colors.transparent,
          blurSigma: 0,
        ),
      ],
    );
  }

  static ThemeData _base({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color canvasColor,
    required Color cardColor,
    required String fontFamily,
    required List<String> fontFallback,
    required EquisVisualEffects effects,
    String? headingFontFamily,
    double cardRadius = 18,
    double inputRadius = 14,
    double? controlRadius,
    double? chipRadius,
  }) {
    final controlShape = controlRadius == null
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          );
    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: canvasColor,
      focusColor: scheme.primary.withValues(alpha: 0.24),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: effects.panelBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: effects.panelBorder),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: effects.panelTint,
        indicatorColor: scheme.primary.withValues(alpha: 0.20),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: effects.panelTint,
        indicatorColor: scheme.primary.withValues(alpha: 0.20),
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: controlShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: controlShape,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(48)),
        ),
      ),
      chipTheme: chipRadius == null
          ? null
          : ChipThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(chipRadius),
                side: BorderSide(color: scheme.outline),
              ),
            ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      extensions: [effects],
    );

    if (headingFontFamily == null) return theme;
    final text = theme.textTheme;
    TextStyle? heading(TextStyle? style) => style?.copyWith(
      fontFamily: headingFontFamily,
      fontFamilyFallback: fontFallback,
    );
    return theme.copyWith(
      textTheme: text.copyWith(
        displayLarge: heading(text.displayLarge),
        displayMedium: heading(text.displayMedium),
        displaySmall: heading(text.displaySmall),
        headlineLarge: heading(text.headlineLarge),
        headlineMedium: heading(text.headlineMedium),
        headlineSmall: heading(text.headlineSmall),
        titleLarge: heading(text.titleLarge),
        titleMedium: heading(text.titleMedium),
        titleSmall: heading(text.titleSmall),
      ),
    );
  }
}
