import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:equis/application/ports/economic_series_ports.dart';
import 'package:equis/application/services/economic_series_service.dart';
import 'package:equis/application/services/investment_service.dart';
import 'package:equis/application/services/wealth_service.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/investments/fixed_income_contract.dart';
import 'package:equis/domain/investments/fixed_income_valuation.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide
        FixedIncomeContract,
        FixedIncomeManualValue,
        InvestmentInstrument,
        InvestmentLot;
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_economic_series_cache.dart';
import 'package:equis/infrastructure/repositories/drift_investment_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_wealth_repository.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftInvestmentRepository investments;
  late DriftEconomicSeriesCache seriesCache;
  late InvestmentService investmentService;
  late EntityId vaultId;
  late LedgerPocket brokerCash;
  late UtcInstant calculatedAt;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    final ledger = DriftLedgerRepository(database);
    investments = DriftInvestmentRepository(database: database, ledger: ledger);
    seriesCache = DriftEconomicSeriesCache(database);
    final reporting = DriftDashboardRepository(database);
    vaultId = EntityId.generate();
    calculatedAt = const UtcInstant.fromEpochMicroseconds(10000);

    final accountId = EntityId.generate();
    final pocketId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO vaults '
      '(id,name,base_currency_code,timezone,created_at,updated_at) '
      "VALUES (?,?,'BRL','UTC',1,1)",
      [vaultId.value, 'Valuation test'],
    );
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) "
      "VALUES ('BRL','brl','R\$',2)",
    );
    await database.customStatement(
      'INSERT INTO accounts '
      '(id,vault_id,name,account_type,nature,created_at,updated_at) '
      "VALUES (?,?,'Broker','investment','asset',1,1)",
      [accountId.value, vaultId.value],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id,account_id,currency_code,is_default) '
      "VALUES (?,?,'BRL',1)",
      [pocketId.value, accountId.value],
    );
    brokerCash = LedgerPocket(
      id: pocketId,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    );

    investmentService = InvestmentService(
      repository: investments,
      reporting: reporting,
      unitOfWork: DriftLocalUnitOfWork(database),
      economicSeries: EconomicSeriesService(
        cache: seriesCache,
        provider: const _EmptySeriesProvider(),
      ),
      businessCalendar: const _WeekdayCalendar(),
      clock: () => calculatedAt,
    );
  });

  tearDown(() => database.close());

  test(
    'report and net worth value each fixed-income lot by its own rate',
    () async {
      final fixed = await _createInstrument(
        investmentService,
        vaultId,
        now: calculatedAt,
        name: 'Different lot rates',
        assetClass: InvestmentAssetClass.fixedIncome,
      );
      final start = LocalDate(2025, 1, 1);
      Future<FixedIncomeTerms> terms(String rate) async => FixedIncomeTerms(
        principal: Decimal.fromInt(1000),
        currency: CurrencyCode.brl,
        productName: 'CDB',
        accrualStart: start,
        mode: FixedIncomeRemunerationMode.fixedAnnual,
        updateRule: FixedIncomeUpdateRule.annualCompound,
        annualRate: Decimal.parse(rate),
        dayCountBasis: 365,
      );

      await investmentService.importOpeningPosition(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.one,
        unitPrice: Decimal.fromInt(1000),
        date: start,
        now: calculatedAt,
        contractTerms: await terms('0.12'),
      );
      await investmentService.importOpeningPosition(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.one,
        unitPrice: Decimal.fromInt(1000),
        date: start,
        now: calculatedAt,
        contractTerms: await terms('0.20'),
      );

      final report = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 1),
      );
      final holding = report.holdings.single;
      expect(holding.marketValueMinor, 232000);
      expect(
        holding.lotValuations.map((value) => value.amountMinor).toList()
          ..sort(),
        [112000, 120000],
      );
      expect(holding.hasIncompleteValuations, isFalse);
      expect(report.hasIncompleteValuations, isFalse);

      final netWorth = await _wealthService(database, investmentService).report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 1),
        historyMonths: 1,
      );
      expect(netWorth.current.assetsMinor, 232000);
      expect(netWorth.current.hasIncompleteInvestments, isFalse);
    },
  );

  test(
    'manual valuation goes stale after a sale and can be reaffirmed',
    () async {
      final fixed = await _createInstrument(
        investmentService,
        vaultId,
        now: calculatedAt,
        name: 'Manual contract',
        assetClass: InvestmentAssetClass.fixedIncome,
      );
      final acquiredOn = LocalDate(2026, 1, 10);
      final acquisition = await investmentService.importOpeningPosition(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.fromInt(10),
        unitPrice: Decimal.fromInt(100),
        date: acquiredOn,
        now: calculatedAt,
        contractTerms: FixedIncomeTerms(
          principal: Decimal.fromInt(1000),
          currency: CurrencyCode.brl,
          productName: 'Manual CDB',
          accrualStart: acquiredOn,
          mode: FixedIncomeRemunerationMode.manualOnly,
          updateRule: FixedIncomeUpdateRule.manualValue,
        ),
      );
      final lotId = (await investments.lotPositions(
        fixed.id,
        asOf: LocalDate(2026, 2, 1),
      )).single.lot.id;
      final revision = await investmentService.recordManualValue(
        vaultId: vaultId,
        lotId: lotId,
        valueDate: LocalDate(2026, 1, 20),
        amountMinor: 102000,
        currency: CurrencyCode.brl,
        expectedTransactionRevision: acquisition.revision,
        now: const UtcInstant.fromEpochMicroseconds(11000),
      );

      await investmentService.sell(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.fromInt(2),
        unitPrice: Decimal.fromInt(110),
        date: LocalDate(2026, 1, 25),
        now: const UtcInstant.fromEpochMicroseconds(12000),
      );
      final staleReport = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 2, 1),
      );
      final staleHolding = staleReport.holdings.single;
      expect(staleHolding.marketValueMinor, isNull);
      expect(staleHolding.hasIncompleteValuations, isTrue);
      expect(
        staleHolding.lotValuations.single.state,
        ValuationState.manualRequired,
      );
      expect(staleReport.marketValueMinor, 0);
      expect(staleReport.incompleteLotIds, [lotId]);

      await investmentService.recordManualValue(
        vaultId: vaultId,
        lotId: lotId,
        valueDate: LocalDate(2026, 2, 1),
        amountMinor: 82000,
        currency: CurrencyCode.brl,
        expectedTransactionRevision: revision,
        now: const UtcInstant.fromEpochMicroseconds(13000),
        notes: 'Reconfirmed after the partial sale',
      );
      final reaffirmed = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 2, 1),
      );
      final currentHolding = reaffirmed.holdings.single;
      expect(currentHolding.quantity, Decimal.fromInt(8));
      expect(currentHolding.marketValueMinor, 82000);
      expect(currentHolding.hasIncompleteValuations, isFalse);
      expect(currentHolding.lotValuations.single.source, 'user_manual');
      expect(reaffirmed.hasIncompleteValuations, isFalse);
    },
  );

  test(
    'manual values remain valid with an empty or legacy fingerprint',
    () async {
      final fixed = await _createInstrument(
        investmentService,
        vaultId,
        now: calculatedAt,
        name: 'Legacy manual contract',
        assetClass: InvestmentAssetClass.fixedIncome,
      );
      final acquiredOn = LocalDate(2026, 1, 10);
      final acquisition = await investmentService.importOpeningPosition(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.fromInt(10),
        unitPrice: Decimal.fromInt(100),
        date: acquiredOn,
        now: calculatedAt,
        contractTerms: FixedIncomeTerms(
          principal: Decimal.fromInt(1000),
          currency: CurrencyCode.brl,
          productName: 'Manual CDB',
          accrualStart: acquiredOn,
          mode: FixedIncomeRemunerationMode.manualOnly,
          updateRule: FixedIncomeUpdateRule.manualValue,
        ),
      );
      final lotId = (await investments.lotPositions(
        fixed.id,
        asOf: LocalDate(2026, 2, 1),
      )).single.lot.id;
      final emptyFingerprint = await investments.disposalFingerprint(
        lotId,
        asOf: LocalDate(2026, 1, 20),
      );
      expect(emptyFingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        await database
            .customSelect('SELECT * FROM investment_lot_disposals')
            .get(),
        isEmpty,
      );
      final revision = await investmentService.recordManualValue(
        vaultId: vaultId,
        lotId: lotId,
        valueDate: LocalDate(2026, 1, 20),
        amountMinor: 102000,
        currency: CurrencyCode.brl,
        expectedTransactionRevision: acquisition.revision,
        now: const UtcInstant.fromEpochMicroseconds(11000),
      );
      final manual = (await investments.manualValues(vaultId, lotId)).single;
      expect(manual.disposalFingerprint, emptyFingerprint);

      final canonicalReport = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 2, 1),
      );
      expect(canonicalReport.holdings.single.marketValueMinor, 102000);
      expect(
        canonicalReport.holdings.single.lotValuations.single.state,
        ValuationState.current,
      );

      // Rows written before disposal fingerprints were introduced have null.
      // They remain usable while the current disposal set is empty.
      await database.customStatement(
        'UPDATE fixed_income_manual_values SET disposal_fingerprint=NULL '
        'WHERE id=?',
        [manual.id.value],
      );
      final legacyReport = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 2, 1),
      );
      expect(legacyReport.holdings.single.marketValueMinor, 102000);
      expect(
        legacyReport.holdings.single.lotValuations.single.state,
        ValuationState.current,
      );
      expect(revision, acquisition.revision + 1);
    },
  );

  test(
    'disposal-bound manual value is invalidated by cancellation or redating',
    () async {
      final fixed = await _createInstrument(
        investmentService,
        vaultId,
        now: calculatedAt,
        name: 'Disposal-bound manual contract',
        assetClass: InvestmentAssetClass.fixedIncome,
      );
      final acquiredOn = LocalDate(2026, 1, 10);
      final acquisition = await investmentService.importOpeningPosition(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.fromInt(10),
        unitPrice: Decimal.fromInt(100),
        date: acquiredOn,
        now: calculatedAt,
        contractTerms: FixedIncomeTerms(
          principal: Decimal.fromInt(1000),
          currency: CurrencyCode.brl,
          productName: 'Manual CDB',
          accrualStart: acquiredOn,
          mode: FixedIncomeRemunerationMode.manualOnly,
          updateRule: FixedIncomeUpdateRule.manualValue,
        ),
      );
      final lotId = (await investments.lotPositions(
        fixed.id,
        asOf: LocalDate(2026, 2, 1),
      )).single.lot.id;
      final sale = await investmentService.sell(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.fromInt(8),
        unitPrice: Decimal.fromInt(110),
        date: LocalDate(2026, 1, 20),
        now: const UtcInstant.fromEpochMicroseconds(12000),
      );
      final saleFingerprint = await investments.disposalFingerprint(
        lotId,
        asOf: LocalDate(2026, 1, 25),
      );
      await investmentService.recordManualValue(
        vaultId: vaultId,
        lotId: lotId,
        valueDate: LocalDate(2026, 1, 25),
        amountMinor: 82000,
        currency: CurrencyCode.brl,
        expectedTransactionRevision: acquisition.revision,
        now: const UtcInstant.fromEpochMicroseconds(13000),
      );
      final manual = (await investments.manualValues(vaultId, lotId)).single;
      expect(manual.disposalFingerprint, saleFingerprint);
      expect(manual.disposalFingerprint, isNotEmpty);

      Future<void> expectManualUnavailable() async {
        final report = await investmentService.report(
          vaultId: vaultId,
          currency: CurrencyCode.brl,
          asOf: LocalDate(2026, 2, 1),
        );
        final holding = report.holdings.single;
        expect(holding.quantity, Decimal.fromInt(10));
        expect(holding.marketValueMinor, isNull);
        expect(holding.hasIncompleteValuations, isTrue);
        expect(
          holding.lotValuations.single.state,
          ValuationState.manualRequired,
        );
      }

      // A remote cancellation can leave the lot undisposed even though the
      // stored manual value was recorded against the eight-unit sale.
      await database.customStatement(
        "UPDATE transactions SET status='cancelled' WHERE id=?",
        [sale.id.value],
      );
      expect(
        await investments.disposalFingerprint(
          lotId,
          asOf: LocalDate(2026, 2, 1),
        ),
        isNot(saleFingerprint),
      );
      await expectManualUnavailable();

      // Reapplying the sale makes its fingerprint match again. Moving it after
      // the manual date must invalidate the value once more.
      await database.customStatement(
        "UPDATE transactions SET status='cleared' WHERE id=?",
        [sale.id.value],
      );
      final restoredSaleReport = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 2, 1),
      );
      expect(restoredSaleReport.holdings.single.marketValueMinor, 82000);
      await database.customStatement(
        'UPDATE transactions SET financial_date=? WHERE id=?',
        ['2026-03-01', sale.id.value],
      );
      expect(
        await investments.disposalFingerprint(
          lotId,
          asOf: LocalDate(2026, 2, 1),
        ),
        isNot(saleFingerprint),
      );
      await expectManualUnavailable();
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'missing CDI observation marks subtotal and net worth incomplete',
    () async {
      final fixed = await _createInstrument(
        investmentService,
        vaultId,
        now: calculatedAt,
        name: 'CDI lot',
        assetClass: InvestmentAssetClass.fixedIncome,
      );
      final stock = await _createInstrument(
        investmentService,
        vaultId,
        now: calculatedAt,
        name: 'Legacy stock',
        assetClass: InvestmentAssetClass.stock,
      );
      final accrualStart = LocalDate(2026, 1, 9);
      await investmentService.importOpeningPosition(
        instrument: fixed,
        cashPocket: brokerCash,
        quantity: Decimal.one,
        unitPrice: Decimal.fromInt(1000),
        date: accrualStart,
        now: calculatedAt,
        contractTerms: FixedIncomeTerms(
          principal: Decimal.fromInt(1000),
          currency: CurrencyCode.brl,
          productName: 'CDI CDB',
          accrualStart: accrualStart,
          mode: FixedIncomeRemunerationMode.dailyIndexPercent,
          updateRule: FixedIncomeUpdateRule.dailyObservation,
          indexCode: EconomicSeriesCode.cdiDaily,
          indexMultiplier: Decimal.one,
          calendarVersion: 'weekday-test-v1',
        ),
      );
      await investmentService.importOpeningPosition(
        instrument: stock,
        cashPocket: brokerCash,
        quantity: Decimal.fromInt(3),
        unitPrice: Decimal.fromInt(10),
        date: LocalDate(2026, 1, 1),
        now: calculatedAt,
      );
      await seriesCache.saveAll([
        EconomicSeriesObservation(
          code: EconomicSeriesCode.cdiDaily,
          referenceStart: LocalDate(2026, 1, 12),
          referenceEnd: LocalDate(2026, 1, 12),
          value: '0.1',
          fetchedAt: calculatedAt,
        ),
      ]);
      await database.customStatement(
        'INSERT INTO manual_market_prices '
        '(id,vault_id,instrument_id,price_date,price,currency_code,revision,created_at,updated_at) '
        "VALUES (?,?,?,'2026-01-13','20','BRL',1,1,1)",
        [EntityId.generate().value, vaultId.value, stock.id.value],
      );

      final report = await investmentService.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 13),
      );
      final fixedHolding = report.holdings.singleWhere(
        (holding) => holding.instrument.id == fixed.id,
      );
      final stockHolding = report.holdings.singleWhere(
        (holding) => holding.instrument.id == stock.id,
      );
      expect(fixedHolding.marketValueMinor, isNull);
      expect(fixedHolding.hasIncompleteValuations, isTrue);
      expect(fixedHolding.lotValuations.single.missingPeriods, hasLength(1));
      expect(
        fixedHolding.lotValuations.single.missingPeriods.single.reason,
        MissingPeriodReason.observation,
      );
      expect(stockHolding.marketValueMinor, 6000);
      expect(stockHolding.lotValuations.single.origin, ValuationOrigin.market);
      expect(report.marketValueMinor, 6000);
      expect(report.hasIncompleteValuations, isTrue);

      final netWorth = await _wealthService(database, investmentService).report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 13),
        historyMonths: 1,
      );
      expect(netWorth.current.assetsMinor, 6000);
      expect(netWorth.current.netWorthMinor, 6000);
      expect(netWorth.current.hasIncompleteInvestments, isTrue);
    },
  );

  test('legacy stock continues to use its latest manual market price', () async {
    final stock = await _createInstrument(
      investmentService,
      vaultId,
      now: calculatedAt,
      name: 'Legacy stock pricing',
      assetClass: InvestmentAssetClass.stock,
    );
    await investmentService.importOpeningPosition(
      instrument: stock,
      cashPocket: brokerCash,
      quantity: Decimal.fromInt(4),
      unitPrice: Decimal.fromInt(25),
      date: LocalDate(2026, 1, 1),
      now: calculatedAt,
    );
    await database.customStatement(
      'INSERT INTO manual_market_prices '
      '(id,vault_id,instrument_id,price_date,price,currency_code,revision,created_at,updated_at) '
      "VALUES (?,?,?,'2026-01-30','30','BRL',1,1,1)",
      [EntityId.generate().value, vaultId.value, stock.id.value],
    );

    final report = await investmentService.report(
      vaultId: vaultId,
      currency: CurrencyCode.brl,
      asOf: LocalDate(2026, 1, 31),
    );
    final holding = report.holdings.single;
    expect(holding.marketValueMinor, 12000);
    expect(holding.unrealizedMinor, 2000);
    expect(holding.lotValuations.single.origin, ValuationOrigin.market);
    expect(holding.lotValuations.single.source, 'user_market_price');
    expect(report.hasIncompleteValuations, isFalse);

    final netWorth = await _wealthService(database, investmentService).report(
      vaultId: vaultId,
      currency: CurrencyCode.brl,
      asOf: LocalDate(2026, 1, 31),
      historyMonths: 1,
    );
    expect(netWorth.current.assetsMinor, 12000);
    expect(netWorth.current.hasIncompleteInvestments, isFalse);
  });

  test('fractional market lots retain instrument-level price rounding', () async {
    final stock = await _createInstrument(
      investmentService,
      vaultId,
      now: calculatedAt,
      name: 'Fractional legacy position',
      assetClass: InvestmentAssetClass.stock,
    );
    for (var day = 1; day <= 2; day++) {
      await investmentService.importOpeningPosition(
        instrument: stock,
        cashPocket: brokerCash,
        quantity: Decimal.parse('0.5'),
        unitPrice: Decimal.parse('0.01'),
        date: LocalDate(2026, 1, day),
        now: calculatedAt,
      );
    }
    await database.customStatement(
      'INSERT INTO manual_market_prices '
      '(id,vault_id,instrument_id,price_date,price,currency_code,revision,created_at,updated_at) '
      "VALUES (?,?,?,'2026-01-03','0.01','BRL',1,1,1)",
      [EntityId.generate().value, vaultId.value, stock.id.value],
    );
    final report = await investmentService.report(
      vaultId: vaultId,
      currency: CurrencyCode.brl,
      asOf: LocalDate(2026, 1, 3),
    );
    final holding = report.holdings.single;
    expect(holding.quantity, Decimal.one);
    expect(holding.marketValueMinor, 1);
    expect(
      holding.lotValuations.fold(0, (sum, value) => sum + value.amountMinor!),
      1,
    );
    expect(report.marketValueMinor, 1);
  });

  test('legacy market FX converts the aggregate before rounding', () async {
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) "
      "VALUES ('USD','usd','\$',2)",
    );
    await database.customStatement(
      'INSERT INTO fx_rate_cache '
      '(base_currency,quote_currency,rate_date,rate,provider,fetched_at) '
      "VALUES ('USD','BRL','2026-01-03','1.5','fixture',1)",
    );
    final stock = await _createInstrument(
      investmentService,
      vaultId,
      now: calculatedAt,
      name: 'Two USD priced lots',
      assetClass: InvestmentAssetClass.stock,
    );
    for (var day = 1; day <= 2; day++) {
      await investmentService.importOpeningPosition(
        instrument: stock,
        cashPocket: brokerCash,
        quantity: Decimal.one,
        unitPrice: Decimal.fromInt(1),
        date: LocalDate(2026, 1, day),
        now: calculatedAt,
      );
    }
    await database.customStatement(
      'INSERT INTO manual_market_prices '
      '(id,vault_id,instrument_id,price_date,price,currency_code,revision,created_at,updated_at) '
      "VALUES (?,?,?,'2026-01-03','0.01','USD',1,1,1)",
      [EntityId.generate().value, vaultId.value, stock.id.value],
    );
    final report = await investmentService.report(
      vaultId: vaultId,
      currency: CurrencyCode.brl,
      asOf: LocalDate(2026, 1, 3),
    );
    expect(report.holdings.single.marketValueMinor, 3);
    expect(report.marketValueMinor, 3);
    expect(
      report.holdings.single.lotValuations
          .map((value) => value.amountMinor)
          .toList(),
      [1, 1],
    );
  });
}

Future<InvestmentInstrument> _createInstrument(
  InvestmentService service,
  EntityId vaultId, {
  required UtcInstant now,
  required String name,
  required InvestmentAssetClass assetClass,
}) => service.createInstrument(
  vaultId: vaultId,
  name: name,
  assetClass: assetClass,
  currency: CurrencyCode.brl,
  now: now,
);

WealthService _wealthService(
  EquisDatabase database,
  InvestmentService investments,
) => WealthService(
  repository: DriftWealthRepository(database),
  reporting: DriftDashboardRepository(database),
  investments: investments,
);

final class _EmptySeriesProvider implements EconomicSeriesProvider {
  const _EmptySeriesProvider();

  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async => const [];
}

final class _WeekdayCalendar implements BusinessCalendar {
  const _WeekdayCalendar();

  @override
  String get version => 'weekday-test-v1';

  @override
  bool? isBusinessDay(LocalDate date) {
    final weekday = date.toUtcDate().weekday;
    return weekday != DateTime.saturday && weekday != DateTime.sunday;
  }
}
