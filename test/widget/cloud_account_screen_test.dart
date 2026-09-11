import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:equis/application/ports/sync_conflict_resolver.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/cloud/cloud_account_controller.dart';
import 'package:equis/presentation/cloud/cloud_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fresh device offers encrypted account restoration', (
    tester,
  ) async {
    await _pump(
      tester,
      const LocalFinanceSnapshot(vault: null),
      const CloudAccountState(),
    );

    expect(
      find.byKey(const Key('restore-existing-vault-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('restore-email')), findsOneWidget);
    expect(find.byKey(const Key('restore-password')), findsOneWidget);
    expect(find.byKey(const Key('restore-recovery-secret')), findsOneWidget);
    expect(find.byKey(const Key('restore-existing-vault')), findsOneWidget);
  });

  testWidgets(
    'local-only state explains that every local feature remains usable',
    (tester) async {
      final fixture = _fixture();
      await _pump(
        tester,
        fixture.finance,
        CloudAccountState(
          snapshot: CloudAccountSnapshot(
            status: CloudAccountStatus.localOnly,
            device: fixture.device,
          ),
        ),
      );

      expect(find.byKey(const Key('cloud-local-first-notice')), findsOneWidget);
      expect(find.byKey(const Key('cloud-status-localOnly')), findsOneWidget);
      expect(
        find.textContaining('every local feature offline'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('cloud-email')), findsNothing);
    },
  );

  testWidgets(
    'signed-out and signed-in states preserve device and vault context',
    (tester) async {
      final fixture = _fixture();
      await _pump(
        tester,
        fixture.finance,
        CloudAccountState(
          snapshot: CloudAccountSnapshot(
            status: CloudAccountStatus.signedOut,
            device: fixture.device,
          ),
          errorCode: CloudAuthFailureCode.network,
        ),
      );
      expect(find.byKey(const Key('cloud-email')), findsOneWidget);
      expect(find.byKey(const Key('cloud-password')), findsOneWidget);
      expect(find.byKey(const Key('cloud-auth-error')), findsOneWidget);
      expect(find.textContaining('Local access is unaffected'), findsOneWidget);

      final binding = VaultCloudBinding(
        vaultId: fixture.finance.vault!.id,
        authUserId: '11111111-1111-4111-8111-111111111111',
        syncEnabled: false,
        linkedAt: const UtcInstant.fromEpochMicroseconds(2),
      );
      await _pump(
        tester,
        fixture.finance,
        CloudAccountState(
          snapshot: CloudAccountSnapshot(
            status: CloudAccountStatus.signedIn,
            device: fixture.device,
            binding: binding,
            identity: const CloudAuthIdentity(
              authUserId: '11111111-1111-4111-8111-111111111111',
              email: 'person@example.com',
              emailVerified: true,
              hasActiveSession: true,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('cloud-status-signedIn')), findsOneWidget);
      expect(find.textContaining('person@example.com'), findsOneWidget);
      expect(
        find.textContaining('Secure synchronization is off'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('enable-secure-sync')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('cloud-sign-out')),
        200,
      );
      expect(find.byKey(const Key('cloud-sign-out')), findsOneWidget);
    },
  );

  testWidgets('recovery and conflict states require explicit user choices', (
    tester,
  ) async {
    final fixture = _fixture();
    final identity = const CloudAuthIdentity(
      authUserId: '11111111-1111-4111-8111-111111111111',
      email: 'person@example.com',
      emailVerified: true,
      hasActiveSession: true,
    );
    final disabled = VaultCloudBinding(
      vaultId: fixture.finance.vault!.id,
      authUserId: identity.authUserId,
      syncEnabled: false,
      linkedAt: const UtcInstant.fromEpochMicroseconds(2),
    );
    await _pump(
      tester,
      fixture.finance,
      CloudAccountState(
        snapshot: CloudAccountSnapshot(
          status: CloudAccountStatus.signedIn,
          device: fixture.device,
          binding: disabled,
          identity: identity,
        ),
        recoverySecret: 'equis-recovery-v1_example',
      ),
    );
    expect(find.byKey(const Key('sync-recovery-secret')), findsOneWidget);
    expect(find.byKey(const Key('confirm-recovery-saved')), findsOneWidget);

    final enabled = VaultCloudBinding(
      vaultId: fixture.finance.vault!.id,
      authUserId: identity.authUserId,
      syncEnabled: true,
      linkedAt: const UtcInstant.fromEpochMicroseconds(2),
    );
    await _pump(
      tester,
      fixture.finance,
      CloudAccountState(
        snapshot: CloudAccountSnapshot(
          status: CloudAccountStatus.signedIn,
          device: fixture.device,
          binding: enabled,
          identity: identity,
        ),
        syncRunStatus: SyncRunStatus.succeeded,
        conflicts: const [
          SyncConflictSummary(
            id: 'conflict',
            vaultId: 'vault',
            entityType: SyncEntityType.transaction,
            recordId: '018f47c2-9b72-7cc1-8b83-5d0fead0a002',
            baseRevision: 1,
            localRevision: 2,
            remoteRevision: 2,
            detectedAtMicros: 3,
          ),
        ],
      ),
    );
    expect(find.byKey(const Key('manual-sync-retry')), findsOneWidget);
    expect(find.text('Conflicts requiring review'), findsOneWidget);
    expect(find.textContaining('local revision 2'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  LocalFinanceSnapshot finance,
  CloudAccountState state,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CloudAccountScreen(
          financeOverride: finance,
          stateOverride: state,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

({LocalFinanceSnapshot finance, LocalDeviceIdentity device}) _fixture() {
  final vaultId = EntityId.generate();
  const instant = UtcInstant.fromEpochMicroseconds(1);
  return (
    finance: LocalFinanceSnapshot(
      vault: VaultProfile(
        id: vaultId,
        name: 'Local',
        baseCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        createdAt: instant,
        updatedAt: instant,
      ),
    ),
    device: LocalDeviceIdentity(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Test Windows',
      platform: 'windows',
      createdAt: instant,
      lastSeenAt: instant,
    ),
  );
}
