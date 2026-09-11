import 'dart:ui';

import 'package:equis/app/theme/equis_theme.dart';
import 'package:flutter/material.dart';

class EquisThemeBackdrop extends StatelessWidget {
  const EquisThemeBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = theme.extension<EquisVisualEffects>();
    final background = effects?.glassEnabled == true
        ? theme.canvasColor
        : EquisColors.obsidian;

    if (effects?.glassEnabled != true) {
      return ColoredBox(color: background, child: child);
    }

    return ColoredBox(
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -220,
            right: -150,
            width: 560,
            height: 560,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [effects!.glowStart, Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -260,
            left: -180,
            width: 640,
            height: 640,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [effects.glowEnd, Colors.transparent],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class EquisGlassSurface extends StatelessWidget {
  const EquisGlassSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effects = Theme.of(context).extension<EquisVisualEffects>();
    if (effects?.glassEnabled != true) return child;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effects!.blurSigma,
          sigmaY: effects.blurSigma,
        ),
        child: child,
      ),
    );
  }
}

class EquisGlassCard extends StatelessWidget {
  const EquisGlassCard({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.child,
    this.semanticContainer = true,
  });

  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final ShapeBorder? shape;
  final bool borderOnForeground;
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;
  final Widget? child;
  final bool semanticContainer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = theme.extension<EquisVisualEffects>();
    if (effects?.glassEnabled != true) return _card();

    final cardTheme = theme.cardTheme;
    final effectiveShape =
        shape ??
        cardTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    final effectiveMargin =
        margin ?? cardTheme.margin ?? const EdgeInsets.all(4);

    return Padding(
      padding: effectiveMargin,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: effectiveShape),
        clipBehavior: clipBehavior ?? Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effects!.blurSigma,
            sigmaY: effects.blurSigma,
          ),
          child: _card(
            margin: EdgeInsets.zero,
            shape: effectiveShape,
            color: color ?? effects.panelTint,
          ),
        ),
      ),
    );
  }

  Card _card({EdgeInsetsGeometry? margin, ShapeBorder? shape, Color? color}) =>
      Card(
        color: color ?? this.color,
        shadowColor: shadowColor,
        surfaceTintColor: surfaceTintColor,
        elevation: elevation,
        shape: shape ?? this.shape,
        borderOnForeground: borderOnForeground,
        margin: margin ?? this.margin,
        clipBehavior: clipBehavior,
        semanticContainer: semanticContainer,
        child: child,
      );
}
