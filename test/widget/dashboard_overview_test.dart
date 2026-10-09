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
import 'package:equis/domain/wealth/net_worth_models.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:equis/presentation/home/dashboard_controller.dart';
import 'package:equis/presentation/wealth/wealth_controller.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:equis/app/providers/app_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fl_chart/src/chart/line_chart/line_chart_renderer.dart';
import 'package:fl_chart/src/chart/bar_chart/bar_chart_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart'
    show FontLoader, LogicalKeyboardKey, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] != '1') return;
    for (final font in const {
      'Inter': 'assets/fonts/Inter-Variable.ttf',
      'Geist Sans': 'assets/fonts/Geist-Variable.ttf',
      'Space Grotesk': 'assets/fonts/SpaceGrotesk-Variable.ttf',
      'JetBrains Mono': 'assets/fonts/JetBrainsMono-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'desktop dashboard alignment and growing report panels: $brightness',
      (tester) async {
        final ids = List.generate(10, (_) => EntityId.generate());
        final harness = _TagDashboardHarness(
          [
            for (var index = 0; index < ids.length; index++)
              TagSpending(tagId: ids[index], amountMinor: 10000 - index * 100),
          ],
          brightness: brightness,
          captureKey: const Key('dashboard-layout-capture'),
          loadedPositionReports: true,
        );
        await harness.pump(tester, size: const Size(1280, 1600));
        final heading = tester.getRect(
          find.byKey(const Key('available-money-heading')),
        );
        final periodControl = tester.getRect(
          find.byKey(const ValueKey('dashboard-range-thisMonth')),
        );
        final modeControl = tester.getRect(
          find.byKey(const ValueKey('dashboard-mode-daily')),
        );
        expect(periodControl.left, greaterThan(heading.left));
        expect(modeControl.left, greaterThan(periodControl.right));
        expect(
          periodControl.center.dy,
          inInclusiveRange(heading.top, heading.bottom),
        );
        expect(periodControl.height, lessThanOrEqualTo(28));
        expect(modeControl.height, lessThanOrEqualTo(28));
        expect(periodControl.width, lessThan(180));
        expect(modeControl.width, lessThan(100));
        final summary = find.byKey(const Key('dashboard-period-summary'));
        final periodTexts = find.descendant(
          of: summary,
          matching: find.byType(Text),
        );
        final labelRect = tester.getRect(periodTexts.at(0));
        final dateRect = tester.getRect(periodTexts.at(1));
        expect(dateRect.left, greaterThan(labelRect.right));
        expect(dateRect.center.dy, closeTo(labelRect.center.dy, 2));
        expect(
          tester.widget<Text>(periodTexts.first).style!.fontSize,
          lessThanOrEqualTo(14),
        );
        for (final summary in ['net-worth', 'portfolio']) {
          final icon = find.byKey(Key('$summary-summary-icon'));
          final tile = find.ancestor(
            of: icon,
            matching: find.byType(EquisGlassCard),
          );
          final textGroup = tester
              .getRect(find.byKey(Key('$summary-summary-title')))
              .expandToInclude(
                tester.getRect(find.byKey(Key('$summary-summary-values'))),
              );
          expect(tester.getCenter(icon).dy, closeTo(textGroup.center.dy, 1));
          expect(
            tester.getCenter(icon).dy,
            closeTo(tester.getCenter(tile).dy, 1),
          );
        }
        final spending = find.byKey(const Key('dashboard-spending-card'));
        final cashFlow = find.byKey(const Key('cash-flow-report-card'));
        final baseHeight = tester.getSize(spending).height;
        final toggleBottom = tester
            .getRect(find.byKey(const Key('dashboard-spending-toggle')))
            .bottom;
        expect(tester.getRect(cashFlow).top, greaterThan(toggleBottom));
        expect(
          tester.getRect(cashFlow).top,
          closeTo(tester.getRect(spending).top, .1),
        );
        expect(tester.getSize(cashFlow).height, closeTo(baseHeight, .1));
        if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] == '1') {
          await _captureDashboard(tester, '${brightness.name}-categories');
        }
        await _showTags(tester);
        expect(
          tester.getSize(spending).height,
          greaterThanOrEqualTo(baseHeight),
        );
        expect(
          tester.getSize(cashFlow).height,
          closeTo(tester.getSize(spending).height, .1),
        );
        final beforeExpansion = tester.getSize(cashFlow).height;
        await tester.ensureVisible(
          find.byKey(const Key('tag-other-values-expansion')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tag-other-values-expansion')));
        await tester.pumpAndSettle();
        expect(tester.getSize(cashFlow).height, greaterThan(beforeExpansion));
        expect(
          tester.getSize(cashFlow).height,
          closeTo(tester.getSize(spending).height, .1),
        );
        if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] == '1') {
          await _captureDashboard(tester, '${brightness.name}-expanded-tags');
        }
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'cash-flow hover at both edges uses theme colors: $brightness',
      (tester) async {
        final harness = _TagDashboardHarness(
          const [],
          brightness: brightness,
          captureKey: const Key('dashboard-layout-capture'),
        );
        await harness.pump(tester, size: const Size(1280, 1600));
        final chart = tester.widget<LineChart>(find.byType(LineChart));
        final theme = Theme.of(tester.element(find.byType(LineChart)));
        final tooltip = chart.data.lineTouchData.touchTooltipData;
        final bar = chart.data.lineBarsData.first;
        expect(
          tooltip.getTooltipColor(LineBarSpot(bar, 0, bar.spots.first)),
          theme.cardTheme.color ?? theme.colorScheme.surface,
        );
        expect(tooltip.fitInsideHorizontally, isTrue);
        expect(tooltip.fitInsideVertically, isTrue);
        await tester.ensureVisible(find.byKey(const Key('cash-flow-plot')));
        await tester.pumpAndSettle();
        final plotRect = tester.getRect(
          find.byKey(const Key('cash-flow-plot')),
        );
        for (final label
            in find
                .descendant(
                  of: find.byType(LineChart),
                  matching: find.byType(Text),
                )
                .evaluate()) {
          final labelRect = tester.getRect(find.byWidget(label.widget));
          expect(labelRect.left, greaterThanOrEqualTo(plotRect.left - 1));
          expect(labelRect.right, lessThanOrEqualTo(plotRect.right + 1));
        }
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: Offset(plotRect.left + 1, plotRect.center.dy),
        );
        for (final x in [plotRect.left + 1, plotRect.right - 1]) {
          await mouse.moveTo(Offset(x, plotRect.center.dy));
          await tester.pumpAndSettle();
          final rendered = tester.widget<LineChartLeaf>(
            find.byKey(const Key('cash-flow-plot')),
          );
          expect(rendered.targetData.showingTooltipIndicators, isNotEmpty);
          expect(tester.takeException(), isNull);
        }
        if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] == '1') {
          await _captureDashboard(
            tester,
            '${brightness.name}-hover-right-edge',
          );
        }
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LineChartLeaf>(find.byKey(const Key('cash-flow-plot')))
              .targetData
              .showingTooltipIndicators,
          isEmpty,
        );
      },
    );
  }
  for (final brightness in Brightness.values) {
    for (final amounts in [(30000, 10000), (10000, 30000), (0, 0)]) {
      testWidgets(
        'three summary bars align with centered totals: $brightness $amounts',
        (tester) async {
          final harness = _TagDashboardHarness(
            const [],
            brightness: brightness,
            incomeMinor: amounts.$1,
            expenseMinor: amounts.$2,
            loadedPositionReports: true,
            incompletePositionReports: amounts.$1 < amounts.$2,
            captureKey: const Key('dashboard-layout-capture'),
          );
          await harness.pump(tester, size: const Size(1280, 1600));
          final plotFinder = find.byKey(const Key('dashboard-summary-bars'));
          final plotRect = tester.getRect(plotFinder);
          final rendered = tester.renderObject<RenderBarChart>(plotFinder);
          final data = tester.widget<BarChart>(find.byType(BarChart)).data;
          final values = [
            amounts.$1 / 100,
            amounts.$2 / 100,
            (amounts.$1 - amounts.$2) / 100,
          ];
          const keys = [
            'income-summary-column',
            'expenses-summary-column',
            'net-cash-flow-summary-column',
          ];
          expect(data.barGroups.length, 3);
          for (var i = 0; i < keys.length; i++) {
            final column = find.byKey(Key(keys[i]));
            final columnRect = tester.getRect(column);
            expect(
              columnRect.center.dx,
              closeTo(plotRect.left + plotRect.width * (i + .5) / 3, .1),
            );
            for (final text
                in find
                    .descendant(of: column, matching: find.byType(Text))
                    .evaluate()) {
              expect(
                tester.getCenter(find.byWidget(text.widget)).dx,
                closeTo(columnRect.center.dx, .1),
              );
              expect((text.widget as Text).textAlign, TextAlign.center);
            }
            expect(data.barGroups[i].barRods.single.toY, values[i]);
            if (values[i] != 0) {
              final barY =
                  plotRect.height *
                  (data.maxY - values[i] / 2) /
                  (data.maxY - data.minY);
              final hit = rendered.getResponseAtLocation(
                Offset(columnRect.center.dx - plotRect.left, barY),
              );
              expect(hit.spot?.touchedBarGroupIndex, i);
              expect(
                hit.spot!.offset.dx,
                closeTo(columnRect.center.dx - plotRect.left, .1),
              );
            }
          }
          expect(data.minY, lessThanOrEqualTo(values.reduce(math.min)));
          expect(data.maxY, greaterThan(values.reduce(math.max)));
          for (final summary in ['net-worth', 'portfolio']) {
            final textRect = tester
                .getRect(find.byKey(Key('$summary-summary-title')))
                .expandToInclude(
                  tester.getRect(find.byKey(Key('$summary-summary-values'))),
                );
            expect(
              tester.getCenter(find.byKey(Key('$summary-summary-icon'))).dy,
              closeTo(textRect.center.dy, 1),
            );
            final card = find.ancestor(
              of: find.byKey(Key('$summary-summary-icon')),
              matching: find.byType(EquisGlassCard),
            );
            expect(textRect.bottom, lessThan(tester.getRect(card).bottom));
            expect(textRect.top, greaterThan(tester.getRect(card).top));
          }
          if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] == '1') {
            await _captureDashboard(
              tester,
              'compact-${brightness.name}-${amounts.$1}-${amounts.$2}',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final locale in [const Locale('en', 'US'), const Locale('pt', 'BR')]) {
    testWidgets(
      'loaded summaries fit narrow screens with large text: $locale',
      (tester) async {
        final harness = _TagDashboardHarness(
          const [],
          locale: locale,
          textScale: 2,
          loadedPositionReports: true,
          incompletePositionReports: true,
          incomeMinor: 123456,
          expenseMinor: 234567,
          captureKey: const Key('dashboard-layout-capture'),
        );
        await harness.pump(tester, size: const Size(320, 1600));
        final chart = tester.widget<BarChart>(find.byType(BarChart));
        expect(chart.data.barGroups.length, 3);
        expect(chart.data.minY, lessThan(-1111.11));
        expect(tester.takeException(), isNull);
        if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] == '1') {
          await _captureDashboard(
            tester,
            'compact-large-loaded-${locale.toLanguageTag()}',
          );
        }
      },
    );
  }
  testWidgets(
    'compact flow menu shows its title on hover and opens by keyboard',
    (tester) async {
      final harness = _TagDashboardHarness(const []);
      await harness.pump(tester, size: const Size(1280, 1600));
      final menu = find.byKey(const ValueKey('dashboard-mode-daily'));
      final l = AppLocalizations.of(tester.element(menu));
      expect(find.text(l.dashboardFlowModeLabel), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(menu));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l.dashboardFlowModeLabel), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<CashFlowMode>), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<CashFlowMode>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in [const Locale('pt', 'BR'), const Locale('en', 'US')]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('empty reports stay usable with large text: $locale $width', (
        tester,
      ) async {
        final harness = _TagDashboardHarness(
          const [],
          locale: locale,
          textScale: 2,
          brightness: Brightness.dark,
          captureKey: const Key('dashboard-layout-capture'),
        );
        await harness.pump(tester, size: Size(width, 1600));
        final l = AppLocalizations.of(
          tester.element(find.byType(DashboardOverview)),
        );
        await tester.ensureVisible(find.text(l.tagsTitle));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.tagsTitle));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width >= 900) {
          expect(
            tester
                .getSize(find.byKey(const Key('cash-flow-report-card')))
                .height,
            closeTo(
              tester
                  .getSize(find.byKey(const Key('dashboard-spending-card')))
                  .height,
              .1,
            ),
          );
        }
        if (Platform.environment['EQUIS_CAPTURE_DASHBOARD'] == '1') {
          await _captureDashboard(
            tester,
            'large-${locale.toLanguageTag()}-${width.toInt()}',
          );
        }
      });
    }
    testWidgets(
      'RC15–16 mode and period controls keep exact totals in narrow layout: $locale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final vault = EntityId.generate();
        final finance = LocalFinanceSnapshot(
          vault: VaultProfile(
            id: vault,
            name: 'Local',
            baseCurrency: CurrencyCode.brl,
            locale: locale.toLanguageTag(),
            timezone: 'UTC',
            createdAt: const UtcInstant.fromEpochMicroseconds(1),
            updatedAt: const UtcInstant.fromEpochMicroseconds(1),
          ),
        );
        final controller = DashboardController(
          service: null,
          vaultId: null,
          reportingCurrency: null,
          clock: () => DateTime(2026, 3, 10),
          loader: (range, asOf) async => DashboardSnapshot(
            reportingCurrency: CurrencyCode.brl,
            periodStart: range.from,
            periodEnd: range.through,
            availableMoneyMinor: 999,
            incomeMinor: 300,
            expenseMinor: 30,
            spendingByCategory: const [],
            cashFlow: [
              for (
                var date = range.from;
                date.compareTo(range.through) <= 0;
                date = date.addDays(1)
              )
                CashFlowPoint(
                  date: date,
                  incomeMinor: date == range.from
                      ? 100
                      : date == range.from.addDays(1)
                      ? 200
                      : 0,
                  expenseMinor: date == range.from
                      ? 40
                      : date == range.from.addDays(1)
                      ? -10
                      : 0,
                ),
            ],
            accountBalances: const [],
            missingRates: const {},
            usesEstimatedRates: false,
            upcomingCount: 0,
          ),
        );
        await controller.reload();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dashboardControllerProvider.overrideWith((ref) => controller),
            ],
            child: MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DashboardOverview(finance: finance),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(DashboardOverview)),
        );
        await tester.tap(find.byKey(const ValueKey('dashboard-mode-daily')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.dashboardCumulativeLabel).last);
        await tester.pumpAndSettle();
        expect(controller.state.selection.mode, CashFlowMode.cumulative);
        await tester.ensureVisible(find.byType(LineChart));
        await tester.pumpAndSettle();
        final chart = tester.widget<LineChart>(find.byType(LineChart));
        expect(chart.data.lineBarsData.first.spots.last.y, 3);
        expect(chart.data.lineBarsData.last.spots.last.y, .3);
        expect(controller.state.snapshot!.availableMoneyMinor, 999);
        await tester.ensureVisible(
          find.byKey(const ValueKey('dashboard-range-thisMonth')),
        );
        await tester.tap(
          find.byKey(const ValueKey('dashboard-range-thisMonth')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.dashboardLastMonthLabel).last);
        await tester.pumpAndSettle();
        expect(controller.state.snapshot!.periodStart, LocalDate(2026, 2, 1));
        expect(controller.state.snapshot!.periodEnd, LocalDate(2026, 2, 28));
        expect(tester.takeException(), isNull);
      },
    );
  }
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
        expect(filter.toDate, LocalDate(2026, 8, 31));
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
        expect(filter.toDate, LocalDate(2026, 8, 31));
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

