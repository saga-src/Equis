import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:equis/application/ports/investment_repository.dart';
import 'package:equis/application/services/investment_service.dart';
import 'package:equis/application/services/wealth_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide InvestmentInstrument, InvestmentLot;
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_investment_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_wealth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftInvestmentRepository repository;
  late InvestmentService service;
  late EntityId vaultId;
  late LedgerPocket cash;
  late LedgerPocket regularCash;
  late EntityId categoryId;
  late EntityId expenseCategoryId;
  late InvestmentInstrument instrument;
  const now = UtcInstant.fromEpochMicroseconds(1000);

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    final ledger = DriftLedgerRepository(database);
    repository = DriftInvestmentRepository(database: database, ledger: ledger);
    service = InvestmentService(
      repository: repository,
      reporting: DriftDashboardRepository(database),
    );
    vaultId = EntityId.generate();
    final account = EntityId.generate();
    final pocket = EntityId.generate();
    final regularAccount = EntityId.generate();
    final regularPocket = EntityId.generate();
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
    instrument = await service.createInstrument(
      vaultId: vaultId,
      name: 'Acme',
      symbol: 'ACME3',
      assetClass: InvestmentAssetClass.stock,
      currency: CurrencyCode.brl,
      exchange: 'B3',
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
      final holding = report.holdings.single;
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
}
