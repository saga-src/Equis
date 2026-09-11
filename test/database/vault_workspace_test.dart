import 'dart:io';
import 'package:equis/app/vault_workspace.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'isolates local vault databases and restores one canonical key on another device',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'equis-workspace-v2-',
      );
      final firstStore = _Store();
      final secondStore = _Store();
      final first = await VaultWorkspace.open(
        rootDirectory: Directory('${directory.path}/first'),
        storage: firstStore,
        cloudEnabled: false,
      );
      final second = await VaultWorkspace.open(
        rootDirectory: Directory('${directory.path}/second'),
        storage: secondStore,
        cloudEnabled: false,
      );
      addTearDown(() async {
        await first.active?.close();
        await second.active?.close();
        await directory.delete(recursive: true);
      });
      Future<void> setup(VaultWorkspace workspace, String name) async {
        await workspace.active!.session.setupLocalVault(
          profileName: name,
          accountName: '$name account',
          currency: CurrencyCode('BRL'),
          locale: 'pt-BR',
          timezone: 'America/Sao_Paulo',
          now: UtcInstant.now(),
        );
        await workspace.refresh();
      }

      await setup(first, 'First');
      final entry = first.selected!;
      final identity = await first.active!.vaultKeys.requireVault(
        entry.vaultId!,
      );
      final backup = File('${directory.path}/canonical.equis');
      await first.active!.backups.create(
        vaultId: identity.vaultId,
        password: 'a sufficiently long password',
        destination: backup,
      );
      await first.create();
      await setup(first, 'Second');
      expect(first.selected!.vaultId, isNot(identity.vaultId));
      expect(
        (await first.active!.session.load()).accounts.single.account.name,
        'Second account',
      );
      await first.select(entry);
      expect(
        (await first.active!.session.load()).accounts.single.account.name,
        'First account',
      );
      final count = first.entries.length;
      await first.restoreBackup(backup, 'a sufficiently long password');
      expect(first.entries.length, count);
      await second.restoreBackup(backup, 'a sufficiently long password');
      expect(
        await (await second.active!.vaultKeys.requireVault(
          identity.vaultId,
        )).fingerprint(),
        await identity.fingerprint(),
      );
      expect(
        (await second.active!.session.load()).accounts.single.account.name,
        'First account',
      );
      final firstDbKeys = firstStore.values.entries
          .where((e) => e.key.contains('.database.') && e.key.endsWith('v1'))
          .map((e) => e.value)
          .toSet();
      final secondDbKeys = secondStore.values.entries
          .where((e) => e.key.contains('.database.') && e.key.endsWith('v1'))
          .map((e) => e.value)
          .toSet();
      expect(firstDbKeys.intersection(secondDbKeys), isEmpty);
      final before = second.entries.length;
      await expectLater(
        second.restoreBackup(backup, 'wrong'),
        throwsA(anything),
      );
      expect(second.entries.length, before);
      expect(second.selected!.vaultId, identity.vaultId);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

final class _Store implements SecureStringStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
