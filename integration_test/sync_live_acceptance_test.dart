import 'dart:convert';

import 'package:equis/app/providers/local_app_dependencies.dart';
import 'package:equis/application/services/sync_engine.dart';
import 'package:equis/domain/cloud/cloud_identity_models.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/infrastructure/cloud/supabase_sync_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _enabled = bool.fromEnvironment('EQUIS_RUN_LIVE_SYNC_ACCEPTANCE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'persisted trusted device synchronizes only encrypted aggregates',
    (_) async {
      final dependencies = await LocalAppDependencies.bootstrap();
      addTearDown(dependencies.close);
      final finance = await dependencies.session.load();
      final vault = finance.vault;
      expect(vault, isNotNull, reason: 'A local vault must already exist.');

      final account = await dependencies.cloudAccounts.load(
        vaultId: vault!.id,
        now: UtcInstant.now(),
      );
      expect(account.status, CloudAccountStatus.signedIn);
      expect(account.binding?.syncEnabled, isTrue);
      final coordinator = dependencies.syncCoordinator;
      expect(coordinator, isNotNull);

      final result = await coordinator!.start(
        vaultId: vault.id.value,
        deviceId: account.device.id.value,
      );
      expect(result.status, SyncRunStatus.succeeded);

      final client = Supabase.instance.client;
      final rawRows = await client
          .from('sync_records')
          .select()
          .eq('vault_id', vault.id.value)
          .order('server_version', ascending: true);
      expect(rawRows, isNotEmpty);
      const allowedColumns = {
        'vault_id',
        'entity_type',
        'record_id',
        'revision',
        'server_version',
        'cipher_version',
        'nonce',
        'ciphertext',
        'is_deleted',
        'updated_at',
      };
      for (final row in rawRows) {
        expect(row.keys.toSet(), allowedColumns);
      }
      final encodedCloudRows = jsonEncode(rawRows);
      for (final forbidden in {
        'amount_minor',
        'merchant',
        'counterparty_name',
        'account_name',
        'category_name',
        'notes',
        'budget_limit',
        'goal_target',
        'asset_value',
      }) {
        expect(encodedCloudRows, isNot(contains(forbidden)));
      }

      final gateway = SupabaseSyncGateway(client);
      var cursor = 0;
      var decrypted = 0;
      while (true) {
        final records = await gateway.pull(
          vaultId: vault.id.value,
          afterServerVersion: cursor,
        );
        if (records.isEmpty) break;
        for (final cloudRecord in records) {
          expect(cloudRecord.serverVersion, greaterThan(cursor));
          final payload = await dependencies.syncEncryption.decrypt(
            identity: cloudRecord.record.identity,
            envelope: cloudRecord.record.envelope,
          );
          expect(payload['format_version'], 1);
          expect(
            payload['entity_type'],
            cloudRecord.record.identity.entityType,
          );
          expect(payload['root'], isA<Map<Object?, Object?>>());
          expect(payload['children'], isA<Map<Object?, Object?>>());
          cursor = cloudRecord.serverVersion;
          decrypted++;
        }
        if (records.length < 100) break;
      }
      expect(decrypted, rawRows.length);

      final device = await client
          .from('devices')
          .select('last_acknowledged_server_version')
          .eq('id', account.device.id.value)
          .single();
      expect(
        device['last_acknowledged_server_version'],
        greaterThanOrEqualTo(cursor),
      );
      expect(
        await dependencies.syncConflicts.unresolved(vault.id.value),
        isEmpty,
      );
    },
    skip: !_enabled,
  );
}
