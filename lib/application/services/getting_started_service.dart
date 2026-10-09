import '../ports/local_experience_preferences.dart';
import '../../domain/shared/uuid_v7.dart';

final class GettingStartedFacts {
  const GettingStartedFacts({
    required this.hasAccount,
    required this.hasTransaction,
    required this.hasBudget,
  });
  final bool hasAccount;
  final bool hasTransaction;
  final bool hasBudget;
}

abstract interface class GettingStartedRepository {
  Future<GettingStartedFacts> facts(EntityId vaultId);
}

final class GettingStartedStatus {
  const GettingStartedStatus({
    required this.facts,
    required this.hidden,
    required this.backupCreated,
  });
  final GettingStartedFacts facts;
  final bool hidden;
  final bool backupCreated;
  bool get complete =>
      facts.hasAccount &&
      facts.hasTransaction &&
      facts.hasBudget &&
      backupCreated;
}

final class GettingStartedService {
  const GettingStartedService({
    required this.repository,
    required this.preferences,
  });
  final GettingStartedRepository repository;
  final LocalExperiencePreferences preferences;
  Future<GettingStartedStatus> load({
    required EntityId vaultId,
    required String profileId,
  }) async {
    final facts = await repository.facts(vaultId);
    final saved = await preferences.readProfile(profileId);
    return GettingStartedStatus(
      facts: facts,
      hidden: saved.checklistHidden,
      backupCreated: saved.backupCreated,
    );
  }
}

final class WelcomeDecision {
  const WelcomeDecision({this.show = false, this.preferenceError});
  final bool show;
  final Object? preferenceError;
}

final class WelcomeGuideGate {
  WelcomeGuideGate(this.preferences);
  final LocalExperiencePreferences preferences;
  static final _installations = <String, WelcomeGuideGate>{};
  static WelcomeGuideGate forInstallation(
    String namespace,
    LocalExperiencePreferences preferences,
  ) => _installations.putIfAbsent(
    namespace,
    () => WelcomeGuideGate(preferences),
  );
  bool _attempted = false;
  Future<WelcomeDecision> check() async {
    if (_attempted) return const WelcomeDecision();
    _attempted = true;
    try {
      if (await preferences.hasSeenGuide()) return const WelcomeDecision();
      await preferences.markGuideSeen();
      return const WelcomeDecision(show: true);
    } catch (error) {
      return WelcomeDecision(preferenceError: error);
    }
  }
}

// Capture this operation before asking for a password or opening a picker.
// Only a confirmed publish can complete the captured profile's checklist.
final class BackupChecklistOperation {
  const BackupChecklistOperation({
    required this.preferences,
    required this.profileId,
    required this.vaultId,
  });
  final LocalExperiencePreferences preferences;
  final String profileId;
  final EntityId vaultId;
  Future<Object?> complete({required bool published}) async {
    if (!published) return null;
    try {
      await preferences.markBackupCreated(profileId);
      return null;
    } catch (error) {
      return error;
    }
  }
}

final class BackupPublicationResult {
  const BackupPublicationResult({
    required this.destination,
    this.preferenceError,
  });
  final Map<String, String> destination;
  final Object? preferenceError;
}

Future<BackupPublicationResult?> publishCheckedBackup({
  required Future<void> Function() create,
  required Future<void> Function() validate,
  required Future<Map<String, String>?> Function() publish,
  BackupChecklistOperation? checklist,
}) async {
  await create();
  await validate();
  final destination = await publish();
  if (destination == null) return null;
  final error = await checklist?.complete(published: true);
  return BackupPublicationResult(
    destination: Map.unmodifiable(destination),
    preferenceError: error,
  );
}
