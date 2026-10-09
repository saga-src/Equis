import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../application/ports/local_experience_preferences.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/local_date.dart';

final class SharedPreferencesExperienceStore
    implements LocalExperiencePreferences {
  static LocalExperiencePreferences deferred(String installationNamespace) =>
      _DeferredExperienceStore(
        () async => SharedPreferencesExperienceStore(
          await SharedPreferences.getInstance(),
          installationNamespace: installationNamespace,
        ),
      );
  SharedPreferencesExperienceStore(
    this.preferences, {
    required String installationNamespace,
    this.writeValue,
  }) : namespace = Uri.encodeComponent(installationNamespace);
  final SharedPreferences preferences;
  final String namespace;
  final Future<bool> Function(String key, Object value)? writeValue;
  Future<void> _tail = Future.value();
  String get guideKey => 'equis.guide.seen.v1.$namespace';
  String profileKey(String id) =>
      'equis.experience.v1.$namespace.${Uri.encodeComponent(id)}';

  Map<String, dynamic> _read(String id) {
    try {
      final text = preferences.getString(profileKey(id));
      return text == null
          ? {}
          : Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      return {};
    }
  }

  @override
  Future<LocalExperienceSettings> readProfile(String profileId) async {
    final data = _read(profileId);
    DashboardSelection selection;
    try {
      final dashboard = data['dashboard'] as Map?;
      if (dashboard == null) {
        selection = const DashboardSelection();
      } else {
        final preset = DashboardRangePreset.values.byName(
          dashboard['preset'] as String,
        );
        selection = DashboardSelection(
          preset: preset,
          mode: CashFlowMode.values.byName(dashboard['mode'] as String),
          customRange: preset == DashboardRangePreset.custom
              ? DashboardDateRange(
                  from: LocalDate.parse(dashboard['from'] as String),
                  through: LocalDate.parse(dashboard['through'] as String),
                )
              : null,
        );
      }
    } catch (_) {
      selection = const DashboardSelection();
    }
    return LocalExperienceSettings(
      dashboard: selection,
      checklistHidden: data['checklist_hidden'] == true,
      backupCreated: data['backup_created'] == true,
    );
  }

  Future<void> _write(Future<bool> Function() action) {
    final result = _tail.then((_) async {
      if (!await action()) {
        // The legacy plugin updates its memory cache before reporting the
        // platform result. Reload it so failed writes cannot appear completed.
        await preferences.reload();
        throw const ExperiencePreferenceWriteFailure();
      }
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _update(String id, String key, Object value) => _write(() async {
    final data = _read(id)..[key] = value;
    return writeValue?.call(profileKey(id), jsonEncode(data)) ??
        preferences.setString(profileKey(id), jsonEncode(data));
  });
  @override
  Future<void> saveDashboard(String profileId, DashboardSelection selection) =>
      _update(profileId, 'dashboard', {
        'preset': selection.preset.name,
        'mode': selection.mode.name,
        if (selection.preset == DashboardRangePreset.custom) ...{
          'from': selection.customRange!.from.toString(),
          'through': selection.customRange!.through.toString(),
        },
      });
  @override
  Future<void> setChecklistHidden(String profileId, bool hidden) =>
      _update(profileId, 'checklist_hidden', hidden);
  @override
  Future<void> markBackupCreated(String profileId) =>
      _update(profileId, 'backup_created', true);
  @override
  Future<bool> hasSeenGuide() async {
    try {
      return preferences.getBool(guideKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> markGuideSeen() => _write(
    () =>
        writeValue?.call(guideKey, true) ?? preferences.setBool(guideKey, true),
  );
}

final class _DeferredExperienceStore implements LocalExperiencePreferences {
  _DeferredExperienceStore(this.open);
  final Future<LocalExperiencePreferences> Function() open;
  Future<LocalExperiencePreferences>? _pending;
  Future<LocalExperiencePreferences> get store => _pending ??= open();
  @override
  Future<LocalExperienceSettings> readProfile(String profileId) async =>
      (await store).readProfile(profileId);
  @override
  Future<void> saveDashboard(
    String profileId,
    DashboardSelection selection,
  ) async => (await store).saveDashboard(profileId, selection);
  @override
  Future<void> setChecklistHidden(String profileId, bool hidden) async =>
      (await store).setChecklistHidden(profileId, hidden);
  @override
  Future<void> markBackupCreated(String profileId) async =>
      (await store).markBackupCreated(profileId);
  @override
  Future<bool> hasSeenGuide() async => (await store).hasSeenGuide();
  @override
  Future<void> markGuideSeen() async => (await store).markGuideSeen();
}
