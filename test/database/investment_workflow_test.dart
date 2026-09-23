import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:equis/application/ports/investment_repository.dart';
import 'package:equis/application/services/investment_service.dart';
import 'package:equis/application/services/wealth_service.dart';
import 'package:equis/application/sync/sync_models.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide InvestmentInstrument, InvestmentLot;
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_investment_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_wealth_repository.dart';
import 'package:equis/infrastructure/sync/drift_sync_aggregate_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_metadata_store.dart';
import 'package:equis/infrastructure/sync/drift_sync_mutation_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftInvestmentRepository repository;
  late DriftLedgerRepository ledger;
  late InvestmentService service;
  late EntityId vaultId;
  late LedgerPocket cash;
  late LedgerPocket regularCash;
  late LedgerPocket usdCash;
  late LedgerPocket usdRegularCash;
  late EntityId categoryId;
  late EntityId expenseCategoryId;
  late InvestmentInstrument instrument;
  late InvestmentInstrument usdInstrument;
  const now = UtcInstant.fromEpochMicroseconds(1000);

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    ledger = DriftLedgerRepository(database);
    repository = DriftInvestmentRepository(database: database, ledger: ledger);
    service = InvestmentService(
      repository: repository,
      reporting: DriftDashboardRepository(database),
      unitOfWork: DriftLocalUnitOfWork(database),
    );
    vaultId = EntityId.generate();
    final account = EntityId.generate();
    final pocket = EntityId.generate();
    final regularAccount = EntityId.generate();
    final regularPocket = EntityId.generate();
    final usdAccount = EntityId.generate();
    final usdPocket = EntityId.generate();
    final usdRegularAccount = EntityId.generate();
    final usdRegularPocket = EntityId.generate();
    categoryId = EntityId.generate();
    expenseCategoryId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) '
      'VALUES (?,?,\'BRL\',\'UTC\',1,1)',
      [vaultId.value, 'Local'],
    );
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('BRL','brl','R\$',2)",
    );
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('USD','usd','\$',2)",
    );
    await database.customStatement(
      'INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) '
      'VALUES (?,?,\'Broker\',\'investment\',\'asset\',1,1)',
      [account.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id,account_id,currency_code,is_default) VALUES (?,?,\'BRL\',1)',
      [pocket.value, account.value],
    );
    await database.customStatement(
      'INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) '
      'VALUES (?,?,\'Bank\',\'checking\',\'asset\',1,1)',
      [regularAccount.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id,account_id,currency_code,is_default) VALUES (?,?,\'BRL\',1)',
      [regularPocket.value, regularAccount.value],
    );
    await database.customStatement(
      'INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) '
      'VALUES (?,?,\'USD Broker\',\'investment\',\'asset\',1,1)',
      [usdAccount.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id,account_id,currency_code,is_default) VALUES (?,?,\'USD\',1)',
      [usdPocket.value, usdAccount.value],
    );
    await database.customStatement(
      'INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) '
      'VALUES (?,?,\'USD Bank\',\'checking\',\'asset\',1,1)',
      [usdRegularAccount.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id,account_id,currency_code,is_default) VALUES (?,?,\'USD\',1)',
      [usdRegularPocket.value, usdRegularAccount.value],
    );
    await database.customStatement(
      'INSERT INTO categories (id,vault_id,category_type,custom_name,created_at,updated_at) '
      'VALUES (?,?,\'income\',\'Investment income\',1,1)',
      [categoryId.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO categories (id,vault_id,category_type,custom_name,created_at,updated_at) '
      'VALUES (?,?,\'expense\',\'Broker fee\',1,1)',
      [expenseCategoryId.value, vaultId.value],
    );
    cash = LedgerPocket(
      id: pocket,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    );
    regularCash = LedgerPocket(
      id: regularPocket,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    );
    usdCash = LedgerPocket(
      id: usdPocket,
      currency: CurrencyCode.usd,
      nature: AccountNature.asset,
    );
    usdRegularCash = LedgerPocket(
      id: usdRegularPocket,
      currency: CurrencyCode.usd,
      nature: AccountNature.asset,
    );
    instrument = await service.createInstrument(
      vaultId: vaultId,
      name: 'Acme',
      symbol: 'ACME3',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      exchange: 'B3',
      now: now,
    );
    usdInstrument = await service.createInstrument(
      vaultId: vaultId,
      name: 'Global ETF',
      symbol: 'WORLD',
      assetClass: InvestmentAssetClass.etf,
      currency: CurrencyCode.usd,
      exchange: 'NYSE',
      now: now,
    );
  });
  tearDown(() => database.close());

  test(
    'partial FIFO sale preserves lots and reconciles realized and unrealized results',
    () async {
      await service.buy(
        instrument: instrument,
        cashPocket: cash,
        quantity: Decimal.fromInt(10),
        unitPrice: Decimal.fromInt(10),
        feesMinor: 100,
        date: LocalDate(2026, 1, 10),
        now: now,
      );
      await service.buy(
        instrument: instrument,
        cashPocket: cash,
        quantity: Decimal.fromInt(5),
        unitPrice: Decimal.fromInt(12),
        feesMinor: 50,
        date: LocalDate(2026, 2, 10),
        now: now,
      );
      await service.sell(
        instrument: instrument,
        cashPocket: cash,
        quantity: Decimal.fromInt(12),
        unitPrice: Decimal.fromInt(15),
        feesMinor: 200,
        taxesMinor: 100,
        date: LocalDate(2026, 3, 10),
        now: now,
      );
      await service.income(
        instrument: instrument,
        cashPocket: cash,
        categoryId: categoryId,
        amountMinor: 500,
        date: LocalDate(2026, 3, 20),
        now: now,
        interest: false,
      );
      await database.customStatement(
        'INSERT INTO manual_market_prices '
        '(id,vault_id,instrument_id,price_date,price,currency_code,revision,created_at,updated_at) '
        'VALUES (?,?,?,?,\'20\',\'BRL\',1,1,1)',
        [
          EntityId.generate().value,
          vaultId.value,
          instrument.id.value,
          '2026-03-31',
        ],
      );

      final report = await service.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 3, 31),
      );
      final holding = report.holdings.singleWhere(
        (item) => item.instrument.id == instrument.id,
      );
      expect(holding.quantity, Decimal.fromInt(3));
      expect(holding.lots.map((lot) => lot.remainingQuantity), [
        Decimal.zero,
        Decimal.fromInt(3),
      ]);
      expect(holding.costBasisMinor, 3630);
      expect(holding.averageCost, Decimal.parse('12.1'));
      expect(holding.marketValueMinor, 6000);
      expect(holding.unrealizedMinor, 2370);
      expect(holding.realizedMinor, 5180);
      expect(holding.incomeMinor, 500);
      expect(holding.allocationBps, 10000);
      expect(report.marketValueMinor, 6000);
      final cashBalance =
          (await database
                  .customSelect(
                    'SELECT SUM(amount_minor) total FROM account_movements '
                    'WHERE account_pocket_id=?',
                    variables: [Variable<String>(cash.id.value)],
                  )
                  .getSingle())
              .read<int>('total');
      expect(cashBalance, 2050);
      final wealth =
          await WealthService(
            repository: DriftWealthRepository(database),
            reporting: DriftDashboardRepository(database),
            investments: service,
          ).report(
            vaultId: vaultId,
            currency: CurrencyCode.brl,
            asOf: LocalDate(2026, 3, 31),
            historyMonths: 1,
          );
      expect(wealth.current.netWorthMinor, 8050);
    },
  );

  test(
    'historical initial purchase creates FIFO lot and reduces cash',
    () async {
      final created = await service.createInstrumentWithInitialPosition(
        vaultId: vaultId,
        name: 'Initial buy',
        symbol: 'INIT3',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.brl,
        exchange: 'B3',
        now: now,
        initialPosition: InitialPositionDraft(
          mode: InitialPositionMode.historicalBuy,
          cashPocket: cash,
          quantity: Decimal.fromInt(2),
          unitPrice: Decimal.fromInt(10),
          feesMinor: 100,
          date: LocalDate(2026, 1, 1),
        ),
      );

      final positions = await repository.lotPositions(
        created.id,
        asOf: LocalDate(2026, 1, 1),
      );
      expect(positions.single.remainingQuantity, Decimal.fromInt(2));
      expect(positions.single.remainingCostMinor, 2100);
      final cashTotal = await database
          .customSelect(
            'SELECT COALESCE(SUM(amount_minor),0) total FROM account_movements '
            'WHERE account_pocket_id=?',
            variables: [Variable<String>(cash.id.value)],
          )
          .getSingle();
      expect(cashTotal.read<int>('total'), -2100);
    },
  );

  test('imported initial position creates FIFO cost with neutral cash', () async {
    final created = await service.createInstrumentWithInitialPosition(
      vaultId: vaultId,
      name: 'Imported position',
      symbol: 'OPEN3',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      exchange: 'B3',
      now: now,
      initialPosition: InitialPositionDraft(
        mode: InitialPositionMode.openingPosition,
        cashPocket: cash,
        quantity: Decimal.fromInt(2),
        unitPrice: Decimal.fromInt(10),
        feesMinor: 100,
        date: LocalDate(2026, 1, 1),
      ),
    );

    final positions = await repository.lotPositions(
      created.id,
      asOf: LocalDate(2026, 1, 1),
    );
    expect(positions.single.remainingCostMinor, 2100);
    final transaction = await database
        .customSelect(
          'SELECT parent.transaction_type,COALESCE(SUM(movement.amount_minor),0) total '
          'FROM transactions parent INNER JOIN investment_events event '
          'ON event.transaction_id=parent.id INNER JOIN account_movements movement '
          'ON movement.transaction_id=parent.id WHERE event.instrument_id=? '
          'GROUP BY parent.id,parent.transaction_type',
          variables: [Variable<String>(created.id.value)],
        )
        .getSingle();
    expect(transaction.read<String>('transaction_type'), 'adjustment');
    expect(transaction.read<int>('total'), 0);
  });

  test('asset creation rolls back when initial position is invalid', () async {
    await expectLater(
      service.createInstrumentWithInitialPosition(
        vaultId: vaultId,
        name: 'Must roll back',
        symbol: 'ROLL3',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.brl,
        now: now,
        initialPosition: InitialPositionDraft(
          mode: InitialPositionMode.historicalBuy,
          cashPocket: cash,
          quantity: Decimal.zero,
          unitPrice: Decimal.one,
          date: LocalDate(2026, 1, 1),
        ),
      ),
      throwsArgumentError,
    );
    final row = await database
        .customSelect(
          "SELECT COUNT(*) total FROM investment_instruments WHERE symbol='ROLL3'",
        )
        .getSingle();
    expect(row.read<int>('total'), 0);
  });

  test('existing asset can be linked to provider identity', () async {
    final linked = await service.linkMarketCandidate(
      instrument: usdInstrument,
      candidate: MarketInstrumentCandidate(
        symbol: 'AAPL',
        name: 'Apple Inc.',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.usd,
        exchange: 'NASDAQ',
        provider: MarketProvider.twelveData,
        providerSymbol: 'AAPL',
      ),
      now: const UtcInstant.fromEpochMicroseconds(2000),
    );

    expect(linked.providerName, 'twelveData');
    expect(linked.providerSymbol, 'AAPL');
    expect(linked.customInstrument, isFalse);
    expect(
      (await repository.findInstrument(linked.id))?.providerName,
      'twelveData',
    );
  });

  test(
    'sale beyond remaining lots fails without ledger or disposal writes',
    () async {
      await service.buy(
        instrument: instrument,
        cashPocket: cash,
        quantity: Decimal.fromInt(2),
        unitPrice: Decimal.fromInt(10),
        date: LocalDate(2026, 1, 10),
        now: now,
      );
      await expectLater(
        service.sell(
          instrument: instrument,
          cashPocket: cash,
          quantity: Decimal.fromInt(3),
          unitPrice: Decimal.fromInt(12),
          date: LocalDate(2026, 2, 1),
          now: now,
        ),
        throwsA(isA<InsufficientLotQuantity>()),
      );
      expect(
        (await database
                .customSelect(
                  "SELECT COUNT(*) total FROM transactions WHERE transaction_type='investment_sell'",
                )
                .getSingle())
            .read<int>('total'),
        0,
      );
      expect(
        (await database
                .customSelect(
                  'SELECT COUNT(*) total FROM investment_lot_disposals',
                )
                .getSingle())
            .read<int>('total'),
        0,
      );
    },
  );

  test(
    'instrument revisions are optimistic and metadata round-trips',
    () async {
      final loaded = await repository.findInstrument(instrument.id);
      expect(loaded!.symbol, 'ACME3');
      await repository.saveInstrument(
        loaded.revise(
          name: 'Acme SA',
          at: const UtcInstant.fromEpochMicroseconds(2000),
        ),
      );
      await expectLater(
        repository.saveInstrument(
          loaded.revise(
            name: 'Stale',
            at: const UtcInstant.fromEpochMicroseconds(3000),
          ),
        ),
        throwsA(isA<InstrumentRevisionConflict>()),
      );
      expect((await repository.findInstrument(instrument.id))!.name, 'Acme SA');
    },
  );

  test(
    'deposits, withdrawals, and fees reconcile through the shared ledger',
    () async {
      await service.transferCash(
        vaultId: vaultId,
        regularCash: regularCash,
        investmentCash: cash,
        amountMinor: 10000,
        date: LocalDate(2026, 1, 1),
        now: now,
        deposit: true,
      );
      await service.transferCash(
        vaultId: vaultId,
        regularCash: regularCash,
        investmentCash: cash,
        amountMinor: 2500,
        date: LocalDate(2026, 1, 2),
        now: now,
        deposit: false,
      );
      await service.fee(
        vaultId: vaultId,
        cashPocket: cash,
        categoryId: expenseCategoryId,
        amountMinor: 300,
        date: LocalDate(2026, 1, 3),
        now: now,
      );
      Future<int> balance(LedgerPocket pocket) async =>
          (await database
                  .customSelect(
                    'SELECT COALESCE(SUM(amount_minor),0) total FROM account_movements WHERE account_pocket_id=?',
                    variables: [Variable<String>(pocket.id.value)],
                  )
                  .getSingle())
              .read<int>('total');
      expect(await balance(regularCash), -7500);
      expect(await balance(cash), 7200);
      expect(
        (await database
                .customSelect(
                  "SELECT COUNT(*) total FROM transactions WHERE transaction_type='transfer'",
                )
                .getSingle())
            .read<int>('total'),
        2,
      );
      expect(
        (await database
                .customSelect('SELECT amount_minor FROM transaction_splits')
                .getSingle())
            .read<int>('amount_minor'),
        300,
      );
    },
  );

  test('foreign-currency deposit and buy use matching USD pockets', () async {
    await service.transferCash(
      vaultId: vaultId,
      regularCash: usdRegularCash,
      investmentCash: usdCash,
      amountMinor: 10000,
      date: LocalDate(2026, 4, 1),
      now: now,
      deposit: true,
    );
    await service.buy(
      instrument: usdInstrument,
      cashPocket: usdCash,
      quantity: Decimal.fromInt(2),
      unitPrice: Decimal.fromInt(10),
      date: LocalDate(2026, 4, 2),
      now: now,
    );

    Future<int> balance(LedgerPocket pocket) async =>
        (await database
                .customSelect(
                  'SELECT COALESCE(SUM(amount_minor),0) total FROM account_movements WHERE account_pocket_id=?',
                  variables: [Variable<String>(pocket.id.value)],
                )
                .getSingle())
            .read<int>('total');
    expect(await balance(usdRegularCash), -10000);
    expect(await balance(usdCash), 8000);
    expect(
      (await repository.lotPositions(
        usdInstrument.id,
        asOf: LocalDate(2026, 4, 30),
      )).single.remainingQuantity,
      Decimal.fromInt(2),
    );
  });

  test('currency mismatch is rejected before ledger writes', () async {
    await expectLater(
      service.buy(
        instrument: instrument,
        cashPocket: usdCash,
        quantity: Decimal.one,
        unitPrice: Decimal.fromInt(10),
        date: LocalDate(2026, 5, 1),
        now: now,
      ),
      throwsA(
        isA<InvestmentCurrencyMismatch>()
            .having((error) => error.expected, 'expected', CurrencyCode.brl)
            .having((error) => error.actual, 'actual', CurrencyCode.usd),
      ),
    );
    await expectLater(
      service.transferCash(
        vaultId: vaultId,
        regularCash: regularCash,
        investmentCash: usdCash,
        amountMinor: 1000,
        date: LocalDate(2026, 5, 1),
        now: now,
        deposit: true,
      ),
      throwsA(isA<InvestmentCurrencyMismatch>()),
    );
    expect(
      (await database
              .customSelect('SELECT COUNT(*) total FROM transactions')
              .getSingle())
          .read<int>('total'),
      0,
    );
  });

  test('unused asset is soft-deleted with a revision tombstone', () async {
    await service.deleteInstrument(
      usdInstrument,
      const UtcInstant.fromEpochMicroseconds(2000),
    );

    expect(await repository.findInstrument(usdInstrument.id), isNull);
    expect(
      (await repository.listInstruments(vaultId)).map((item) => item.id),
      isNot(contains(usdInstrument.id)),
    );
    final row = await database
        .customSelect(
          'SELECT revision,deleted_at FROM investment_instruments WHERE id=?',
          variables: [Variable<String>(usdInstrument.id.value)],
        )
        .getSingle();
    expect(row.read<int>('revision'), 2);
    expect(row.read<int>('deleted_at'), 2000);
  });

  test('unused asset deletion enqueues a sync delete tombstone', () async {
    await database.customStatement(
      'INSERT INTO vault_cloud_bindings '
      '(vault_id,auth_user_id,sync_enabled,linked_at) VALUES (?,?,1,1)',
      [vaultId.value, 'owner'],
    );
    final metadata = DriftSyncMetadataStore(database);
    final syncRepository = DriftInvestmentRepository(
      database: database,
      ledger: ledger,
      syncRecorder: DriftSyncMutationRecorder(
        database: database,
        aggregates: DriftSyncAggregateStore(
          database: database,
          metadata: metadata,
        ),
        metadata: metadata,
      ),
    );
    await InvestmentService(
      repository: syncRepository,
      reporting: DriftDashboardRepository(database),
    ).deleteInstrument(
      usdInstrument,
      const UtcInstant.fromEpochMicroseconds(2000),
    );

    final pending = await metadata.readyMutations(
      vaultId: vaultId.value,
      nowMicros: 9999999999999999,
    );
    expect(pending, hasLength(1));
    expect(pending.single.entityType, SyncEntityType.investmentInstrument);
    expect(pending.single.operation, SyncOperation.delete);
    expect(pending.single.newRevision, 2);
    expect(pending.single.recordId, usdInstrument.id.value);
  });

  test('used zero-position asset remains with all linked history', () async {
    await service.buy(
      instrument: instrument,
      cashPocket: cash,
      quantity: Decimal.fromInt(2),
      unitPrice: Decimal.fromInt(10),
      date: LocalDate(2026, 6, 1),
      now: now,
    );
    await service.sell(
      instrument: instrument,
      cashPocket: cash,
      quantity: Decimal.fromInt(2),
      unitPrice: Decimal.fromInt(12),
      date: LocalDate(2026, 6, 2),
      now: now,
    );
    final positions = await repository.lotPositions(
      instrument.id,
      asOf: LocalDate(2026, 6, 30),
    );
    expect(positions.single.remainingQuantity, Decimal.zero);

    await expectLater(
      service.deleteInstrument(
        instrument,
        const UtcInstant.fromEpochMicroseconds(2000),
      ),
      throwsA(isA<InvestmentAssetInUse>()),
    );

    expect(await repository.findInstrument(instrument.id), isNotNull);
    Future<int> count(String table) async =>
        (await database
                .customSelect('SELECT COUNT(*) total FROM $table')
                .getSingle())
            .read<int>('total');
    expect(await count('investment_events'), 2);
    expect(await count('investment_lots'), 1);
    expect(await count('investment_lot_disposals'), 1);
  });

  test('price history alone allows deletion and remains preserved', () async {
    await database.customStatement(
      'INSERT INTO manual_market_prices '
      '(id,vault_id,instrument_id,price_date,price,currency_code,revision,created_at,updated_at) '
      "VALUES (?,?,?,'2026-07-01','25','USD',1,1,1)",
      [EntityId.generate().value, vaultId.value, usdInstrument.id.value],
    );
    await database.customStatement(
      'INSERT INTO market_price_cache '
      '(instrument_id,price_timestamp,price,currency_code,provider,fetched_at) '
      "VALUES (?,1,'26','USD','twelve_data',1)",
      [usdInstrument.id.value],
    );

    await service.deleteInstrument(
      usdInstrument,
      const UtcInstant.fromEpochMicroseconds(2000),
    );
    expect(await repository.findInstrument(usdInstrument.id), isNull);
    expect(
      (await database
              .customSelect(
                'SELECT COUNT(*) total FROM manual_market_prices WHERE instrument_id=?',
                variables: [Variable<String>(usdInstrument.id.value)],
              )
              .getSingle())
          .read<int>('total'),
      1,
    );
    expect(
      (await database
              .customSelect(
                'SELECT COUNT(*) total FROM market_price_cache WHERE instrument_id=?',
                variables: [Variable<String>(usdInstrument.id.value)],
              )
              .getSingle())
          .read<int>('total'),
      1,
    );
  });

  test('linked attachment still blocks asset deletion', () async {
    final attachment = EntityId.generate();
    await database.customStatement(
      'INSERT INTO attachments '
      '(id,vault_id,byte_size,sha256,revision,created_at,updated_at) '
      "VALUES (?,?,1,'hash',1,1,1)",
      [attachment.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO attachment_links (attachment_id,entity_type,entity_id) '
      "VALUES (?,'investment_instrument',?)",
      [attachment.value, usdInstrument.id.value],
    );

    await expectLater(
      service.deleteInstrument(
        usdInstrument,
        const UtcInstant.fromEpochMicroseconds(2000),
      ),
      throwsA(isA<InvestmentAssetInUse>()),
    );
    expect(await repository.findInstrument(usdInstrument.id), isNotNull);
  });
}
