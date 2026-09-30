import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';

import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/ledger/transaction_search.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders the implemented local reports with FL Chart', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = EntityId.generate();
    final category = CategoryNode(
      id: EntityId.generate(),
      vaultId: vault,
      type: CategoryType.expense,
      customName: 'Food',
      createdAt: const UtcInstant.fromEpochMicroseconds(1),
      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
    );
    final extraCategories = List.generate(
      5,
      (index) => CategoryNode(
        id: EntityId.generate(),
        vaultId: vault,
        type: CategoryType.expense,
        customName: 'Expense $index',
        createdAt: const UtcInstant.fromEpochMicroseconds(1),
        updatedAt: const UtcInstant.fromEpochMicroseconds(1),
      ),
    );
    final incomeCategory = CategoryNode(
      id: EntityId.generate(),
      vaultId: vault,
      type: CategoryType.income,
      customName: 'Salary',
      createdAt: const UtcInstant.fromEpochMicroseconds(1),
      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
    );
    final account = EntityId.generate();
    final pocket = EntityId.generate();
    final report = DashboardSnapshot(
      reportingCurrency: CurrencyCode.brl,
      periodStart: LocalDate(2026, 8, 1),
      periodEnd: LocalDate(2026, 8, 31),
      availableMoneyMinor: 125000,
      incomeMinor: 50000,
      expenseMinor: 20000,
      spendingByTag: const [TagSpending(tagId: null, amountMinor: 20000)],
      spendingByCategory: [
        CategorySpending(categoryId: category.id, amountMinor: 20000),
        for (var index = 0; index < extraCategories.length; index++)
          CategorySpending(
            categoryId: extraCategories[index].id,
            amountMinor: 5000 - index * 500,
          ),
      ],
      incomeByCategory: [
        CategorySpending(categoryId: incomeCategory.id, amountMinor: 50000),
      ],
      cashFlow: [
        CashFlowPoint(
          date: LocalDate(2026, 8, 1),
          incomeMinor: 50000,
          expenseMinor: 0,
        ),
        CashFlowPoint(
          date: LocalDate(2026, 8, 2),
          incomeMinor: 0,
          expenseMinor: 20000,
        ),
      ],
      accountBalances: [
        AccountReportBalance(
          accountId: account,
          pocketId: pocket,
          accountName: 'Checking',
          type: AccountType.checking,
          nature: AccountNature.asset,
          currency: CurrencyCode.brl,
          originalMinor: 125000,
          reportingMinor: 125000,
        ),
      ],
      missingRates: const {},
      usesEstimatedRates: false,
      upcomingCount: 3,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: DashboardOverview(
                finance: LocalFinanceSnapshot(
                  vault: VaultProfile(
                    id: vault,
                    name: 'Local',
                    baseCurrency: CurrencyCode.brl,
                    locale: 'en-US',
                    timezone: 'UTC',
                    createdAt: const UtcInstant.fromEpochMicroseconds(1),
                    updatedAt: const UtcInstant.fromEpochMicroseconds(1),
                  ),
                  categories: [category, ...extraCategories, incomeCategory],
                ),
                reportOverride: report,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available money'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('Cash flow over time'), findsOneWidget);
    expect(find.text('Account balances'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Income:.*Expenses:', dotAll: true)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('By category: Expenses'), findsOneWidget);
    expect(find.bySemanticsLabel('Cash flow over time'), findsAtLeast(1));
    expect(find.byKey(const Key('dashboard-wide-pair')), findsNWidgets(3));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('category-classification-selector')),
        matching: find.text('Income'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.bySemanticsLabel('By category: Income'), findsOneWidget);
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Spending by tag'), findsOneWidget);
    expect(find.text('Without tags'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-wide-pair')), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'shows six proportional positive tag bubbles and keeps other values in lists',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final ids = List.generate(9, (_) => EntityId.generate());
      final values = [
        TagSpending(tagId: ids[0], amountMinor: 40000),
        TagSpending(tagId: ids[1], amountMinor: 10000),
        TagSpending(tagId: ids[2], amountMinor: 2500),
        TagSpending(tagId: ids[3], amountMinor: 625),
        TagSpending(tagId: ids[4], amountMinor: 100),
        TagSpending(tagId: ids[5], amountMinor: 25),
        TagSpending(tagId: ids[6], amountMinor: 1),
        TagSpending(tagId: ids[7], amountMinor: 0),
        TagSpending(tagId: ids[8], amountMinor: -500),
      ];
      final harness = _TagDashboardHarness(values);
      await harness.pump(tester, size: const Size(1280, 1400));
      await _showTags(tester);

      expect(find.byKey(const Key('tag-bubble-cluster')), findsOneWidget);
      for (final id in ids.take(6)) {
        expect(find.byKey(Key('tag-bubble-${id.value}')), findsOneWidget);
      }
      for (final id in ids.skip(6).take(1)) {
        expect(find.byKey(Key('tag-bubble-${id.value}')), findsNothing);
      }
      expect(find.byKey(Key('tag-bubble-${ids[7].value}')), findsNothing);
      expect(find.byKey(Key('tag-bubble-${ids[8].value}')), findsNothing);

      final largestDiameter = tester
          .getSize(find.byKey(Key('tag-bubble-${ids[0].value}')))
          .width;
      expect(largestDiameter, greaterThan(0));
      expect(largestDiameter, lessThanOrEqualTo(180));
      for (var index = 1; index < 6; index++) {
        final diameter = tester
            .getSize(find.byKey(Key('tag-bubble-${ids[index].value}')))
            .width;
        expect(
          diameter,
          closeTo(
            largestDiameter * math.sqrt(values[index].amountMinor / 40000),
            0.01,
          ),
        );
      }
      expect(
        find.bySemanticsLabel('${_tagLabel(ids[0])}, \$400.00'),
        findsOneWidget,
      );
      expect(find.text('\$400.00'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(
        find.text(
          'Each expense counts in full for every tag. Tag totals may overlap.',
        ),
        findsOneWidget,
      );

      expect(find.text(_tagLabel(ids[8])), findsOneWidget);
      expect(find.text(_tagLabel(ids[7])), findsNothing);
      expect(find.text('Other tag values'), findsOneWidget);
      await tester.tap(find.text('Other tag values'));
      await tester.pumpAndSettle();
      // Featured circles too small to carry a readable label also remain
      // available in the text list.
      for (final id in ids.skip(2).take(5)) {
        expect(find.byKey(Key('tag-value-${id.value}')), findsOneWidget);
      }
      expect(find.text(_tagLabel(ids[6])), findsOneWidget);
      expect(find.text(_tagLabel(ids[7])), findsOneWidget);
      expect(find.text(_tagLabel(ids[8])), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('keeps extreme positive ratios proportional', (tester) async {
    final largest = EntityId.generate();
    final smallest = EntityId.generate();
    final harness = _TagDashboardHarness([
      TagSpending(tagId: largest, amountMinor: 10000000),
      TagSpending(tagId: smallest, amountMinor: 1),
    ]);
    await harness.pump(tester, size: const Size(1280, 1400));
    await _showTags(tester);

    final largestDiameter = tester
        .getSize(find.byKey(Key('tag-bubble-${largest.value}')))
        .width;
    final smallestDiameter = tester
        .getSize(find.byKey(Key('tag-bubble-${smallest.value}')))
        .width;
    expect(largestDiameter, greaterThan(0));
    expect(largestDiameter, lessThanOrEqualTo(180));
    expect(smallestDiameter, greaterThan(0));
    expect(
      smallestDiameter,
      closeTo(largestDiameter * math.sqrt(1 / 10000000), 0.001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the empty state when the report has no tag values', (
    tester,
  ) async {
    final harness = _TagDashboardHarness(const []);
    await harness.pump(tester, size: const Size(1280, 1400));
    await _showTags(tester);

    expect(find.text('No classified activity in this period.'), findsOneWidget);
    expect(find.byKey(const Key('tag-bubble-cluster')), findsNothing);
    expect(find.text('Other tag values'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps negative-only tag values separate from the bubble chart', (
    tester,
  ) async {
    final id = EntityId.generate();
    final harness = _TagDashboardHarness([
      TagSpending(tagId: id, amountMinor: -1250),
    ]);
    await harness.pump(tester, size: const Size(720, 1200));
    await _showTags(tester);

    expect(find.byKey(const Key('tag-bubble-cluster')), findsNothing);
    expect(find.text('Negative adjustments by tag'), findsOneWidget);
    expect(find.text(_tagLabel(id)), findsOneWidget);
    expect(find.text('No classified activity in this period.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orders tied bubble values by stable tag identity', (
    tester,
  ) async {
    final ids = [
      EntityId.parse('00000000-0000-7000-8000-000000000003'),
      EntityId.parse('00000000-0000-7000-8000-000000000001'),
      EntityId.parse('00000000-0000-7000-8000-000000000002'),
    ];
    final harness = _TagDashboardHarness([
      for (final id in ids) TagSpending(tagId: id, amountMinor: 10000),
    ]);
    await harness.pump(tester, size: const Size(720, 1200));
    await _showTags(tester);

    final orderedIds = [...ids]..sort((a, b) => a.value.compareTo(b.value));
    final renderedBubbleKeys = tester
        .widgetList<Widget>(
          find.descendant(
            of: find.byKey(const Key('tag-bubble-cluster')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'tag-bubble-',
                  ) &&
                  !(widget.key! as ValueKey<String>).value.startsWith(
                    'tag-bubble-target-',
                  ),
            ),
          ),
        )
        .map((widget) => widget.key)
        .toList();

    expect(
      renderedBubbleKeys,
      orderedIds.map((id) => Key('tag-bubble-${id.value}')).toList(),
    );
  });

  testWidgets(
    'lays out the tag panel at mobile and wide widths without overflow',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final ids = List.generate(6, (_) => EntityId.generate());
        const longName =
            'A particularly long tag label that should wrap on narrow screens';
        final harness = _TagDashboardHarness(
          [
            for (var index = 0; index < ids.length; index++)
              TagSpending(tagId: ids[index], amountMinor: 10000 - index * 1000),
          ],
          tagNames: {ids.first: longName},
        );
        await harness.pump(tester, size: const Size(1280, 1400));
        await _showTags(tester);
        expect(find.byKey(const Key('dashboard-wide-pair')), findsNWidgets(3));
        expect(find.text(longName), findsOneWidget);
        expect(find.bySemanticsLabel('$longName, \$100.00'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(const Size(360, 1400));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dashboard-wide-pair')), findsNothing);
        if (find.byKey(const Key('tag-bubble-cluster')).evaluate().isEmpty) {
          await _showTags(tester);
        }
        expect(find.byKey(const Key('tag-bubble-cluster')), findsOneWidget);
        expect(find.text(longName), findsOneWidget);
        expect(find.bySemanticsLabel('$longName, \$100.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'tag bubbles expose names and values and route exact filters to history',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final taggedId = EntityId.generate();
        final harness = _TagDashboardHarness([
          TagSpending(tagId: taggedId, amountMinor: 12345),
          const TagSpending(tagId: null, amountMinor: 2500),
        ]);
        await harness.pump(tester, size: const Size(1280, 1400));
        await _showTags(tester);

        final taggedBubble = find.bySemanticsLabel(
          '${_tagLabel(taggedId)}, \$123.45',
        );
        expect(taggedBubble, findsOneWidget);
        final taggedSemantics = tester.getSemantics(taggedBubble);
        expect(
          taggedSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(taggedBubble);
        await tester.pumpAndSettle();

        var filter = harness.historyFilter!;
        expect(filter.tagId, taggedId);
        expect(filter.withoutTags, isFalse);
        expect(filter.fromDate, LocalDate(2026, 8, 1));
        expect(filter.toDate, LocalDate(2026, 8, 28));
        expect(filter.reportingExpensesOnly, isTrue);

        harness.router.go('/');
        await tester.pumpAndSettle();
        await _showTags(tester);
        final withoutTagsBubble = find.bySemanticsLabel(
          'Without tags, \$25.00',
        );
        expect(withoutTagsBubble, findsOneWidget);
        expect(
          tester
              .getSemantics(withoutTagsBubble)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(withoutTagsBubble);
        await tester.pumpAndSettle();

        filter = harness.historyFilter!;
        expect(filter.tagId, isNull);
        expect(filter.withoutTags, isTrue);
        expect(filter.fromDate, LocalDate(2026, 8, 1));
        expect(filter.toDate, LocalDate(2026, 8, 28));
        expect(filter.reportingExpensesOnly, isTrue);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'tooltip supports hover, exit, and long press without navigation',
    (tester) async {
      final id = EntityId.generate();
      const longName = 'A full tag name that does not fit inside the bubble';
      final harness = _TagDashboardHarness(
        [TagSpending(tagId: id, amountMinor: 12345)],
        tagNames: {id: longName},
      );
      await harness.pump(tester, size: const Size(900, 1200));
      await _showTags(tester);
      final target = find.byKey(Key('tag-bubble-target-${id.value}'));
      final message = '$longName\n\$123.45';

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 201));
      expect(find.text(message), findsOneWidget);
      expect(harness.historyFilter, isNull);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 101));
      expect(find.text(message), findsNothing);

      await tester.longPress(target);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(harness.historyFilter, isNull);
      await mouse.removePointer();
    },
  );

  testWidgets('keyboard focus reveals the tooltip and Enter opens the filter', (
    tester,
  ) async {
    final id = EntityId.generate();
    final harness = _TagDashboardHarness([
      TagSpending(tagId: id, amountMinor: 12345),
    ]);
    await harness.pump(tester, size: const Size(900, 1200));
    await _showTags(tester);
    final target = find.byKey(Key('tag-bubble-target-${id.value}'));
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: target, matching: find.byType(InkWell)),
    );

    inkWell.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('${_tagLabel(id)}\n\$123.45'), findsOneWidget);
    expect(harness.historyFilter, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(harness.historyFilter?.tagId, id);
    expect(harness.historyFilter?.reportingExpensesOnly, isTrue);
  });

  testWidgets('clipped circular hit target ignores its rectangular corners', (
    tester,
  ) async {
    final id = EntityId.generate();
    final harness = _TagDashboardHarness([
      TagSpending(tagId: id, amountMinor: 10000),
    ]);
    await harness.pump(tester, size: const Size(900, 1200));
    await _showTags(tester);
    final target = find.byKey(Key('tag-bubble-target-${id.value}'));
    final rect = tester.getRect(target);

    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(harness.historyFilter, isNull);
  });

  testWidgets('focus moving between bubbles and away moves the tooltip', (
    tester,
  ) async {
    final ids = [
      EntityId.parse('00000000-0000-7000-8000-000000000001'),
      EntityId.parse('00000000-0000-7000-8000-000000000002'),
    ];
    final harness = _TagDashboardHarness([
      for (final id in ids) TagSpending(tagId: id, amountMinor: 10000),
    ]);
    await harness.pump(tester, size: const Size(900, 1200));
    await _showTags(tester);

    FocusNode focusNode(String id) {
      final bubble = find.byKey(Key('tag-bubble-target-$id'));
      return tester
          .widget<InkWell>(
            find.descendant(of: bubble, matching: find.byType(InkWell)),
          )
          .focusNode!;
    }

    final first = focusNode(ids[0].value);
    final second = focusNode(ids[1].value);
    first.requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('${_tagLabel(ids[0])}\n\$100.00'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(first.hasFocus, isFalse);
    expect(second.hasFocus, isTrue);
    expect(find.text('${_tagLabel(ids[0])}\n\$100.00'), findsNothing);
    expect(find.text('${_tagLabel(ids[1])}\n\$100.00'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(second.hasFocus, isFalse);
    expect(find.text('${_tagLabel(ids[1])}\n\$100.00'), findsNothing);
  });

  testWidgets(
    'focused bubble preserves its identity when report order changes',
    (tester) async {
      final ids = [EntityId.generate(), EntityId.generate()];
      final harness = _TagDashboardHarness([
        TagSpending(tagId: ids[0], amountMinor: 10000),
        TagSpending(tagId: ids[1], amountMinor: 5000),
      ]);
      await harness.pump(tester, size: const Size(900, 1200));
      await _showTags(tester);

      Finder bubble(String id) => find.byKey(Key('tag-bubble-target-$id'));
      FocusNode node(String id) => tester
          .widget<InkWell>(
            find.descendant(of: bubble(id), matching: find.byType(InkWell)),
          )
          .focusNode!;

      final originalNode = node(ids[0].value);
      originalNode.requestFocus();
      await tester.pumpAndSettle();
      expect(originalNode.hasFocus, isTrue);

      harness.values
        ..clear()
        ..add(TagSpending(tagId: ids[1], amountMinor: 20000))
        ..add(TagSpending(tagId: ids[0], amountMinor: 10000));
      harness.router.refresh();
      await tester.pumpAndSettle();

      expect(node(ids[0].value), same(originalNode));
      expect(originalNode.hasFocus, isTrue);
      expect(find.text('${_tagLabel(ids[0])}\n\$100.00'), findsOneWidget);
    },
  );

  testWidgets('large text on mobile keeps full names in the text list', (
    tester,
  ) async {
    final id = EntityId.generate();
    const longName = 'A complete tag name that remains available on mobile';
    final harness = _TagDashboardHarness(
      [TagSpending(tagId: id, amountMinor: 100000)],
      tagNames: {id: longName},
      textScale: 2,
    );
    await harness.pump(tester, size: const Size(320, 1200));
    await _showTags(tester);

    await tester.tap(find.text('Other tag values'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('tag-value-${id.value}')), findsOneWidget);
    expect(find.text(longName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'can export desktop and mobile bubble review captures',
    (tester) async {
      final cases = [
        (
          name: 'desktop-light',
          size: const Size(1280, 1400),
          scale: 1.0,
          brightness: Brightness.light,
        ),
        (
          name: 'mobile-light',
          size: const Size(320, 1400),
          scale: 1.0,
          brightness: Brightness.light,
        ),
        (
          name: 'desktop-large-dark',
          size: const Size(1280, 1400),
          scale: 2.0,
          brightness: Brightness.dark,
        ),
        (
          name: 'mobile-large-dark',
          size: const Size(320, 1400),
          scale: 2.0,
          brightness: Brightness.dark,
        ),
        (
          name: 'mobile-equal-values',
          size: const Size(320, 1400),
          scale: 1.0,
          brightness: Brightness.light,
        ),
      ];
      final directory = Directory('.tooling/bubble-captures');
      await tester.runAsync(() async {
        for (final font in const {
          'Inter': 'assets/fonts/Inter-Variable.ttf',
          'Geist Sans': 'assets/fonts/Geist-Variable.ttf',
          'Space Grotesk': 'assets/fonts/SpaceGrotesk-Variable.ttf',
          'JetBrains Mono': 'assets/fonts/JetBrainsMono-Variable.ttf',
        }.entries) {
          final loader = FontLoader(font.key)
            ..addFont(rootBundle.load(font.value));
          await loader.load();
        }
      });

      for (final item in cases) {
        const names = [
          'Rent',
          'Groceries & household',
          'Education and training',
          'Transport',
          'Health',
          'Travel',
        ];
        final ids = [
          for (var index = 0; index < names.length; index++)
            EntityId.parse(
              '00000000-0000-7000-8000-${(index + 1).toString().padLeft(12, '0')}',
            ),
        ];
        final harness = _TagDashboardHarness(
          [
            for (var index = 0; index < ids.length; index++)
              TagSpending(
                tagId: ids[index],
                amountMinor: item.name == 'mobile-equal-values'
                    ? 10000
                    : [120000, 80000, 50000, 30000, 15000, 5000][index],
              ),
          ],
          tagNames: {
            for (var index = 0; index < ids.length; index++)
              ids[index]: names[index],
          },
          brightness: item.brightness,
          textScale: item.scale,
          captureKey: const Key('bubble-review-capture'),
        );
        await harness.pump(tester, size: item.size);
        await _showTags(tester);
        await tester.ensureVisible(find.byKey(const Key('tag-bubble-cluster')));
        await tester.pumpAndSettle();

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('bubble-review-capture')),
        );
        await tester.runAsync(() async {
          await directory.create(recursive: true);
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          await File(
            '${directory.path}/${item.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    },
    skip: Platform.environment['EQUIS_CAPTURE_BUBBLES'] != '1',
  );
}

Future<void> _showTags(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Tags'));
  await tester.tap(find.text('Tags'));
  await tester.pumpAndSettle();
}

String _tagLabel(EntityId id) => 'Tag ${id.value.substring(28)}';

class _TagDashboardHarness {
  _TagDashboardHarness(
    this.values, {
    this.tagNames = const {},
    this.brightness = Brightness.light,
    this.textScale = 1,
    this.captureKey,
  }) : vaultId = EntityId.generate(),
       periodStart = LocalDate(2026, 8, 1),
       periodEnd = LocalDate(2026, 8, 31) {
    tags = [
      for (final id
          in values.map((value) => value.tagId).whereType<EntityId>().toSet())
        Tag(
          id: id,
          vaultId: vaultId,
          name: tagNames[id] ?? _tagLabel(id),
          createdAt: const UtcInstant.fromEpochMicroseconds(1),
          updatedAt: const UtcInstant.fromEpochMicroseconds(1),
        ),
    ];
  }

  final List<TagSpending> values;
  final Map<EntityId, String> tagNames;
  final Brightness brightness;
  final double textScale;
  final Key? captureKey;
  final EntityId vaultId;
  final LocalDate periodStart;
  final LocalDate periodEnd;
  late final List<Tag> tags;
  late final GoRouter router;
  TransactionSearchFilter? historyFilter;

  Future<void> pump(WidgetTester tester, {required Size size}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: RepaintBoundary(
              key: captureKey,
              child: SingleChildScrollView(
                child: DashboardOverview(
                  finance: LocalFinanceSnapshot(
                    vault: VaultProfile(
                      id: vaultId,
                      name: 'Local',
                      baseCurrency: CurrencyCode.usd,
                      locale: 'en-US',
                      timezone: 'UTC',
                      createdAt: const UtcInstant.fromEpochMicroseconds(1),
                      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
                    ),
                    tags: tags,
                  ),
                  reportOverride: DashboardSnapshot(
                    reportingCurrency: CurrencyCode.usd,
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    availableMoneyMinor: 100000,
                    incomeMinor: 0,
                    expenseMinor: 0,
                    spendingByCategory: const [],
                    spendingByTag: values,
                    cashFlow: [
                      CashFlowPoint(
                        date: LocalDate(2026, 8, 10),
                        incomeMinor: 0,
                        expenseMinor: 0,
                      ),
                      CashFlowPoint(
                        date: LocalDate(2026, 8, 28),
                        incomeMinor: 0,
                        expenseMinor: 0,
                      ),
                    ],
                    accountBalances: const [],
                    missingRates: const {},
                    usesEstimatedRates: false,
                    upcomingCount: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) {
            historyFilter = state.extra as TransactionSearchFilter;
            return const Scaffold(body: Text('History route'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en', 'US'),
          theme: EquisTheme.forVariant(
            brightness == Brightness.dark
                ? EquisThemeVariant.obsidian
                : EquisThemeVariant.trueLight,
          ),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