Future<void> _captureDashboard(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('dashboard-layout-capture')),
  );
  await tester.runAsync(() async {
    final directory = Directory('.tooling/dashboard-layout-captures');
    await directory.create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
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
    this.locale = const Locale('en', 'US'),
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.loadedPositionReports = false,
    this.incompletePositionReports = false,
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
  final Locale locale;
  final int incomeMinor;
  final int expenseMinor;
  final bool loadedPositionReports;
  final bool incompletePositionReports;
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
            backgroundColor: Theme.of(context).canvasColor,
            body: RepaintBoundary(
              key: captureKey,
              child: EquisThemeBackdrop(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 16),
                  child: DashboardOverview(
                    investmentStateOverride: loadedPositionReports
                        ? InvestmentState(
                            report: PortfolioReport(
                              currency: CurrencyCode.usd,
                              holdings: const [],
                              marketValueMinor: 56789,
                              costBasisMinor: 50000,
                              unrealizedMinor: 6789,
                              realizedMinor: 0,
                              incomeMinor: 0,
                              hasIncompleteAccountSync:
                                  incompletePositionReports,
                            ),
                          )
                        : null,
                    wealthStateOverride: loadedPositionReports
                        ? WealthState(
                            report: NetWorthReport(
                              currency: CurrencyCode.usd,
                              current: NetWorthPoint(
                                date: periodEnd,
                                assetsMinor: 123456,
                                liabilitiesMinor: 0,
                                missingRates: const {},
                                usesEstimatedRates: false,
                                hasIncompleteAccounts:
                                    incompletePositionReports,
                              ),
                              history: const [],
                              physicalAssets: const [],
                            ),
                          )
                        : null,
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
                      incomeMinor: incomeMinor,
                      expenseMinor: expenseMinor,
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
          locale: locale,
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
