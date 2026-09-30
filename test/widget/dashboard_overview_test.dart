import 'dart:math' as math;

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
import 'package:equis/presentation/home/dashboard_overview.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
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

      expect(find.byKey(const Key('tag-bubble-grid')), findsOneWidget);
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
      expect(largestDiameter, closeTo(128, 0.01));
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
    expect(largestDiameter, closeTo(128, 0.01));
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
    expect(find.byKey(const Key('tag-bubble-grid')), findsNothing);
    expect(find.text('Other tag values'), findsNothing);
    expect(tester.takeException(), isNull);
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
        if (find.byKey(const Key('tag-bubble-grid')).evaluate().isEmpty) {
          await _showTags(tester);
        }
        expect(find.byKey(const Key('tag-bubble-grid')), findsOneWidget);
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
}

Future<void> _showTags(WidgetTester tester) async {
  await tester.tap(find.text('Tags'));
  await tester.pumpAndSettle();
}

String _tagLabel(EntityId id) => 'Tag ${id.value.substring(28)}';

class _TagDashboardHarness {
  _TagDashboardHarness(this.values, {this.tagNames = const {}})
    : vaultId = EntityId.generate(),
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
            body: SingleChildScrollView(
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
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
