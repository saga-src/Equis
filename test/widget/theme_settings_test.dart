import 'package:equis/app/equis_app.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings switches among Obsidian, True Light, and Legacy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: EquisApp()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      const Duration(milliseconds: 300),
    );
    expect(_theme(tester).brightness, Brightness.dark);
    expect(
      _theme(tester).extension<EquisVisualEffects>()?.glassEnabled,
      isTrue,
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-true_light')));
    await tester.pumpAndSettle();
    expect(_theme(tester).brightness, Brightness.light);
    expect(_theme(tester).scaffoldBackgroundColor, Colors.transparent);

    await tester.tap(find.byKey(const Key('theme-legacy')));
    await tester.pumpAndSettle();
    expect(_theme(tester).brightness, Brightness.dark);
    expect(
      _theme(tester).extension<EquisVisualEffects>()?.glassEnabled,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('theme-obsidian')));
    await tester.pumpAndSettle();
    expect(
      _theme(tester).extension<EquisVisualEffects>()?.glassEnabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first));
