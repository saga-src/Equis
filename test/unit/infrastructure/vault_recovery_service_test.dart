import 'dart:convert';
import 'dart:math';

import 'package:equis/infrastructure/security/secure_string_store.dart';
import 'package:equis/infrastructure/security/vault_key_manager.dart';
import 'package:equis/infrastructure/security/vault_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vaultId = '018f47c2-9b72-7cc1-8b83-5d0fead0a001';
  const parameters = RecoveryKdfParameters(
    memoryKiB: 32,
    iterations: 2,
    parallelism: 1,
  );
  final nonce = List<int>.generate(24, (index) => 100 + index);

  test('Argon2id wraps and recovers the VMK with a known envelope', () async {
    final master = List<int>.generate(32, (index) => index);
    final service = _service(
      master: master,
      parameters: parameters,
      nonce: nonce,
    );

    final package = await service.create(vaultId: vaultId);
    final recovered = await service.recover(
      record: package.record,
      recoverySecret: package.secret.export(),
    );

    expect(await recovered.extractBytes(), master);
    expect(package.secret.toString(), isNot(contains(package.secret.export())));
    expect(package.record.wrappedVaultKey, isNot(master));
    expect(
      _hex(package.record.wrappedVaultKey),
      'bd0cbd96c5580da740228bcf3dd20a98503dc49cea38b0fcb976d3fc586d2873'
      '224346ac61abb5d6614e481dfe128fda',
    );
    expect(package.record.toCloudColumns().keys, {
      'vault_id',
      'wrapped_vault_key',
      'kdf',
      'kdf_parameters',
      'salt',
      'nonce',
      'key_version',
    });
    expect(
      package.record.toCloudColumns().values,
      isNot(contains(package.secret.export())),
    );
  });

  test(
    'wrong recovery secret and tampered wrapping fail authentication',
    () async {
      final service = _service(
        master: List<int>.filled(32, 9),
        parameters: parameters,
        nonce: nonce,
      );
      final package = await service.create(vaultId: vaultId);
      final otherSecret = RecoverySecret.fromRandomBytes(
        List<int>.filled(32, 3),
      ).export();

      await expectLater(
        service.recover(record: package.record, recoverySecret: otherSecret),
        throwsA(isA<RecoveryAuthenticationException>()),
      );

      final tamperedBytes = List<int>.from(package.record.wrappedVaultKey);
      tamperedBytes[0] ^= 1;
      final tampered = VaultRecoveryRecord(
        vaultId: package.record.vaultId,
        wrappedVaultKey: tamperedBytes,
        parameters: package.record.parameters,
        salt: package.record.salt,
        nonce: package.record.nonce,
        keyVersion: package.record.keyVersion,
      );
      await expectLater(
        service.recover(
          record: tampered,
          recoverySecret: package.secret.export(),
        ),
        throwsA(isA<RecoveryAuthenticationException>()),
      );
    },
  );

  test('recovered VMK can seed an empty trusted device store', () async {
    final master = List<int>.generate(32, (index) => 255 - index);
    final source = _service(
      master: master,
      parameters: parameters,
      nonce: nonce,
    );
    final package = await source.create(vaultId: vaultId);
    final destinationStore = _MemorySecureStore({});
    final destinationKeys = VaultKeyManager(store: destinationStore);
    final destination = VaultRecoveryService(
      keys: destinationKeys,
      parameters: parameters,
    );

    await destination.restoreToSecureStorage(
      record: package.record,
      recoverySecret: package.secret.export(),
    );

    expect(
      await (await destinationKeys.loadMasterKey(1)).extractBytes(),
      master,
    );
    expect(await destinationKeys.currentVersion(), 1);
  });
}

VaultRecoveryService _service({
  required List<int> master,
  required RecoveryKdfParameters parameters,
  required List<int> nonce,
}) => VaultRecoveryService(
  keys: VaultKeyManager(
    store: _MemorySecureStore({
      'equis.vault_master_key.v1': base64UrlEncode(master),
    }),
  ),
  parameters: parameters,
  random: _FixedRandom(17),
  nonceGenerator: () => nonce,
);

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _MemorySecureStore implements SecureStringStore {
  _MemorySecureStore(this.values);
  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _FixedRandom implements Random {
  const _FixedRandom(this.value);
  final int value;

  @override
  bool nextBool() => value.isOdd;

  @override
  double nextDouble() => value / 256;

  @override
  int nextInt(int max) => value % max;
}
