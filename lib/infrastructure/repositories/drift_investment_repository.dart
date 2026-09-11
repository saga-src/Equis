import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../application/ports/investment_repository.dart';
import '../../application/ports/ledger_repository.dart';
import '../../domain/investments/investment_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart'
    hide InvestmentInstrument, InvestmentLot;
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
    InvestmentLot lot,
  ) => database.transaction(() async {
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
  });

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
