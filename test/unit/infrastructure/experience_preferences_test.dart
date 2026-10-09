import 'dart:async';
import 'dart:convert';
import 'package:equis/application/ports/local_experience_preferences.dart';
import 'package:equis/domain/reporting/dashboard_models.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/infrastructure/settings/shared_preferences_experience_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'restart and profile/installation isolation include welcome and checklist',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final a = SharedPreferencesExperienceStore(
        prefs,
        installationNamespace: 'F:/one',
      );
      final b = SharedPreferencesExperienceStore(
        prefs,
        installationNamespace: 'F:/two',
      );
      await a.markGuideSeen();
      await a.markBackupCreated('A');
      await a.setChecklistHidden('A', true);
      await a.saveDashboard(
        'A',
        const DashboardSelection(
          preset: DashboardRangePreset.lastThreeMonths,
          mode: CashFlowMode.cumulative,
        ),
      );
      final restarted = SharedPreferencesExperienceStore(
        prefs,
        installationNamespace: 'F:/one',
      );
      expect(await restarted.hasSeenGuide(), isTrue);
      final saved = await restarted.readProfile('A');
      expect(saved.backupCreated, isTrue);
      expect(saved.checklistHidden, isTrue);
      expect(saved.dashboard.mode, CashFlowMode.cumulative);
      expect(
        saved.dashboard.resolve(LocalDate(2027, 1, 10)).from,
        LocalDate(2026, 11, 1),
      );
      expect((await a.readProfile('B')).backupCreated, isFalse);
      expect((await b.readProfile('A')).checklistHidden, isFalse);
      expect(await b.hasSeenGuide(), isFalse);
      final encoded = jsonDecode(prefs.getString(a.profileKey('A'))!) as Map;
      expect((encoded['dashboard'] as Map).containsKey('from'), isFalse);
    },
  );
  test(
    'custom stores exact ISO dates; corrupt keys restore defaults',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesExperienceStore(
        prefs,
        installationNamespace: 'root',
      );
      await store.saveDashboard(
        'A',
        DashboardSelection(
          preset: DashboardRangePreset.custom,
          customRange: DashboardDateRange(
            from: LocalDate(2026, 1, 15),
            through: LocalDate(2026, 3, 10),
          ),
        ),
      );
      expect(
        (await store.readProfile('A')).dashboard.customRange!.through,
        LocalDate(2026, 3, 10),
      );
      await prefs.setString(store.profileKey('A'), 'broken');
      expect(
        (await store.readProfile('A')).dashboard.preset,
        DashboardRangePreset.thisMonth,
      );
      await prefs.setString(
        store.profileKey('A'),
        '{"dashboard":{"preset":"removed","mode":"daily"}}',
      );
      expect(
        (await store.readProfile('A')).dashboard.preset,
        DashboardRangePreset.thisMonth,
      );
    },
  );
  test(
    'failed bool result is explicit and does not mark guide or backup',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesExperienceStore(
        prefs,
        installationNamespace: 'root',
        writeValue: (key, value) async => false,
      );
      await expectLater(
        store.markGuideSeen(),
        throwsA(isA<ExperiencePreferenceWriteFailure>()),
      );
      await expectLater(
        store.markBackupCreated('A'),
        throwsA(isA<ExperiencePreferenceWriteFailure>()),
      );
      expect(await store.hasSeenGuide(), isFalse);
      expect((await store.readProfile('A')).backupCreated, isFalse);
    },
  );
  test(
    'queued writes retain independent fields and finish in selection order',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gate = Completer<void>();
      var calls = 0;
      final store = SharedPreferencesExperienceStore(
        prefs,
        installationNamespace: 'root',
        writeValue: (key, value) async {
          if (++calls == 1) await gate.future;
          return prefs.setString(key, value as String);
        },
      );
      final first = store.saveDashboard(
        'A',
        const DashboardSelection(preset: DashboardRangePreset.lastMonth),
      );
      final second = store.saveDashboard(
        'A',
        const DashboardSelection(preset: DashboardRangePreset.thisYear),
      );
      final hidden = store.setChecklistHidden('A', true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      gate.complete();
      await Future.wait([first, second, hidden]);
      final saved = await store.readProfile('A');
      expect(saved.dashboard.preset, DashboardRangePreset.thisYear);
      expect(saved.checklistHidden, isTrue);
    },
  );
}
