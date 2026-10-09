import 'dart:async';
import 'package:equis/application/ports/local_experience_preferences.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/presentation/home/dashboard_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'presets cross year boundaries, custom validates, accumulation keeps exact signed totals',
    () {
      final today = LocalDate(2026, 1, 15);
      expect(
        const DashboardSelection(
          preset: DashboardRangePreset.lastMonth,
        ).resolve(today).from,
        LocalDate(2025, 12, 1),
      );
      expect(
        const DashboardSelection(
          preset: DashboardRangePreset.lastMonth,
        ).resolve(today).through,
        LocalDate(2025, 12, 31),
      );
      expect(
        const DashboardSelection(
          preset: DashboardRangePreset.lastThreeMonths,
        ).resolve(today).from,
        LocalDate(2025, 11, 1),
      );
      expect(
        () => DashboardDateRange(from: today, through: today.addDays(-1)),
        throwsArgumentError,
      );
      expect(
        () => DashboardSelection(
          preset: DashboardRangePreset.custom,
          customRange: DashboardDateRange(
            from: today,
            through: today.addDays(1),
          ),
        ).resolve(today),
        throwsArgumentError,
      );
      final daily = [
        CashFlowPoint(date: today, incomeMinor: 100, expenseMinor: 80),
        CashFlowPoint(
          date: today.addDays(1),
          incomeMinor: -10,
          expenseMinor: -5,
        ),
        CashFlowPoint(date: today.addDays(2), incomeMinor: 0, expenseMinor: 0),
      ];
      expect(cashFlowSeries(daily, CashFlowMode.daily)[1].incomeMinor, -10);
      final curve = cashFlowSeries(daily, CashFlowMode.cumulative);
      expect(curve.map((p) => p.incomeMinor), [100, 90, 90]);
      expect(curve.last.expenseMinor, 75);
      expect(curve.first.netMinor, 20);
    },
  );

  test(
    'latest selection wins older success and error; writes serialize and profile is captured',
    () async {
      final requests = <Completer<DashboardSnapshot>>[];
      final settings = _Preferences();
      final controller = DashboardController(
        service: null,
        vaultId: null,
        reportingCurrency: null,
        profileId: 'A',
        preferences: settings,
        clock: () => DateTime(2026, 3, 10),
        loader: (range, asOf) {
          final pending = Completer<DashboardSnapshot>();
          requests.add(pending);
          return pending.future;
        },
      );
      addTearDown(controller.dispose);
      final first = controller.reload();
      await Future<void>.delayed(Duration.zero);
      final second = controller.select(
        const DashboardSelection(preset: DashboardRangePreset.lastMonth),
      );
      final third = controller.select(
        const DashboardSelection(
          preset: DashboardRangePreset.thisYear,
          mode: CashFlowMode.cumulative,
        ),
      );
      requests[2].complete(
        _snapshot(LocalDate(2026, 1, 1), LocalDate(2026, 3, 10), 300),
      );
      await third;
      requests[1].completeError(StateError('stale failure'));
      requests[0].complete(
        _snapshot(LocalDate(2026, 3, 1), LocalDate(2026, 3, 10), 100),
      );
      await Future.wait([first, second]);
      expect(controller.state.snapshot!.incomeMinor, 300);
      expect(controller.state.error, isNull);
      expect(settings.writes.map((entry) => entry.$1), ['A', 'A']);
      expect(settings.writes.last.$2.mode, CashFlowMode.cumulative);
    },
  );

  test(
    'late preference read cannot overwrite user selection, disposal ignores a late result',
    () async {
      final settings = _Preferences()
        ..readGate = Completer<LocalExperienceSettings>();
      final requests = <Completer<DashboardSnapshot>>[];
      final controller = DashboardController(
        service: null,
        vaultId: null,
        reportingCurrency: null,
        preferences: settings,
        clock: () => DateTime(2026, 3, 10),
        loader: (range, asOf) {
          final pending = Completer<DashboardSnapshot>();
          requests.add(pending);
          return pending.future;
        },
      );
      final first = controller.reload();
      final selection = controller.select(
        const DashboardSelection(preset: DashboardRangePreset.lastMonth),
      );
      settings.readGate!.complete(
        const LocalExperienceSettings(
          dashboard: DashboardSelection(preset: DashboardRangePreset.thisYear),
        ),
      );
      await first;
      expect(controller.state.selection.preset, DashboardRangePreset.lastMonth);
      controller.dispose();
      requests.single.complete(
        _snapshot(LocalDate(2026, 2, 1), LocalDate(2026, 2, 28), 5),
      );
      await selection;
    },
  );

  test(
    'future saved custom interval falls back visibly; persistence failure keeps current selection',
    () async {
      final settings = _Preferences()
        ..saved = LocalExperienceSettings(
          dashboard: DashboardSelection(
            preset: DashboardRangePreset.custom,
            customRange: DashboardDateRange(
              from: LocalDate(2026, 1, 1),
              through: LocalDate(2027, 1, 1),
            ),
          ),
        );
      final controller = DashboardController(
        service: null,
        vaultId: null,
        reportingCurrency: null,
        preferences: settings,
        clock: () => DateTime(2026, 3, 10),
        loader: (range, asOf) async => _snapshot(range.from, range.through, 0),
      );
      addTearDown(controller.dispose);
      await controller.reload();
      expect(controller.state.invalidSelection, isTrue);
      expect(controller.state.selection.preset, DashboardRangePreset.thisMonth);
      settings.failWrites = true;
      await controller.select(
        const DashboardSelection(preset: DashboardRangePreset.lastMonth),
      );
      expect(controller.state.selection.preset, DashboardRangePreset.lastMonth);
      expect(controller.state.preferenceError, isNotNull);
      expect(controller.state.invalidSelection, isFalse);
    },
  );
}

DashboardSnapshot _snapshot(LocalDate from, LocalDate through, int income) =>
    DashboardSnapshot(
      reportingCurrency: CurrencyCode.brl,
      periodStart: from,
      periodEnd: through,
      availableMoneyMinor: 999,
      incomeMinor: income,
      expenseMinor: 0,
      spendingByCategory: const [],
      cashFlow: const [],
      accountBalances: const [],
      missingRates: const {},
      usesEstimatedRates: false,
      upcomingCount: 0,
    );

final class _Preferences implements LocalExperiencePreferences {
  final writes = <(String, DashboardSelection)>[];
  Completer<LocalExperienceSettings>? readGate;
  LocalExperienceSettings saved = const LocalExperienceSettings();
  bool failWrites = false;
  @override
  Future<LocalExperienceSettings> readProfile(String id) =>
      readGate?.future ?? Future.value(saved);
  @override
  Future<void> saveDashboard(String id, DashboardSelection selection) async {
    if (failWrites) throw const ExperiencePreferenceWriteFailure();
    writes.add((id, selection));
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> setChecklistHidden(String id, bool hidden) async {}
  @override
  Future<void> markBackupCreated(String id) async {}
  @override
  Future<bool> hasSeenGuide() async => false;
  @override
  Future<void> markGuideSeen() async {}
}
