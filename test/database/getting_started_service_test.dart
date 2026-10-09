import 'package:drift/native.dart';
import 'package:equis/application/services/getting_started_service.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_getting_started_repository.dart';
import 'package:equis/infrastructure/settings/shared_preferences_experience_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'RC02 EXISTS sees old real records beyond recent 20, archived accounts and profile-local backup',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      SharedPreferences.setMockInitialValues({
        'last_portable_backup': '{"name":"legacy.equis"}',
      });
      final prefs = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'fixture',
      );
      final service = GettingStartedService(
        repository: DriftGettingStartedRepository(database),
        preferences: prefs,
      );
      final vault = EntityId.generate(), otherVault = EntityId.generate();
      for (final id in [vault, otherVault]) {
        await database.customStatement(
          "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES (?, 'Local', 'BRL', 'UTC', 1, 1)",
          [id.value],
        );
      }
      var status = await service.load(vaultId: vault, profileId: 'A');
      expect(status.facts.hasAccount, isFalse);
      expect(status.backupCreated, isFalse);
      final account = EntityId.generate(),
          budget = EntityId.generate(),
          old = EntityId.generate();
      await database.customStatement(
        "INSERT INTO accounts (id, vault_id, name, account_type, nature, archived, created_at, updated_at) VALUES (?, ?, 'Archived', 'checking', 'asset', 1, 1, 1)",
        [account.value, vault.value],
      );
      await database.customStatement(
        "INSERT INTO budgets (id, vault_id, name, currency_code, limit_minor, period_type, created_at, updated_at) VALUES (?, ?, 'Plan', 'BRL', 100, 'monthly', 1, 1)",
        [budget.value, vault.value],
      );
      for (var index = 0; index < 26; index++) {
        await database.customStatement(
          'INSERT INTO transactions (id, vault_id, transaction_type, status, financial_date, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            index == 0 ? old.value : EntityId.generate().value,
            vault.value,
            'expense',
            index == 0 ? 'cleared' : 'cancelled',
            '2026-01-01',
            index + 1,
            index + 1,
          ],
        );
      }
      status = await service.load(vaultId: vault, profileId: 'A');
      expect(status.facts.hasAccount, isTrue);
      expect(status.facts.hasTransaction, isTrue);
      expect(status.facts.hasBudget, isTrue);
      expect(status.backupCreated, isFalse);
      await prefs.markBackupCreated('A');
      await prefs.setChecklistHidden('A', true);
      status = await service.load(vaultId: vault, profileId: 'A');
      expect(status.complete, isTrue);
      expect(status.hidden, isTrue);
      final other = await service.load(vaultId: otherVault, profileId: 'B');
      expect(other.facts.hasAccount, isFalse);
      expect(other.facts.hasTransaction, isFalse);
      expect(other.backupCreated, isFalse);
      expect(other.hidden, isFalse);
      await database.customStatement(
        'UPDATE transactions SET deleted_at = 1 WHERE id = ?',
        [old.value],
      );
      await database.customStatement(
        'UPDATE budgets SET deleted_at = 1 WHERE id = ?',
        [budget.value],
      );
      status = await service.load(vaultId: vault, profileId: 'A');
      expect(status.facts.hasTransaction, isFalse);
      expect(status.facts.hasBudget, isFalse);
    },
  );

  test(
    'RC01 welcome is marked before navigation, skip/restart/profile changes do not reopen',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'welcome-test',
      );
      final gate = WelcomeGuideGate(prefs);
      final decision = await gate.check();
      expect(decision.show, isTrue);
      expect(await prefs.hasSeenGuide(), isTrue);
      expect((await gate.check()).show, isFalse);
      expect((await WelcomeGuideGate(prefs).check()).show, isFalse);
      final otherInstall = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'another',
      );
      expect((await WelcomeGuideGate(otherInstall).check()).show, isTrue);
    },
  );

  test(
    'guide persistence failure leaves access usable and is attempted once per session',
    () async {
      SharedPreferences.setMockInitialValues({});
      var attempts = 0;
      final prefs = SharedPreferencesExperienceStore(
        await SharedPreferences.getInstance(),
        installationNamespace: 'failed',
        writeValue: (key, value) async {
          attempts++;
          return false;
        },
      );
      final gate = WelcomeGuideGate(prefs);
      expect((await gate.check()).preferenceError, isNotNull);
      expect((await gate.check()).show, isFalse);
      expect(attempts, 1);
      expect(await prefs.hasSeenGuide(), isFalse);
      await WelcomeGuideGate(prefs).check();
      expect(attempts, 2);
    },
  );
}
