import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:equis/application/ports/fx_rate_ports.dart';
import 'package:equis/application/ports/market_data_ports.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/fx_rate_selector.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/application/services/market_data_service.dart';
import 'package:equis/application/services/startup_refresh_service.dart';
import 'package:equis/application/services/taxonomy_service.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/fx/fx_models.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide InvestmentInstrument;
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_fx_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_investment_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_market_price_repository.dart';
import 'package:equis/infrastructure/repositories/drift_startup_refresh_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('open refresh persists a three-hour gate across service restarts', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const now = UtcInstant.fromEpochMicroseconds(1800000000000000);
    final vaultId = EntityId.generate();
    await DriftVaultRepository(database).save(
      VaultProfile(
        id: vaultId,
        name: 'Local',
        baseCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('BRL','brl','R\$',2),('USD','usd','\$',2)",
    );
    final accountId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) '
      "VALUES (?,?,'Dollar account','checking','asset',1,1)",
      [accountId.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id,account_id,currency_code,is_default) '
      "VALUES (?,?,'USD',1)",
      [EntityId.generate().value, accountId.value],
    );

    final ledger = DriftLedgerRepository(database);
    final investments = DriftInvestmentRepository(
      database: database,
      ledger: ledger,
    );
    final instrument = InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Acme',
      symbol: 'ACME',
      exchange: 'NYSE',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.usd,
      createdAt: now,
      updatedAt: now,
    );
    await investments.saveInstrument(instrument);

    final vaults = DriftVaultRepository(database);
    final accounts = DriftAccountAggregateRepository(database);
    final categories = DriftCategoryRepository(database);
    final tags = DriftTagRepository(database);
    final unitOfWork = DriftLocalUnitOfWork(database);
    final session = LocalFinanceSessionService(
      vaults: vaults,
      accounts: accounts,
      categories: categories,
      tags: tags,
      ledger: ledger,
      unitOfWork: unitOfWork,
      containers: LocalFinanceContainerService(
        vaults: vaults,
        currencies: DriftCurrencyRepository(database),
        accounts: accounts,
        ledger: ledger,
        unitOfWork: unitOfWork,
      ),
      taxonomy: TaxonomyService(categories: categories, tags: tags),
      everydayTransactions: EverydayTransactionService(ledger: ledger),
    );
    var cacheClock = now;
    final prices = DriftMarketPriceRepository(
      database,
      clock: () => cacheClock,
    );
    final marketProvider = _MarketProvider(instrument, now);
    final fxCache = DriftFxRateCacheRepository(
      database,
      clock: () => cacheClock,
    );
    final fxProvider = _FxProvider();

    StartupRefreshService service() => StartupRefreshService(
      session: session,
      marketData: MarketDataService(
        instruments: investments,
        prices: prices,
        provider: marketProvider,
      ),
      fxRates: FxRateSelector(
        manualRates: DriftManualFxRateRepository(database),
        cache: fxCache,
        provider: fxProvider,
      ),
      gate: DriftStartupRefreshGate(database),
    );

    final first = await service().refreshOnOpen(now);
    expect(first.attempted, isTrue);
    expect(marketProvider.calls, 1);
    expect(fxProvider.calls, 1);
    expect(await prices.latestAutomaticFetchedAt(instrument.id), now);
    expect(
      await fxCache.latestFetchedAt(
        base: CurrencyCode.brl,
        quote: CurrencyCode.usd,
      ),
      now,
    );

    final twoHoursLater = UtcInstant.fromEpochMicroseconds(
      now.epochMicroseconds + const Duration(hours: 2).inMicroseconds,
    );
    final skipped = await service().refreshOnOpen(twoHoursLater);
    expect(skipped.attempted, isFalse);
    expect(marketProvider.calls, 1);
    expect(fxProvider.calls, 1);

    cacheClock = UtcInstant.fromEpochMicroseconds(
      now.epochMicroseconds + const Duration(hours: 3).inMicroseconds,
    );
    final refreshed = await service().refreshOnOpen(cacheClock);
    expect(refreshed.attempted, isTrue);
    expect(marketProvider.calls, 2);
    expect(fxProvider.calls, 2);
  });
}

final class _MarketProvider implements MarketDataProvider {
  _MarketProvider(this.instrument, this.timestamp);
  final InvestmentInstrument instrument;
  final UtcInstant timestamp;
  int calls = 0;
  int heartbeatCalls = 0;

  @override
  Future<void> heartbeat(List<MarketQuoteRequest> assets) async {
    heartbeatCalls++;
  }

  @override
  Future<List<MarketInstrumentCandidate>> search({
    required String query,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    int limit = 10,
  }) async => const [];

  @override
  Future<MarketQuotePreview?> quoteCandidate(
    MarketInstrumentCandidate candidate,
  ) async => null;

  @override
  Future<MarketQuote?> quote(MarketQuoteRequest request) async {
    calls++;
    return MarketQuote(
      instrumentId: instrument.id,
      price: Decimal.parse('25.50'),
      currency: instrument.currency,
      timestamp: timestamp,
      provider: 'twelve_data',
    );
  }

  @override
  Future<List<MarketQuote>> history(
    MarketQuoteRequest request, {
    required LocalDate from,
    required LocalDate through,
  }) async => const [];
}

final class _FxProvider implements FxRateProvider {
  int calls = 0;

  @override
  Future<FxRateQuote?> quote({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) async {
    calls++;
    return FxRateQuote(
      base: base,
      quote: quote,
      requestedDate: date,
      rateDate: date,
      rate: '0.20',
      source: FxRateSource.automaticExact,
      provider: 'frankfurter_v2',
    );
  }
}
