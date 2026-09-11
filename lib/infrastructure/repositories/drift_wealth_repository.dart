import 'package:drift/drift.dart';

import '../../application/ports/wealth_repository.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/wealth/asset_models.dart';
import '../../domain/wealth/net_worth_models.dart';
import '../persistence/database/equis_database.dart' hide AssetValuation;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftWealthRepository implements WealthRepository {
  const DriftWealthRepository(this.database, {this.syncRecorder});
  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> saveAsset(PhysicalAsset asset) =>
      syncRecorder?.run(
        vaultId: asset.vaultId.value,
        entityType: SyncEntityType.asset,
        recordId: asset.id.value,
        newRevision: asset.revision,
        operation: asset.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _saveAsset(asset),
      ) ??
      _saveAsset(asset);

  Future<void> _saveAsset(
    PhysicalAsset asset,
  ) => database.transaction(() async {
    final current = await database
        .customSelect(
          'SELECT revision FROM assets WHERE id = ?',
          variables: [Variable<String>(asset.id.value)],
          readsFrom: {database.assets},
        )
        .getSingleOrNull();
    if (current == null) {
      if (asset.revision != 1) {
        throw AssetRevisionConflict(
          id: asset.id,
          expected: asset.revision - 1,
          actual: null,
        );
      }
      await database.customStatement(
        'INSERT INTO assets (id, vault_id, name, asset_type, currency_code, '
        'acquired_on, acquisition_cost_minor, valuation_method, annual_rate, '
        'useful_life_months, salvage_value_minor, include_in_net_worth, notes, '
        'revision, created_at, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        _values(asset),
      );
      return;
    }
    final actual = current.read<int>('revision');
    final expected = asset.revision - 1;
    if (actual != expected) {
      throw AssetRevisionConflict(
        id: asset.id,
        expected: expected,
        actual: actual,
      );
    }
    final changed = await database.customUpdate(
      'UPDATE assets SET name = ?, asset_type = ?, currency_code = ?, acquired_on = ?, '
      'acquisition_cost_minor = ?, valuation_method = ?, annual_rate = ?, '
      'useful_life_months = ?, salvage_value_minor = ?, include_in_net_worth = ?, '
      'notes = ?, revision = ?, updated_at = ?, deleted_at = ? '
      'WHERE id = ? AND revision = ?',
      variables: _variables([
        asset.name,
        asset.type.stored,
        asset.currency.value,
        asset.acquiredOn?.toString(),
        asset.acquisitionCostMinor,
        asset.valuationMethod.stored,
        asset.annualRate == null
            ? null
            : DecimalValue.canonical(asset.annualRate!),
        asset.usefulLifeMonths,
        asset.salvageValueMinor,
        asset.includeInNetWorth ? 1 : 0,
        asset.notes,
        asset.revision,
        asset.updatedAt.epochMicroseconds,
        asset.deletedAt?.epochMicroseconds,
        asset.id.value,
        expected,
      ]),
      updates: {database.assets},
    );
    if (changed != 1) {
      throw AssetRevisionConflict(
        id: asset.id,
        expected: expected,
        actual: actual,
      );
    }
  });

  List<Object?> _values(PhysicalAsset asset) => [
    asset.id.value,
    asset.vaultId.value,
    asset.name,
    asset.type.stored,
    asset.currency.value,
    asset.acquiredOn?.toString(),
    asset.acquisitionCostMinor,
    asset.valuationMethod.stored,
    asset.annualRate == null ? null : DecimalValue.canonical(asset.annualRate!),
    asset.usefulLifeMonths,
    asset.salvageValueMinor,
    asset.includeInNetWorth ? 1 : 0,
    asset.notes,
    asset.revision,
    asset.createdAt.epochMicroseconds,
    asset.updatedAt.epochMicroseconds,
    asset.deletedAt?.epochMicroseconds,
  ];

  @override
  Future<PhysicalAsset?> findAsset(EntityId id) async {
    final row = await database
        .customSelect(
          'SELECT * FROM assets WHERE id = ? AND deleted_at IS NULL',
          variables: [Variable<String>(id.value)],
          readsFrom: {database.assets},
        )
        .getSingleOrNull();
    return row == null ? null : _asset(row.data);
  }

  @override
  Future<List<PhysicalAsset>> listAssets(EntityId vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM assets WHERE vault_id = ? ORDER BY name, id',
          variables: [Variable<String>(vaultId.value)],
          readsFrom: {database.assets},
        )
        .get();
    return [for (final row in rows) _asset(row.data)];
  }

  PhysicalAsset _asset(Map<String, Object?> row) => PhysicalAsset(
    id: EntityId.parse(row['id']! as String),
    vaultId: EntityId.parse(row['vault_id']! as String),
    name: row['name']! as String,
    type: PhysicalAssetType.fromStorage(row['asset_type']! as String),
    currency: CurrencyCode(row['currency_code']! as String),
    acquiredOn: row['acquired_on'] == null
        ? null
        : LocalDate.parse(row['acquired_on']! as String),
    acquisitionCostMinor: row['acquisition_cost_minor'] as int?,
    valuationMethod: AssetValuationMethod.fromStorage(
      row['valuation_method']! as String,
    ),
    annualRate: row['annual_rate'] == null
        ? null
        : DecimalValue.parse(row['annual_rate']! as String),
    usefulLifeMonths: row['useful_life_months'] as int?,
    salvageValueMinor: row['salvage_value_minor'] as int?,
    includeInNetWorth: row['include_in_net_worth']! as int != 0,
    notes: row['notes'] as String?,
    revision: row['revision']! as int,
    createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
    updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
    deletedAt: row['deleted_at'] == null
        ? null
        : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
  );

  @override
  Future<void> addValuation(AssetValuation valuation) async {
    final asset = await database
        .customSelect(
          'SELECT vault_id, revision FROM assets WHERE id = ?',
          variables: [Variable(valuation.assetId.value)],
        )
        .getSingle();
    final revision = asset.read<int>('revision') + 1;
    Future<void> action() => database.transaction(() async {
      await database.customStatement(
        'INSERT INTO asset_valuations (id, asset_id, valuation_date, value_minor, source, notes) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          valuation.id.value,
          valuation.assetId.value,
          valuation.date.toString(),
          valuation.valueMinor,
          valuation.source.name,
          valuation.notes,
        ],
      );
      final changed = await database.customUpdate(
        'UPDATE assets SET revision = ?, updated_at = ? WHERE id = ? AND revision = ?',
        variables: [
          Variable(revision),
          Variable(DateTime.now().toUtc().microsecondsSinceEpoch),
          Variable(valuation.assetId.value),
          Variable(revision - 1),
        ],
      );
      if (changed != 1) {
        throw AssetRevisionConflict(
          id: valuation.assetId,
          expected: revision - 1,
          actual: null,
        );
      }
    });
    await (syncRecorder?.run(
          vaultId: asset.read<String>('vault_id'),
          entityType: SyncEntityType.asset,
          recordId: valuation.assetId.value,
          newRevision: revision,
          operation: SyncOperation.upsert,
          action: action,
        ) ??
        action());
  }

  @override
  Future<List<AssetValuation>> valuations(
    EntityId assetId, {
    LocalDate? through,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM asset_valuations WHERE asset_id = ? '
          '${through == null ? '' : 'AND valuation_date <= ? '}'
          "ORDER BY valuation_date, CASE source WHEN 'calculated' THEN 0 WHEN 'external' THEN 1 ELSE 2 END, id",
          variables: [
            Variable<String>(assetId.value),
            if (through != null) Variable<String>(through.toString()),
          ],
          readsFrom: {database.assetValuations},
        )
        .get();
    return [
      for (final row in rows)
        AssetValuation(
          id: EntityId.parse(row.read<String>('id')),
          assetId: assetId,
          date: LocalDate.parse(row.read<String>('valuation_date')),
          valueMinor: row.read<int>('value_minor'),
          source: AssetValuationSource.values.byName(
            row.read<String>('source'),
          ),
          notes: row.readNullable<String>('notes'),
        ),
    ];
  }

  @override
  Future<List<NetWorthAccountBalance>> accountBalances(
    EntityId vaultId,
    LocalDate asOf,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT account.id AS account_id, account.name AS account_name, account.nature, '
          'pocket.currency_code, COALESCE(SUM(CASE WHEN parent.id IS NOT NULL '
          "AND parent.status != 'cancelled' AND parent.deleted_at IS NULL "
          'AND parent.financial_date <= ? '
          "AND NOT (parent.status = 'pending' AND parent.recurring_rule_id IS NOT NULL) "
          'THEN movement.amount_minor ELSE 0 END), 0) AS balance_minor '
          'FROM accounts AS account INNER JOIN account_pockets AS pocket ON pocket.account_id = account.id '
          'LEFT JOIN account_movements AS movement ON movement.account_pocket_id = pocket.id '
          'LEFT JOIN transactions AS parent ON parent.id = movement.transaction_id '
          'WHERE account.vault_id = ? AND account.deleted_at IS NULL AND account.archived = 0 '
          'AND account.include_in_net_worth = 1 '
          'AND (account.opened_on IS NULL OR account.opened_on <= ?) '
          'AND (account.closed_on IS NULL OR account.closed_on > ?) '
          'GROUP BY account.id, account.name, account.nature, pocket.currency_code '
          'ORDER BY account.name, pocket.currency_code',
          variables: [
            Variable<String>(asOf.toString()),
            Variable<String>(vaultId.value),
            Variable<String>(asOf.toString()),
            Variable<String>(asOf.toString()),
          ],
          readsFrom: {
            database.accounts,
            database.accountPockets,
            database.accountMovements,
            database.transactions,
          },
        )
        .get();
    return [
      for (final row in rows)
        NetWorthAccountBalance(
          accountId: EntityId.parse(row.read<String>('account_id')),
          accountName: row.read<String>('account_name'),
          nature: AccountNature.values.byName(row.read<String>('nature')),
          currency: CurrencyCode(row.read<String>('currency_code')),
          balanceMinor: row.read<int>('balance_minor'),
        ),
    ];
  }
}

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map(Variable<Object>.new).toList(growable: false);
