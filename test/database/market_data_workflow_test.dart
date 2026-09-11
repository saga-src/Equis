import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:equis/application/ports/market_data_ports.dart';
import 'package:equis/application/services/market_data_service.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide InvestmentInstrument, ManualMarketPrice;
import 'package:equis/infrastructure/repositories/drift_investment_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_market_price_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late EntityId vaultId;
  late InvestmentInstrument instrument;
  late DriftMarketPriceRepository prices;
  late _FakeProvider provider;
  late MarketDataService service;

  const now = UtcInstant.fromEpochMicroseconds(2 * Duration.microsecondsPerDay);
  final asOf = LocalDate(1970, 1, 3);

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    vaultId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) '
      "VALUES (?,?,'BRL','UTC',1,1)",
      [vaultId.value, 'Local'],
    );
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('BRL','brl','R\$',2)",
    );
    final investments = DriftInvestmentRepository(
      database: database,
      ledger: DriftLedgerRepository(database),
    );
    instrument = InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Petrobras',
      symbol: 'PETR4',
      exchange: 'B3',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      createdAt: now,
      updatedAt: now,
    );
    await investments.saveInstrument(instrument);
    prices = DriftMarketPriceRepository(database);
    provider = _FakeProvider();
    service = MarketDataService(
      instruments: investments,
      prices: prices,
      provider: provider,
      staleAfter: const Duration(hours: 24),
    );
  });

  tearDown(() => database.close());

  test(
    'cached quote survives offline failure and becomes visibly stale',
    () async {
      provider.next = MarketQuote(
        instrumentId: instrument.id,
        price: Decimal.parse('42.125'),
        currency: CurrencyCode.brl,
        timestamp: now,
        provider: 'brapi',
      );
      final fresh = await service.load(
        vaultId: vaultId,
        asOf: asOf,
        now: now,
        refresh: true,
      );
      expect(fresh.single.quote?.price.toString(), '42.125');
      expect(provider.requests.single.provider, MarketProvider.brapi);

      provider.fail = true;
      final offline = await service.load(
        vaultId: vaultId,
        asOf: asOf,
        now: UtcInstant.fromEpochMicroseconds(
          now.epochMicroseconds + 2 * Duration.microsecondsPerDay,
        ),
        refresh: true,
      );
      expect(offline.single.quote?.price.toString(), '42.125');
      expect(offline.single.refreshFailed, isTrue);
      expect(offline.single.stale, isTrue);
    },
  );

  test('manual override wins without deleting the automatic cache', () async {
    final automatic = MarketQuote(
      instrumentId: instrument.id,
      price: Decimal.parse('40.5'),
      currency: CurrencyCode.brl,
      timestamp: now,
      provider: 'brapi',
    );
    await prices.saveAutomatic(automatic);
    await service.override(
      vaultId: vaultId,
      instrument: instrument,
      date: asOf,
      price: Decimal.parse('41.7500'),
      now: now,
    );

    final selected = await service.load(
      vaultId: vaultId,
      asOf: asOf,
      now: now,
      refresh: true,
    );
    expect(selected.single.source, MarketPriceSource.manual);
    expect(selected.single.quote?.price.toString(), '41.75');
    expect(provider.requests, isEmpty);
    expect(
      (await prices.latestAutomatic(instrument.id))?.price,
      automatic.price,
    );
  });
}

final class _FakeProvider implements MarketDataProvider {
  MarketQuote? next;
  bool fail = false;
  final requests = <MarketQuoteRequest>[];

  @override
  Future<MarketQuote?> quote(MarketQuoteRequest request) async {
    requests.add(request);
    if (fail) throw const _Offline();
    return next;
  }

  @override
  Future<List<MarketQuote>> history(
    MarketQuoteRequest request, {
    required LocalDate from,
    required LocalDate through,
  }) async => const [];
}

final class _Offline implements Exception {
  const _Offline();
}
