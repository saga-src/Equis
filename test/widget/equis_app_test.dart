import 'package:equis/app/equis_app.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the local-first shell in English', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EquisApp()));
    await tester.pumpAndSettle();

    expect(find.text('Available money'), findsOneWidget);
    expect(find.text('Offline ready'), findsOneWidget);
    expect(find.text('Add transaction'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
  });

  testWidgets('renders the shared shell in Brazilian Portuguese', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeProvider.overrideWith((ref) => const Locale('pt', 'BR')),
        ],
        child: const EquisApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dinheiro disponível'), findsOneWidget);
    expect(find.text('Pronto para uso offline'), findsOneWidget);
    expect(find.text('Adicionar transação'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Agendado'), findsOneWidget);
    expect(find.text('Cartões'), findsOneWidget);
  });

  test('legacy tokens preserve the original approved palette', () {
    expect(EquisColors.obsidian, const Color(0xFF0F172A));
    expect(EquisColors.surface, const Color(0xFF1E293B));
    expect(EquisColors.textPrimary, const Color(0xFFE2E8F0));
    expect(EquisColors.emerald, const Color(0xFF10B981));
    expect(
      _contrast(EquisColors.textPrimary, EquisColors.obsidian),
      greaterThan(7),
    );
    expect(
      _contrast(EquisColors.textPrimary, EquisColors.surface),
      greaterThan(7),
    );
    expect(
      _contrast(EquisColors.emerald, EquisColors.obsidian),
      greaterThan(4.5),
    );
  });

  testWidgets('adapts navigation and preserves mobile touch targets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: EquisApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final destination in tester.widgetList<NavigationDestination>(
      find.byType(NavigationDestination),
    )) {
      expect(destination.label, isNotEmpty);
    }
    expect(tester.getSize(find.byType(NavigationBar)).height, greaterThan(48));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Wealth'), findsOneWidget);
    expect(find.text('Investments'), findsOneWidget);
  });

  testWidgets('uses the complete navigation rail on a resized desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: EquisApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).destinations,
      hasLength(9),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('principal mobile layout fits Brazilian Portuguese', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeProvider.overrideWith((ref) => const Locale('pt', 'BR')),
        ],
        child: const EquisApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Adicionar transação'), findsOneWidget);
  });

  testWidgets('switches the running application locale from settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: EquisApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.byKey(const Key('taxonomy-settings')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('language-pt-BR')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-pt-BR')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Português (Brasil)'), findsOneWidget);
    expect(find.text('Configurações'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('language-en-US')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-en-US')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Language'), findsOneWidget);
  });
}

double _contrast(Color foreground, Color background) {
  final light = foreground.computeLuminance();
  final dark = background.computeLuminance();
  return (light + 0.05) / (dark + 0.05);
}
