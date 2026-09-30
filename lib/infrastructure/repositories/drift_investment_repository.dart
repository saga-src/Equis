import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../application/ports/investment_repository.dart';
import '../../application/ports/ledger_repository.dart';
import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/investments/fixed_income_contract.dart';
import '../../domain/investments/investment_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart'
    hide
        InvestmentInstrument,
        InvestmentLot,
        FixedIncomeContract,
        FixedIncomeManualValue;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftInvestmentRepository implements InvestmentRepository {
  const DriftInvestmentRepository({
    required this.database,
    required this.ledger,
    this.syncRecorder,
  });
  final EquisDatabase database;
  final LedgerRepository ledger;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> saveInstrument(InvestmentInstrument value) =>
      syncRecorder?.run(
        vaultId: value.vaultId.value,
        entityType: SyncEntityType.investmentInstrument,
        recordId: value.id.value,
        newRevision: value.revision,
        operation: value.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _saveInstrument(value),
      ) ??
      _saveInstrument(value);

  Future<void> _saveInstrument(
    InvestmentInstrument value,
  ) => database.transaction(() async {
    final row = await database
        .customSelect(
          'SELECT revision FROM investment_instruments WHERE id = ?',
          variables: [Variable<String>(value.id.value)],
          readsFrom: {database.investmentInstruments},
        )
        .getSingleOrNull();
    if (row == null) {
      if (value.revision != 1) {
        throw InstrumentRevisionConflict(
          id: value.id,
          expected: value.revision - 1,
          actual: null,
        );
      }
      await database.customStatement(
        'INSERT INTO investment_instruments '
        '(id,vault_id,symbol,name,asset_class,exchange,currency_code,isin,provider_symbol,'
        'provider_name,custom_instrument,revision,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        _instrumentValues(value),
      );
      return;
    }
    final actual = row.read<int>('revision'), expected = value.revision - 1;
    if (actual != expected) {
      throw InstrumentRevisionConflict(
        id: value.id,
        expected: expected,
        actual: actual,
      );
    }
    final changed = await database.customUpdate(
      'UPDATE investment_instruments SET symbol=?,name=?,'
      'asset_class=?,exchange=?,currency_code=?,isin=?,provider_symbol=?,provider_name=?,'
      'custom_instrument=?,revision=?,updated_at=?,deleted_at=? WHERE id=? AND revision=?',
      variables: _variables([
        value.symbol,
        value.name,
        value.assetClass.stored,
        value.exchange,
        value.currency.value,
        value.isin,
        value.providerSymbol,
        value.providerName,
        value.customInstrument ? 1 : 0,
        value.revision,
        value.updatedAt.epochMicroseconds,
        value.deletedAt?.epochMicroseconds,
        value.id.value,
        expected,
      ]),
      updates: {database.investmentInstruments},
    );
    if (changed != 1) {
      throw InstrumentRevisionConflict(
        id: value.id,
        expected: expected,
        actual: actual,
      );
    }
  });

  @override
  Future<bool> hasProtectedHistory(EntityId instrumentId) async {
    final row = await database
        .customSelect(
          'SELECT 1 AS present FROM investment_events WHERE instrument_id=? '
          'UNION ALL SELECT 1 FROM investment_lots WHERE instrument_id=? '
          'UNION ALL SELECT 1 FROM investment_lot_disposals disposal '
          'INNER JOIN investment_lots lot ON lot.id=disposal.lot_id '
          'WHERE lot.instrument_id=? '
          "UNION ALL SELECT 1 FROM attachment_links WHERE entity_type='investment_instrument' AND entity_id=? "
          'LIMIT 1',
          variables: List.filled(
            4,
            Variable<String>(instrumentId.value),
            growable: false,
          ),
          readsFrom: {
            database.investmentEvents,
            database.investmentLots,
            database.investmentLotDisposals,
            database.attachmentLinks,
          },
        )
        .getSingleOrNull();
    return row != null;
  }

  List<Object?> _instrumentValues(InvestmentInstrument v) => [
    v.id.value,
    v.vaultId.value,
    v.symbol,
    v.name,
    v.assetClass.stored,
    v.exchange,
    v.currency.value,
    v.isin,
    v.providerSymbol,
    v.providerName,
    v.customInstrument ? 1 : 0,
    v.revision,
    v.createdAt.epochMicroseconds,
    v.updatedAt.epochMicroseconds,
    v.deletedAt?.epochMicroseconds,
  ];

  @override
  Future<InvestmentInstrument?> findInstrument(EntityId id) async {
    final row = await database
        .customSelect(
          'SELECT * FROM investment_instruments WHERE id=? AND deleted_at IS NULL',
          variables: [Variable<String>(id.value)],
          readsFrom: {database.investmentInstruments},
        )
        .getSingleOrNull();
    return row == null ? null : _instrument(row.data);
  }

  @override
  Future<List<InvestmentInstrument>> listInstruments(EntityId vaultId) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM investment_instruments WHERE vault_id=? '
          'AND deleted_at IS NULL ORDER BY name,id',
          variables: [Variable<String>(vaultId.value)],
          readsFrom: {database.investmentInstruments},
        )
        .get();
    return [for (final row in rows) _instrument(row.data)];
  }

  InvestmentInstrument _instrument(Map<String, Object?> row) =>
      InvestmentInstrument(
        id: EntityId.parse(row['id']! as String),
        vaultId: EntityId.parse(row['vault_id']! as String),
        symbol: row['symbol'] as String?,
        name: row['name']! as String,
        assetClass: InvestmentAssetClass.fromStorage(
          row['asset_class']! as String,
        ),
        exchange: row['exchange'] as String?,
        currency: CurrencyCode(row['currency_code']! as String),
        isin: row['isin'] as String?,
        providerSymbol: row['provider_symbol'] as String?,
        providerName: row['provider_name'] as String?,
        customInstrument: (row['custom_instrument']! as int) != 0,
        revision: row['revision']! as int,
        createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
        updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
        deletedAt: row['deleted_at'] == null
            ? null
            : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
      );

  @override
  Future<int> currencyMinorUnits(CurrencyCode currency) async =>
      (await database
              .customSelect(
                'SELECT minor_units FROM currencies WHERE code=?',
                variables: [Variable<String>(currency.value)],
                readsFrom: {database.currencies},
              )
              .getSingle())
          .read<int>('minor_units');

  @override
  Future<void> saveBuy(
    LedgerTransaction transaction,
    InvestmentLot lot, {
    FixedIncomeContract? contract,
  }) => database.transaction(() async {
    if (contract != null &&
        (contract.lotId != lot.id ||
            contract.terms.currency != lot.costCurrency)) {
      throw ArgumentError('Contract does not match the acquisition lot.');
    }
    await ledger.save(transaction);
    await database.customStatement(
      'INSERT INTO investment_lots (id,acquisition_event_id,instrument_id,'
      'acquired_on,original_quantity,cost_basis_minor,cost_currency_code) VALUES (?,?,?,?,?,?,?)',
      [
        lot.id.value,
        lot.acquisitionEventId.value,
        lot.instrumentId.value,
        lot.acquiredOn.toString(),
        DecimalValue.canonical(lot.originalQuantity),
        lot.costBasisMinor,
        lot.costCurrency.value,
      ],
    );
    if (contract != null) {
      if (await _acquisitionRoot(transaction.vaultId, lot.id) == null) {
        throw StateError('Contract requires a fixed-income acquisition lot.');
      }
      await _upsertContract(contract);
    }
  });

  @override
  Future<FixedIncomeContract?> findContract(
    EntityId vaultId,
    EntityId lotId,
  ) async {
    final row = await database
        .customSelect(
          'SELECT contract.* FROM fixed_income_contracts contract '
          'INNER JOIN investment_lots lot ON lot.id=contract.lot_id '
          'INNER JOIN investment_events event ON event.id=lot.acquisition_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'WHERE contract.lot_id=? AND parent.vault_id=? AND parent.deleted_at IS NULL',
          variables: [Variable(lotId.value), Variable(vaultId.value)],
          readsFrom: {
            database.fixedIncomeContracts,
            database.investmentLots,
            database.investmentEvents,
            database.transactions,
          },
        )
        .getSingleOrNull();
    return row == null ? null : _contractFromRow(row.data);
  }

  @override
  Future<InvestmentLotEditorSnapshot?> loadLotEditor({
    required EntityId vaultId,
    required EntityId lotId,
    required LocalDate asOf,
  }) => database.transaction(() async {
    final acquisition = await database
        .customSelect(
          'SELECT lot.original_quantity, '
          'parent.revision AS acquisition_revision '
          'FROM investment_lots lot '
          'INNER JOIN investment_events event ON event.id=lot.acquisition_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'INNER JOIN investment_instruments instrument ON instrument.id=lot.instrument_id '
          'WHERE lot.id=? AND parent.vault_id=? AND instrument.vault_id=? '
          "AND instrument.asset_class='fixed_income' AND instrument.deleted_at IS NULL "
          "AND parent.deleted_at IS NULL AND parent.status!='cancelled' "
          'AND parent.financial_date<=?',
          variables: [
            Variable(lotId.value),
            Variable(vaultId.value),
            Variable(vaultId.value),
            Variable(asOf.toString()),
          ],
          readsFrom: {
            database.investmentLots,
            database.investmentEvents,
            database.transactions,
            database.investmentInstruments,
          },
        )
        .getSingleOrNull();
    if (acquisition == null) return null;

    final disposals = await database
        .customSelect(
          'SELECT disposal.quantity FROM investment_lot_disposals disposal '
          'INNER JOIN investment_events event ON event.id=disposal.disposal_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'WHERE disposal.lot_id=? AND parent.financial_date<=? '
          "AND parent.deleted_at IS NULL AND parent.status!='cancelled'",
          variables: [Variable(lotId.value), Variable(asOf.toString())],
          readsFrom: {
            database.investmentLotDisposals,
            database.investmentEvents,
            database.transactions,
          },
        )
        .get();
    var disposed = Decimal.zero;
    for (final row in disposals) {
      disposed += DecimalValue.parse(row.read<String>('quantity'));
    }
    final original = DecimalValue.parse(
      acquisition.read<String>('original_quantity'),
    );
    if (disposed >= original) return null;

    return InvestmentLotEditorSnapshot(
      lotId: lotId,
      contract: await findContract(vaultId, lotId),
      manualValues: (await manualValues(
        vaultId,
        lotId,
      )).where((value) => value.removedAt == null).toList(),
      acquisitionTransactionRevision: acquisition.read<int>(
        'acquisition_revision',
      ),
      disposalFingerprint: await disposalFingerprint(
        lotId,
        asOf: LocalDate(9999, 12, 31),
      ),
    );
  });

  @override
  Future<int> saveContract({
    required EntityId vaultId,
    required FixedIncomeContract contract,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  }) => _mutateLot(
    vaultId: vaultId,
    lotId: contract.lotId,
    expectedRevision: expectedTransactionRevision,
    updatedAt: updatedAt,
    expectedDisposalFingerprint: expectedDisposalFingerprint,
    action: () async {
      final row = await database
          .customSelect(
            'SELECT cost_currency_code FROM investment_lots WHERE id=?',
            variables: [Variable(contract.lotId.value)],
            readsFrom: {database.investmentLots},
          )
          .getSingle();
      if (row.read<String>('cost_currency_code') !=
          contract.terms.currency.value) {
        throw ArgumentError('Contract currency differs from acquisition lot.');
      }
      await _upsertContract(contract);
    },
  );

  @override
  Future<List<FixedIncomeManualValue>> manualValues(
    EntityId vaultId,
    EntityId lotId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT manual.* FROM fixed_income_manual_values manual '
          'INNER JOIN investment_lots lot ON lot.id=manual.lot_id '
          'INNER JOIN investment_events event ON event.id=lot.acquisition_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'WHERE manual.lot_id=? AND parent.vault_id=? AND parent.deleted_at IS NULL '
          'ORDER BY manual.value_date,manual.recorded_at,manual.id',
          variables: [Variable(lotId.value), Variable(vaultId.value)],
          readsFrom: {
            database.fixedIncomeManualValues,
            database.investmentLots,
            database.investmentEvents,
            database.transactions,
          },
        )
        .get();
    return [for (final row in rows) _manualFromRow(row.data)];
  }

  @override
  Future<String> disposalFingerprint(
    EntityId lotId, {
    required LocalDate asOf,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT disposal.id, parent.financial_date, disposal.quantity '
          'FROM investment_lot_disposals disposal '
          'INNER JOIN investment_events event ON event.id=disposal.disposal_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'WHERE disposal.lot_id=? AND parent.financial_date<=? '
          "AND parent.deleted_at IS NULL AND parent.status!='cancelled' "
          'ORDER BY disposal.id',
          variables: [Variable(lotId.value), Variable(asOf.toString())],
          readsFrom: {
            database.investmentLotDisposals,
            database.investmentEvents,
            database.transactions,
          },
        )
        .get();
    final entries = [
      for (final row in rows)
        [
          row.read<String>('id'),
          LocalDate.parse(row.read<String>('financial_date')).toString(),
          DecimalValue.canonical(
            DecimalValue.parse(row.read<String>('quantity')),
          ),
        ],
    ];
    final hash = await Sha256().hash(utf8.encode(jsonEncode([1, entries])));
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  Future<int> addManualValue({
    required EntityId vaultId,
    required FixedIncomeManualValue value,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  }) {
    _validateNewManualValue(value);
    return _mutateLot(
      vaultId: vaultId,
      lotId: value.lotId,
      expectedRevision: expectedTransactionRevision,
      updatedAt: updatedAt,
      expectedDisposalFingerprint: expectedDisposalFingerprint,
      action: () async {
        final fingerprint = await _validatedManualFingerprint(vaultId, value);
        await _insertManualValue(value, fingerprint);
      },
    );
  }

  @override
  Future<int> replaceManualValue({
    required EntityId vaultId,
    required EntityId oldValueId,
    required FixedIncomeManualValue newValue,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  }) {
    _validateNewManualValue(newValue);
    if (oldValueId == newValue.id) {
      throw ArgumentError('Replacement must have a new identity.');
    }
    return _mutateLot(
      vaultId: vaultId,
      lotId: newValue.lotId,
      expectedRevision: expectedTransactionRevision,
      updatedAt: updatedAt,
      expectedDisposalFingerprint: expectedDisposalFingerprint,
      action: () async {
        final fingerprint = await _validatedManualFingerprint(
          vaultId,
          newValue,
        );
        final changed = await database.customUpdate(
          'UPDATE fixed_income_manual_values SET removed_at=? '
          'WHERE id=? AND lot_id=? AND removed_at IS NULL',
          variables: [
            Variable(updatedAt.epochMicroseconds),
            Variable(oldValueId.value),
            Variable(newValue.lotId.value),
          ],
          updates: {database.fixedIncomeManualValues},
        );
        if (changed != 1) {
          throw StateError('Manual value is absent or removed.');
        }
        await _insertManualValue(newValue, fingerprint);
      },
    );
  }

  void _validateNewManualValue(FixedIncomeManualValue value) {
    if (value.amountMinor < 0 || value.removedAt != null) {
      throw ArgumentError('A new manual value must be active and nonnegative.');
    }
  }

  Future<String> _validatedManualFingerprint(
    EntityId vaultId,
    FixedIncomeManualValue value,
  ) async {
    final contract = await findContract(vaultId, value.lotId);
    if (contract == null || contract.terms.currency != value.currency) {
      throw StateError('Manual value requires a matching lot contract.');
    }
    final lot = await database
        .customSelect(
          'SELECT acquired_on FROM investment_lots WHERE id = ?',
          variables: [Variable<String>(value.lotId.value)],
          readsFrom: {database.investmentLots},
        )
        .getSingle();
    if (value.valueDate.compareTo(
          LocalDate.parse(lot.read<String>('acquired_on')),
        ) <
        0) {
      throw ArgumentError('Manual value cannot predate its lot.');
    }
    return disposalFingerprint(value.lotId, asOf: value.valueDate);
  }

  Future<void> _insertManualValue(
    FixedIncomeManualValue value,
    String fingerprint,
  ) async {
    await database.customStatement(
      'INSERT INTO fixed_income_manual_values '
      '(id,lot_id,value_date,amount_minor,currency_code,notes,recorded_at,removed_at,disposal_fingerprint) '
      'VALUES (?,?,?,?,?,?,?,NULL,?)',
      [
        value.id.value,
        value.lotId.value,
        value.valueDate.toString(),
        value.amountMinor,
        value.currency.value,
        value.notes,
        value.recordedAt.epochMicroseconds,
        fingerprint,
      ],
    );
  }

  @override
  Future<int> removeManualValue({
    required EntityId vaultId,
    required EntityId lotId,
    required EntityId valueId,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  }) => _mutateLot(
    vaultId: vaultId,
    lotId: lotId,
    expectedRevision: expectedTransactionRevision,
    updatedAt: updatedAt,
    expectedDisposalFingerprint: expectedDisposalFingerprint,
    action: () async {
      final changed = await database.customUpdate(
        'UPDATE fixed_income_manual_values SET removed_at=? '
        'WHERE id=? AND lot_id=? AND removed_at IS NULL',
        variables: [
          Variable(updatedAt.epochMicroseconds),
          Variable(valueId.value),
          Variable(lotId.value),
        ],
        updates: {database.fixedIncomeManualValues},
      );
      if (changed != 1) throw StateError('Manual value is absent or removed.');
    },
  );

  Future<int> _mutateLot({
    required EntityId vaultId,
    required EntityId lotId,
    required int expectedRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
    required Future<void> Function() action,
  }) async {
    if (expectedRevision < 1) {
      throw RangeError.value(expectedRevision, 'expectedRevision');
    }
    final rootId = await _acquisitionRoot(vaultId, lotId);
    if (rootId == null) throw StateError('Acquisition lot not found in vault.');
    Future<int> mutation() => database.transaction(() async {
      if (expectedDisposalFingerprint != null &&
          await disposalFingerprint(lotId, asOf: LocalDate(9999, 12, 31)) !=
              expectedDisposalFingerprint) {
        throw InvestmentLotStateConflict(lotId);
      }
      final changed = await database.customUpdate(
        'UPDATE transactions SET revision=revision+1,updated_at=? '
        'WHERE id=? AND vault_id=? AND revision=? AND deleted_at IS NULL',
        variables: [
          Variable(updatedAt.epochMicroseconds),
          Variable(rootId.value),
          Variable(vaultId.value),
          Variable(expectedRevision),
        ],
        updates: {database.transactions},
      );
      if (changed != 1) {
        final actual = await database
            .customSelect(
              'SELECT revision FROM transactions WHERE id=? AND vault_id=?',
              variables: [Variable(rootId.value), Variable(vaultId.value)],
              readsFrom: {database.transactions},
            )
            .getSingleOrNull();
        throw LedgerRevisionConflict(
          transactionId: rootId,
          expectedRevision: expectedRevision,
          actualRevision: actual?.read<int>('revision'),
        );
      }
      await action();
      return expectedRevision + 1;
    });
    return syncRecorder?.run(
          vaultId: vaultId.value,
          entityType: SyncEntityType.transaction,
          recordId: rootId.value,
          newRevision: expectedRevision + 1,
          operation: SyncOperation.upsert,
          action: mutation,
        ) ??
        mutation();
  }

  Future<EntityId?> _acquisitionRoot(EntityId vaultId, EntityId lotId) async {
    final row = await database
        .customSelect(
          'SELECT parent.id FROM investment_lots lot '
          'INNER JOIN investment_events event ON event.id=lot.acquisition_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'INNER JOIN investment_instruments instrument ON instrument.id=lot.instrument_id '
          "WHERE lot.id=? AND parent.vault_id=? AND instrument.vault_id=? "
          "AND parent.deleted_at IS NULL AND parent.status!='cancelled' "
          "AND instrument.deleted_at IS NULL AND instrument.asset_class='fixed_income'",
          variables: [
            Variable(lotId.value),
            Variable(vaultId.value),
            Variable(vaultId.value),
          ],
          readsFrom: {
            database.investmentLots,
            database.investmentEvents,
            database.transactions,
            database.investmentInstruments,
          },
        )
        .getSingleOrNull();
    return row == null ? null : EntityId.parse(row.read<String>('id'));
  }

  Future<void> _upsertContract(
    FixedIncomeContract contract,
  ) => database.customStatement(
    'INSERT INTO fixed_income_contracts '
    '(lot_id,principal,currency_code,product_name,issuer_name,accrual_start,'
    'maturity_on,liquidity_on,remuneration_mode,index_code,index_multiplier,'
    'annual_rate,annual_spread,day_count_basis,calendar_version,'
    'publication_lag_months,anniversary_day,update_rule) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT(lot_id) DO UPDATE SET '
    'principal=excluded.principal,currency_code=excluded.currency_code,'
    'product_name=excluded.product_name,issuer_name=excluded.issuer_name,'
    'accrual_start=excluded.accrual_start,maturity_on=excluded.maturity_on,'
    'liquidity_on=excluded.liquidity_on,remuneration_mode=excluded.remuneration_mode,'
    'index_code=excluded.index_code,index_multiplier=excluded.index_multiplier,'
    'annual_rate=excluded.annual_rate,annual_spread=excluded.annual_spread,'
    'day_count_basis=excluded.day_count_basis,calendar_version=excluded.calendar_version,'
    'publication_lag_months=excluded.publication_lag_months,'
    'anniversary_day=excluded.anniversary_day,update_rule=excluded.update_rule',
    [
      contract.lotId.value,
      DecimalValue.canonical(contract.terms.principal),
      contract.terms.currency.value,
      contract.terms.productName,
      contract.terms.issuerName,
      contract.terms.accrualStart.toString(),
      contract.terms.maturityOn?.toString(),
      contract.terms.liquidityOn?.toString(),
      contract.terms.mode.name,
      contract.terms.indexCode?.sgsCode,
      contract.terms.indexMultiplier == null
          ? null
          : DecimalValue.canonical(contract.terms.indexMultiplier!),
      contract.terms.annualRate == null
          ? null
          : DecimalValue.canonical(contract.terms.annualRate!),
      contract.terms.annualSpread == null
          ? null
          : DecimalValue.canonical(contract.terms.annualSpread!),
      contract.terms.dayCountBasis,
      contract.terms.calendarVersion,
      contract.terms.publicationLagMonths,
      contract.terms.anniversaryDay,
      contract.terms.updateRule.name,
    ],
  );

  FixedIncomeContract _contractFromRow(Map<String, Object?> row) =>
      FixedIncomeContract(
        lotId: EntityId.parse(row['lot_id']! as String),
        terms: FixedIncomeTerms(
          principal: DecimalValue.parse(row['principal']! as String),
          currency: CurrencyCode(row['currency_code']! as String),
          productName: row['product_name']! as String,
          issuerName: row['issuer_name'] as String?,
          accrualStart: LocalDate.parse(row['accrual_start']! as String),
          maturityOn: row['maturity_on'] == null
              ? null
              : LocalDate.parse(row['maturity_on']! as String),
          liquidityOn: row['liquidity_on'] == null
              ? null
              : LocalDate.parse(row['liquidity_on']! as String),
          mode: FixedIncomeRemunerationMode.values.byName(
            row['remuneration_mode']! as String,
          ),
          indexCode: row['index_code'] == null
              ? null
              : EconomicSeriesCode.values.singleWhere(
                  (code) => code.sgsCode == row['index_code'],
                ),
          indexMultiplier: row['index_multiplier'] == null
              ? null
              : DecimalValue.parse(row['index_multiplier']! as String),
          annualRate: row['annual_rate'] == null
              ? null
              : DecimalValue.parse(row['annual_rate']! as String),
          annualSpread: row['annual_spread'] == null
              ? null
              : DecimalValue.parse(row['annual_spread']! as String),
          dayCountBasis: row['day_count_basis'] as int?,
          calendarVersion: row['calendar_version'] as String?,
          publicationLagMonths: row['publication_lag_months']! as int,
          anniversaryDay: row['anniversary_day'] as int?,
          updateRule: FixedIncomeUpdateRule.values.byName(
            row['update_rule']! as String,
          ),
        ),
      );

  FixedIncomeManualValue _manualFromRow(Map<String, Object?> row) =>
      FixedIncomeManualValue(
        id: EntityId.parse(row['id']! as String),
        lotId: EntityId.parse(row['lot_id']! as String),
        valueDate: LocalDate.parse(row['value_date']! as String),
        amountMinor: row['amount_minor']! as int,
        currency: CurrencyCode(row['currency_code']! as String),
        notes: row['notes'] as String?,
        recordedAt: UtcInstant.fromEpochMicroseconds(
          row['recorded_at']! as int,
        ),
        removedAt: row['removed_at'] == null
            ? null
            : UtcInstant.fromEpochMicroseconds(row['removed_at']! as int),
        disposalFingerprint: row['disposal_fingerprint'] as String?,
      );

  @override
  Future<void> saveSale(
    LedgerTransaction transaction,
    List<LotDisposal> disposals,
  ) => database.transaction(() async {
    final event = transaction.investmentEvents.single;
    if (disposals.any((item) => item.disposalEventId != event.id)) {
      throw StateError('Disposal event mismatch.');
    }
    final positions = {
      for (final item in await lotPositions(
        event.instrumentId,
        asOf: transaction.financialDate,
      ))
        item.lot.id: item,
    };
    final perLot = <EntityId, Decimal>{};
    for (final item in disposals) {
      perLot[item.lotId] = (perLot[item.lotId] ?? Decimal.zero) + item.quantity;
    }
    for (final entry in perLot.entries) {
      final position = positions[entry.key];
      if (position == null || entry.value > position.remainingQuantity) {
        throw InsufficientLotQuantity(event.instrumentId);
      }
    }
    await ledger.save(transaction);
    for (final item in disposals) {
      await database.customStatement(
        'INSERT INTO investment_lot_disposals (id,disposal_event_id,lot_id,quantity,allocated_cost_minor) '
        'VALUES (?,?,?,?,?)',
        [
          item.id.value,
          item.disposalEventId.value,
          item.lotId.value,
          DecimalValue.canonical(item.quantity),
          item.allocatedCostMinor,
        ],
      );
    }
  });

  @override
  Future<void> saveLedgerTransaction(LedgerTransaction transaction) =>
      ledger.save(transaction);

  @override
  Future<List<LotPosition>> lotPositions(
    EntityId instrumentId, {
    required LocalDate asOf,
  }) async {
    final lots = await database
        .customSelect(
          'SELECT lot.* FROM investment_lots lot '
          'INNER JOIN investment_events event ON event.id=lot.acquisition_event_id '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id '
          'WHERE lot.instrument_id=? AND parent.financial_date<=? AND parent.deleted_at IS NULL '
          "AND parent.status!='cancelled' ORDER BY lot.acquired_on,lot.id",
          variables: [
            Variable<String>(instrumentId.value),
            Variable<String>(asOf.toString()),
          ],
          readsFrom: {
            database.investmentLots,
            database.investmentEvents,
            database.transactions,
          },
        )
        .get();
    final result = <LotPosition>[];
    for (final row in lots) {
      final id = EntityId.parse(row.read<String>('id'));
      final disposalRows = await database
          .customSelect(
            'SELECT disposal.quantity,disposal.allocated_cost_minor '
            'FROM investment_lot_disposals disposal INNER JOIN investment_events event '
            'ON event.id=disposal.disposal_event_id INNER JOIN transactions parent '
            'ON parent.id=event.transaction_id WHERE disposal.lot_id=? AND parent.financial_date<=? '
            "AND parent.deleted_at IS NULL AND parent.status!='cancelled'",
            variables: [
              Variable<String>(id.value),
              Variable<String>(asOf.toString()),
            ],
            readsFrom: {
              database.investmentLotDisposals,
              database.investmentEvents,
              database.transactions,
            },
          )
          .get();
      var quantity = Decimal.zero, cost = 0;
      for (final disposal in disposalRows) {
        quantity += DecimalValue.parse(disposal.read<String>('quantity'));
        cost += disposal.read<int>('allocated_cost_minor');
      }
      result.add(
        LotPosition(
          lot: InvestmentLot(
            id: id,
            acquisitionEventId: EntityId.parse(
              row.read<String>('acquisition_event_id'),
            ),
            instrumentId: instrumentId,
            acquiredOn: LocalDate.parse(row.read<String>('acquired_on')),
            originalQuantity: DecimalValue.parse(
              row.read<String>('original_quantity'),
            ),
            costBasisMinor: row.read<int>('cost_basis_minor'),
            costCurrency: CurrencyCode(row.read<String>('cost_currency_code')),
          ),
          disposedQuantity: quantity,
          allocatedCostMinor: cost,
        ),
      );
    }
    return result;
  }

  @override
  Future<InvestmentPerformanceSource> performance(
    EntityId instrumentId, {
    required LocalDate asOf,
  }) async {
    final events = await database
        .customSelect(
          'SELECT event.* FROM investment_events event '
          'INNER JOIN transactions parent ON parent.id=event.transaction_id WHERE event.instrument_id=? '
          'AND parent.financial_date<=? AND parent.deleted_at IS NULL AND parent.status!=\'cancelled\'',
          variables: [
            Variable<String>(instrumentId.value),
            Variable<String>(asOf.toString()),
          ],
          readsFrom: {database.investmentEvents, database.transactions},
        )
        .get();
    var realized = 0, income = 0;
    for (final event in events) {
      final type = event.read<String>('event_type');
      final net =
          (event.readNullable<int>('gross_minor') ?? 0) -
          (event.readNullable<int>('fees_minor') ?? 0) -
          (event.readNullable<int>('taxes_minor') ?? 0);
      if (type == 'dividend' || type == 'interest') {
        income += net;
      }
      if (type == 'sell') {
        final cost =
            (await database
                    .customSelect(
                      'SELECT COALESCE(SUM(allocated_cost_minor),0) total '
                      'FROM investment_lot_disposals WHERE disposal_event_id=?',
                      variables: [Variable<String>(event.read<String>('id'))],
                      readsFrom: {database.investmentLotDisposals},
                    )
                    .getSingle())
                .read<int>('total');
        realized += net - cost;
      }
    }
    return InvestmentPerformanceSource(
      realizedMinor: realized,
      incomeMinor: income,
    );
  }

  @override
  Future<InvestmentPrice?> latestPrice(
    EntityId vaultId,
    EntityId instrumentId,
    CurrencyCode instrumentCurrency, {
    required LocalDate asOf,
  }) async {
    final manual = await database
        .customSelect(
          'SELECT price, currency_code, price_date FROM manual_market_prices '
          'WHERE vault_id=? AND instrument_id=? AND price_date<=? AND deleted_at IS NULL '
          'ORDER BY price_date DESC,updated_at DESC LIMIT 1',
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(instrumentId.value),
            Variable<String>(asOf.toString()),
          ],
          readsFrom: {database.manualMarketPrices},
        )
        .getSingleOrNull();
    if (manual != null) {
      return InvestmentPrice(
        price: DecimalValue.parse(manual.read<String>('price')),
        currency: CurrencyCode(manual.read<String>('currency_code')),
        date: LocalDate.parse(manual.read<String>('price_date')),
        manual: true,
      );
    }
    final cutoff = DateTime.utc(
      asOf.year,
      asOf.month,
      asOf.day + 1,
    ).microsecondsSinceEpoch;
    final cached = await database
        .customSelect(
          'SELECT price,currency_code,price_timestamp FROM market_price_cache '
          'WHERE instrument_id=? AND price_timestamp<? ORDER BY price_timestamp DESC,fetched_at DESC LIMIT 1',
          variables: [
            Variable<String>(instrumentId.value),
            Variable<int>(cutoff),
          ],
          readsFrom: {database.marketPriceCache},
        )
        .getSingleOrNull();
    if (cached == null) return null;
    final instant = DateTime.fromMicrosecondsSinceEpoch(
      cached.read<int>('price_timestamp'),
      isUtc: true,
    );
    return InvestmentPrice(
      price: DecimalValue.parse(cached.read<String>('price')),
      currency: CurrencyCode(cached.read<String>('currency_code')),
      date: LocalDate(instant.year, instant.month, instant.day),
      manual: false,
    );
  }
}

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map(Variable<Object>.new).toList(growable: false);
