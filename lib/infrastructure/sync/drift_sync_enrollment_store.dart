import 'package:drift/drift.dart';

import '../../application/ports/sync_enrollment_store.dart';
import '../../application/sync/sync_models.dart';
import '../persistence/database/equis_database.dart';
import 'drift_sync_metadata_store.dart';

final class DriftSyncEnrollmentStore implements SyncEnrollmentStore {
  const DriftSyncEnrollmentStore({
    required this.database,
    required this.metadata,
    this.allowVerifiedOwnerBinding = false,
  });

  final EquisDatabase database;
  final DriftSyncMetadataStore metadata;
  final bool allowVerifiedOwnerBinding;

  @override
  Future<void> seedAndEnable({
    required String vaultId,
    required String authUserId,
  }) => database.transaction(() async {
    final binding = await database
        .customSelect(
          'SELECT auth_user_id, sync_enabled FROM vault_cloud_bindings WHERE vault_id = ?',
          variables: [Variable(vaultId)],
        )
        .getSingleOrNull();
    if ((binding == null && !allowVerifiedOwnerBinding) ||
        (binding != null &&
            binding.read<String>('auth_user_id') != authUserId)) {
      throw StateError(
        'The authenticated user does not own this local binding.',
      );
    }
    if (binding == null) {
      // Called only after the gateway has verified and bound the cloud owner.
      await database.customStatement(
        'INSERT INTO vault_cloud_bindings(vault_id,auth_user_id,sync_enabled,linked_at) VALUES (?,?,0,?)',
        [vaultId, authUserId, DateTime.now().toUtc().microsecondsSinceEpoch],
      );
    } else if (binding.read<int>('sync_enabled') == 1) {
      return;
    }
    for (final entry in _roots.entries) {
      final rows = await database
          .customSelect(
            'SELECT id, revision, deleted_at FROM ${entry.value} '
            'WHERE ${entry.key == SyncEntityType.vault ? 'id' : 'vault_id'} = ?',
            variables: [Variable(vaultId)],
          )
          .get();
      for (final row in rows) {
        await metadata.enqueue(
          vaultId: vaultId,
          entityType: entry.key,
          recordId: row.read<String>('id'),
          baseRevision: null,
          baseSnapshot: null,
          newRevision: row.read<int>('revision'),
          operation: row.readNullable<int>('deleted_at') == null
              ? SyncOperation.upsert
              : SyncOperation.delete,
        );
      }
    }
    await database.customStatement(
      'UPDATE vault_cloud_bindings SET sync_enabled = 1 '
      'WHERE vault_id = ? AND auth_user_id = ?',
      [vaultId, authUserId],
    );
  });
}

const _roots = <SyncEntityType, String>{
  SyncEntityType.vault: 'vaults',
  SyncEntityType.account: 'accounts',
  SyncEntityType.category: 'categories',
  SyncEntityType.counterparty: 'counterparties',
  SyncEntityType.tag: 'tags',
  SyncEntityType.transaction: 'transactions',
  SyncEntityType.recurringRule: 'recurring_rules',
  SyncEntityType.installmentPlan: 'installment_plans',
  SyncEntityType.creditCardStatement: 'credit_card_statements',
  SyncEntityType.budget: 'budgets',
  SyncEntityType.goal: 'goals',
  SyncEntityType.asset: 'assets',
  SyncEntityType.investmentInstrument: 'investment_instruments',
  SyncEntityType.manualFxRate: 'manual_fx_rates',
  SyncEntityType.manualMarketPrice: 'manual_market_prices',
  SyncEntityType.attachment: 'attachments',
};
