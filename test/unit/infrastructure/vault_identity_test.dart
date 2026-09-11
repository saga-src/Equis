import 'package:equis/infrastructure/security/vault_identity.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vault = '01990000-0000-7000-8000-000000000001';
  const owner = '01990000-0000-7000-8000-000000000002';
  test('reads existing storage without creating another key', () async {
    final store = _Store();
    final original = VaultIdentity.create(vault);
    final writer = VaultKeyManager(store: store, protocolVersion: 2);
    await writer.installVaultIdentity(original);
    store.values['equis.v2.identity'] = store.values.remove(
      'equis.vault.identity',
    )!;
    final reopened = VaultKeyManager(store: store, protocolVersion: 2);
    expect(
      await (await reopened.requireVault(vault)).fingerprint(),
      await original.fingerprint(),
    );
    await reopened.installVaultIdentity(original);
    expect(
      store.values['equis.vault.identity'],
      store.values['equis.v2.identity'],
    );
  });
  test('missing v2 keys fail without generating secrets', () async {
    final store = _Store();
    final keys = VaultKeyManager(store: store, protocolVersion: 2);
    await expectLater(keys.requireVault(vault), throwsStateError);
    expect(store.values, isEmpty);
  });
  test(
    'same exported key derives same purposes and owner cannot change',
    () async {
      final first = VaultKeyManager(store: _Store(), protocolVersion: 2);
      final original = await first.ensureVault(vault);
      expect(original.exportKey(), startsWith('equis-vault:'));
      final oldExport = original.exportKey().replaceFirst(
        'equis-vault:',
        'equis-vault-v2:',
      );
      expect(
        await VaultIdentity.fromKey(oldExport).fingerprint(),
        await original.fingerprint(),
      );
      final restored = VaultIdentity.fromKey(
        original.exportKey(),
        ownerId: owner,
      );
      final second = VaultKeyManager(store: _Store(), protocolVersion: 2);
      await second.installVaultIdentity(restored);
      expect(await original.fingerprint(), await restored.fingerprint());
      final sync = await (await original.derive('sync')).extractBytes();
      expect(sync, await (await restored.derive('sync')).extractBytes());
      expect(
        sync,
        isNot(await (await restored.derive('attachments')).extractBytes()),
      );
      await expectLater(
        second.installVaultIdentity(original),
        throwsStateError,
      );
      await expectLater(
        second.installVaultIdentity(VaultIdentity.create(vault)),
        throwsStateError,
      );
      expect((await second.requireVault(vault)).ownerId, owner);
      await expectLater(
        second.deriveKey(VaultKeyPurpose.localDatabase),
        throwsStateError,
      );
    },
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
