import '../../domain/reporting/dashboard_models.dart';

final class LocalExperienceSettings {
  const LocalExperienceSettings({
    this.dashboard = const DashboardSelection(),
    this.checklistHidden = false,
    this.backupCreated = false,
  });
  final DashboardSelection dashboard;
  final bool checklistHidden;
  final bool backupCreated;
}

abstract interface class LocalExperiencePreferences {
  Future<LocalExperienceSettings> readProfile(String profileId);
  Future<void> saveDashboard(String profileId, DashboardSelection selection);
  Future<void> setChecklistHidden(String profileId, bool hidden);
  Future<void> markBackupCreated(String profileId);
  Future<bool> hasSeenGuide();
  Future<void> markGuideSeen();
}

final class ExperiencePreferenceWriteFailure implements Exception {
  const ExperiencePreferenceWriteFailure();
}
