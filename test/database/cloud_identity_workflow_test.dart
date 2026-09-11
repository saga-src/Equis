import 'dart:async';

import 'package:drift/native.dart';
import 'package:equis/application/ports/cloud_identity_ports.dart';
import 'package:equis/application/services/cloud_account_service.dart';
import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide VaultCloudBinding;
import 'package:equis/infrastructure/repositories/drift_cloud_identity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late EntityId vaultId;
  late _FakeAuth auth;
  late CloudAccountService service;
  const first = UtcInstant.fromEpochMicroseconds(1000);
  const later = UtcInstant.fromEpochMicroseconds(2000);

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    vaultId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) '
      "VALUES (?,?,'BRL','UTC',1,1)",
      [vaultId.value, 'Local'],
    );
    auth = _FakeAuth();
    service = CloudAccountService(
      repository: DriftCloudIdentityRepository(database),
      auth: auth,
      deviceName: 'Test Windows',
      platform: 'windows',
    );
  });

  tearDown(() async {
    await auth.close();
    await database.close();
  });

  test('device UUID remains stable across offline restarts', () async {
    final initial = await service.load(vaultId: vaultId, now: first);
    final restarted = await CloudAccountService(
      repository: DriftCloudIdentityRepository(database),
      deviceName: 'Changed label',
      platform: 'windows',
    ).load(vaultId: vaultId, now: later);

    expect(restarted.status, CloudAccountStatus.localOnly);
    expect(restarted.device.id, initial.device.id);
    expect(restarted.device.name, 'Test Windows');
    expect(restarted.device.lastSeenAt, later);
  });

  test(
    'verification then sign-in binds the existing local UUID only',
    () async {
      auth.signUpIdentity = const CloudAuthIdentity(
        authUserId: '11111111-1111-4111-8111-111111111111',
        email: 'person@example.com',
        emailVerified: false,
        hasActiveSession: false,
      );
      final pending = await service.createAccount(
        vaultId: vaultId,
        email: 'person@example.com',
        password: 'long-test-password',
        now: first,
      );
      expect(pending.status, CloudAccountStatus.awaitingEmailVerification);
      expect(pending.binding, isNull);

      auth.signInIdentity = const CloudAuthIdentity(
        authUserId: '11111111-1111-4111-8111-111111111111',
        email: 'person@example.com',
        emailVerified: true,
        hasActiveSession: true,
      );
      final signedIn = await service.signIn(
        vaultId: vaultId,
        email: 'person@example.com',
        password: 'long-test-password',
        now: later,
      );

      expect(signedIn.status, CloudAccountStatus.signedIn);
      expect(signedIn.binding?.vaultId, vaultId);
      expect(signedIn.binding?.syncEnabled, isFalse);
      final storedVault = await database
          .customSelect('SELECT id FROM vaults')
          .getSingle();
      expect(storedVault.read<String>('id'), vaultId.value);
    },
  );

  test('sign-out and auth outage preserve safe local access', () async {
    auth.signInIdentity = const CloudAuthIdentity(
      authUserId: '22222222-2222-4222-8222-222222222222',
      email: 'person@example.com',
      emailVerified: true,
      hasActiveSession: true,
    );
    await service.signIn(
      vaultId: vaultId,
      email: 'person@example.com',
      password: 'long-test-password',
      now: first,
    );
    final signedOut = await service.signOut(vaultId: vaultId, now: later);
    expect(signedOut.status, CloudAccountStatus.sessionExpired);
    expect(signedOut.localAccessAvailable, isTrue);

    auth.failure = const CloudAuthFailure(CloudAuthFailureCode.network);
    await expectLater(
      service.signIn(
        vaultId: vaultId,
        email: 'person@example.com',
        password: 'long-test-password',
        now: later,
      ),
      throwsA(
        isA<CloudAuthFailure>().having(
          (value) => value.code,
          'code',
          CloudAuthFailureCode.network,
        ),
      ),
    );
    expect(
      (await database.customSelect('SELECT COUNT(*) n FROM vaults').getSingle())
          .read<int>('n'),
      1,
    );
  });

  test('a vault cannot silently switch to another auth user', () async {
    auth.signInIdentity = const CloudAuthIdentity(
      authUserId: '33333333-3333-4333-8333-333333333333',
      email: 'first@example.com',
      emailVerified: true,
      hasActiveSession: true,
    );
    await service.signIn(
      vaultId: vaultId,
      email: 'first@example.com',
      password: 'long-test-password',
      now: first,
    );
    auth.signInIdentity = const CloudAuthIdentity(
      authUserId: '44444444-4444-4444-8444-444444444444',
      email: 'other@example.com',
      emailVerified: true,
      hasActiveSession: true,
    );
    await expectLater(
      service.signIn(
        vaultId: vaultId,
        email: 'other@example.com',
        password: 'long-test-password',
        now: later,
      ),
      throwsA(
        isA<CloudAuthFailure>().having(
          (value) => value.code,
          'code',
          CloudAuthFailureCode.vaultUserMismatch,
        ),
      ),
    );
  });
}

final class _FakeAuth implements CloudAuthGateway {
  final _changes = StreamController<CloudAuthIdentity?>.broadcast();
  CloudAuthIdentity? signUpIdentity;
  CloudAuthIdentity? signInIdentity;
  CloudAuthIdentity? _current;
  CloudAuthFailure? failure;

  @override
  String? get currentAccessToken =>
      _current?.hasActiveSession == true ? 'test-access-token' : null;
  @override
  CloudAuthIdentity? get currentIdentity => _current;
  @override
  Stream<CloudAuthIdentity?> get identityChanges => _changes.stream;

  @override
  Future<CloudAuthIdentity> signUp({
    required String email,
    required String password,
  }) async {
    if (failure case final value?) throw value;
    _current = signUpIdentity!;
    _changes.add(_current);
    return _current!;
  }

  @override
  Future<CloudAuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    if (failure case final value?) throw value;
    _current = signInIdentity!;
    _changes.add(_current);
    return _current!;
  }

  @override
  Future<void> resendVerification(String email) async {
    if (failure case final value?) throw value;
  }

  @override
  Future<void> signOut() async {
    if (failure case final value?) throw value;
    _current = null;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}
