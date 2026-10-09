import 'dart:async';
import 'package:equis/application/services/getting_started_service.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/settings/shared_preferences_experience_store.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/home/getting_started_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'RC03 backup creation/validation/publish failures and cancellation never mark checklist',
    () async {
      final prefs = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'backup',
      );
      final captured = BackupChecklistOperation(
        preferences: prefs,
        profileId: 'A',
        vaultId: EntityId.generate(),
      );
      for (final failure in ['create', 'validate', 'publish', 'cancel']) {
        final operation = publishCheckedBackup(
          create: () async {
            if (failure == 'create') throw StateError('create');
          },
          validate: () async {
            if (failure == 'validate') throw StateError('validate');
          },
          publish: () async {
            if (failure == 'publish') throw StateError('publish');
            return failure == 'cancel' ? null : {'uri': 'fixture'};
          },
          checklist: captured,
        );
        if (failure == 'cancel') {
          expect(await operation, isNull);
        } else {
          await expectLater(operation, throwsStateError);
        }
        expect((await prefs.readProfile('A')).backupCreated, isFalse);
      }
    },
  );
  test(
    'RC03 successful publish marks captured profile after completion; failure distinguishes saved file',
    () async {
      final prefs = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'backup',
      );
      final captured = BackupChecklistOperation(
        preferences: prefs,
        profileId: 'A',
        vaultId: EntityId.generate(),
      );
      final gate = Completer<Map<String, String>?>();
      final operation = publishCheckedBackup(
        create: () async {},
        validate: () async {},
        publish: () => gate.future,
        checklist: captured,
      );
      await Future<void>.delayed(Duration.zero);
      expect((await prefs.readProfile('A')).backupCreated, isFalse);
      // A different profile is now active; the operation still belongs to A.
      await prefs.setChecklistHidden('B', true);
      gate.complete({'uri': 'fixture.equis'});
      final published = await operation;
      expect(published!.preferenceError, isNull);
      expect((await prefs.readProfile('A')).backupCreated, isTrue);
      expect((await prefs.readProfile('B')).backupCreated, isFalse);
      final failed = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'failed',
        writeValue: (key, value) async => false,
      );
      final result = await publishCheckedBackup(
        create: () async {},
        validate: () async {},
        publish: () async => {'uri': 'saved'},
        checklist: BackupChecklistOperation(
          preferences: failed,
          profileId: 'A',
          vaultId: EntityId.generate(),
        ),
      );
      expect(result!.destination['uri'], 'saved');
      expect(result.preferenceError, isNotNull);
      expect((await failed.readProfile('A')).backupCreated, isFalse);
    },
  );
  for (final locale in [const Locale('pt', 'BR'), const Locale('en', 'US')]) {
    for (final width in [360.0, 1280.0]) {
      testWidgets(
        'checklist renders completed/pending states, hiding failure is visible: $locale $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  locale: locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: GettingStartedChecklist(
                        statusOverride: const GettingStartedStatus(
                          facts: GettingStartedFacts(
                            hasAccount: true,
                            hasTransaction: true,
                            hasBudget: true,
                          ),
                          hidden: false,
                          backupCreated: false,
                        ),
                        onHide: () async => throw StateError('preference'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final l10n = AppLocalizations.of(
              tester.element(find.byType(GettingStartedChecklist)),
            );
            expect(find.text(l10n.checklistDoneLabel), findsNWidgets(3));
            expect(find.text(l10n.checklistPendingLabel), findsOneWidget);
            await tester.ensureVisible(find.byKey(const Key('checklist-hide')));
            await tester.tap(find.byKey(const Key('checklist-hide')));
            await tester.pumpAndSettle();
            expect(
              find.text(l10n.experiencePreferenceFailedMessage),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
