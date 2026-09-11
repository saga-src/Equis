import 'package:drift/drift.dart';

import '../../application/ports/market_data_ports.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart' hide ManualMarketPrice;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftMarketPriceRepository implements MarketPriceRepository {
  const DriftMarketPriceRepository(this.database, {this.syncRecorder});
  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;
  @override
  Future<void> saveAutomatic(MarketQuote quote) => database.customStatement(
    'INSERT OR REPLACE INTO market_price_cache '
    '(instrument_id,price_timestamp,price,currency_code,provider,fetched_at) VALUES (?,?,?,?,?,?)',
    [
      quote.instrumentId.value,
      quote.timestamp.epochMicroseconds,
      DecimalValue.canonical(quote.price),
      quote.currency.value,
      quote.provider,
      UtcInstant.now().epochMicroseconds,
    ],
  );
  @override
  Future<void> saveManual(ManualMarketPrice price) =>
      syncRecorder?.run(
        vaultId: price.vaultId.value,
        entityType: SyncEntityType.manualMarketPrice,
        recordId: price.id.value,
        newRevision: price.revision,
        operation: price.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _saveManual(price),
      ) ??
      _saveManual(price);

  Future<void> _saveManual(ManualMarketPrice price) => database.customStatement(
    'INSERT INTO manual_market_prices (id,vault_id,instrument_id,price_date,price,currency_code,'
    'notes,revision,created_at,updated_at,deleted_at) VALUES (?,?,?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT(id) DO UPDATE SET price_date=excluded.price_date,price=excluded.price,'
    'currency_code=excluded.currency_code,notes=excluded.notes,revision=excluded.revision,'
    'updated_at=excluded.updated_at,deleted_at=excluded.deleted_at',
    [
      price.id.value,
      price.vaultId.value,
      price.instrumentId.value,
      price.date.toString(),
      DecimalValue.canonical(price.price),
      price.currency.value,
      price.notes,
      price.revision,
      price.createdAt.epochMicroseconds,
      price.updatedAt.epochMicroseconds,
      price.deletedAt?.epochMicroseconds,
    ],
  );
  @override
  Future<ManualMarketPrice?> latestManual(
    EntityId vaultId,
    EntityId instrumentId, {
    required LocalDate asOf,
  }) async {
    final row = await database
        .customSelect(
          'SELECT * FROM manual_market_prices WHERE vault_id=? '
          'AND instrument_id=? AND price_date<=? AND deleted_at IS NULL ORDER BY price_date DESC,updated_at DESC LIMIT 1',
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(instrumentId.value),
            Variable<String>(asOf.toString()),
          ],
          readsFrom: {database.manualMarketPrices},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return ManualMarketPrice(
      id: EntityId.parse(row.read<String>('id')),
      vaultId: vaultId,
      instrumentId: instrumentId,
      date: LocalDate.parse(row.read<String>('price_date')),
      price: DecimalValue.parse(row.read<String>('price')),
      currency: CurrencyCode(row.read<String>('currency_code')),
      notes: row.readNullable<String>('notes'),
      revision: row.read<int>('revision'),
      createdAt: UtcInstant.fromEpochMicroseconds(row.read<int>('created_at')),
      updatedAt: UtcInstant.fromEpochMicroseconds(row.read<int>('updated_at')),
      deletedAt: row.readNullable<int>('deleted_at') == null
          ? null
          : UtcInstant.fromEpochMicroseconds(row.read<int>('deleted_at')),
    );
  }

  @override
  Future<MarketQuote?> latestAutomatic(
    EntityId instrumentId, {
    LocalDate? asOf,
  }) async {
    final cutoff = asOf == null
        ? null
        : DateTime.utc(
            asOf.year,
            asOf.month,
            asOf.day + 1,
          ).microsecondsSinceEpoch;
    final row = await database
        .customSelect(
          'SELECT * FROM market_price_cache WHERE instrument_id=? '
          '${cutoff == null ? '' : 'AND price_timestamp<? '}ORDER BY price_timestamp DESC,fetched_at DESC LIMIT 1',
          variables: [
            Variable<String>(instrumentId.value),
            if (cutoff != null) Variable<int>(cutoff),
          ],
          readsFrom: {database.marketPriceCache},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return MarketQuote(
      instrumentId: instrumentId,
      price: DecimalValue.parse(row.read<String>('price')),
      currency: CurrencyCode(row.read<String>('currency_code')),
      timestamp: UtcInstant.fromEpochMicroseconds(
        row.read<int>('price_timestamp'),
      ),
      provider: row.read<String>('provider'),
    );
  }
}
