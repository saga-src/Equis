import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:equis/application/ports/economic_series_ports.dart';
import 'package:equis/application/services/economic_series_service.dart';
import 'package:equis/application/services/investment_service.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/investments/fixed_income_contract.dart';
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
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_economic_series_cache.dart';
import 'package:equis/infrastructure/repositories/drift_investment_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late InvestmentService service;
  late EntityId vaultId;
  late LedgerPocket pocket;
  late _Provider provider;
  final now = UtcInstant.fromDateTime(DateTime.utc(2026, 9, 30));
  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    vaultId = EntityId.generate();
    final accountId = EntityId.generate();
    final pocketId = EntityId.generate();
    await database.customStatement(
      "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('BRL','brl','R\$',2)",
    );
    await database.customStatement(
      "INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) VALUES (?,'Backfill','BRL','UTC',1,1)",
      [vaultId.value],
    );
    await database.customStatement(
      "INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) VALUES (?,?,'Broker','investment','asset',1,1)",
      [accountId.value, vaultId.value],
    );
    await database.customStatement(
      "INSERT INTO account_pockets (id,account_id,currency_code,is_default) VALUES (?,?,'BRL',1)",
      [pocketId.value, accountId.value],
    );
    pocket = LedgerPocket(
      id: pocketId,
      currency: CurrencyCode.brl,
      nature: AccountNature.asset,
    );
    final ledger = DriftLedgerRepository(database);
    provider = _Provider();
    service = InvestmentService(
      repository: DriftInvestmentRepository(database: database, ledger: ledger),
      reporting: DriftDashboardRepository(database),
      unitOfWork: DriftLocalUnitOfWork(database),
      economicSeries: EconomicSeriesService(
        cache: DriftEconomicSeriesCache(database),
        provider: provider,
        remoteReadsEnabled: true,
        clock: () => now,
      ),
      clock: () => now,
    );
  });
  tearDown(() => database.close());

  Future<InvestmentInstrument> position(FixedIncomeTerms terms) async {
    final instrument = await service.createInstrument(
      vaultId: vaultId,
      name: terms.productName,
      assetClass: InvestmentAssetClass.fixedIncome,
      currency: CurrencyCode.brl,
      now: now,
    );
    await service.importOpeningPosition(
      instrument: instrument,
      cashPocket: pocket,
      quantity: Decimal.one,
      unitPrice: Decimal.fromInt(1000),
      date: terms.accrualStart,
      now: now,
      contractTerms: terms,
    );
    return instrument;
  }

  FixedIncomeTerms daily(LocalDate start, LocalDate maturity) =>
      FixedIncomeTerms(
        principal: Decimal.fromInt(1000),
        currency: CurrencyCode.brl,
        productName: 'CDI',
        accrualStart: start,
        maturityOn: maturity,
        mode: FixedIncomeRemunerationMode.dailyIndexPercent,
        updateRule: FixedIncomeUpdateRule.dailyObservation,
        indexCode: EconomicSeriesCode.cdiDaily,
        indexMultiplier: Decimal.one,
      );

  test(
    'position history exceeds one year; monthly lag and maturity share valuation range',
    () async {
      await position(daily(LocalDate(2023, 1, 1), LocalDate(2025, 6, 1)));
      final monthlyStart = LocalDate(2025, 5, 15);
      await position(
        FixedIncomeTerms(
          principal: Decimal.fromInt(1000),
          currency: CurrencyCode.brl,
          productName: 'IPCA',
          accrualStart: monthlyStart,
          maturityOn: LocalDate(2025, 8, 15),
          mode: FixedIncomeRemunerationMode.monthlyIndex,
          updateRule: FixedIncomeUpdateRule.monthlyAnniversary,
          indexCode: EconomicSeriesCode.ipcaMonthly,
          publicationLagMonths: 2,
          anniversaryDay: 15,
        ),
      );
      final asOf = LocalDate(2026, 9, 30);
      await service.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: asOf,
      );
      expect(provider.calls, isEmpty);
      await service.refreshEconomicSeries(vaultId: vaultId, asOf: asOf);
      final dailyCalls = provider.calls
          .where((call) => call.$1 == EconomicSeriesCode.cdiDaily)
          .toList();
      expect(dailyCalls, hasLength(3));
      expect(dailyCalls.first.$2, LocalDate(2023, 1, 1));
      expect(dailyCalls.last.$3, LocalDate(2025, 5, 31));
      final monthly = provider.calls.singleWhere(
        (call) => call.$1 == EconomicSeriesCode.ipcaMonthly,
      );
      expect(monthly.$2, monthlyStart.addDays(-124));
      expect(monthly.$3, LocalDate(2025, 8, 15));
      final count = provider.calls.length;
      await service.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: asOf,
      );
      expect(provider.calls, hasLength(count));
    },
  );

  test('fully disposed lots produce no refresh demand', () async {
    final instrument = await position(
      daily(LocalDate(2023, 1, 1), LocalDate(2027, 1, 1)),
    );
    await service.sell(
      instrument: instrument,
      cashPocket: pocket,
      quantity: Decimal.one,
      unitPrice: Decimal.fromInt(1100),
      feesMinor: 0,
      taxesMinor: 0,
      date: LocalDate(2024, 1, 1),
      now: now,
    );
    await service.refreshEconomicSeries(
      vaultId: vaultId,
      asOf: LocalDate(2026, 9, 30),
    );
    expect(provider.calls, isEmpty);
    await service.refreshEconomicSeries(
      vaultId: vaultId,
      asOf: LocalDate(2023, 6, 1),
    );
    expect(provider.calls.single.$2, LocalDate(2023, 1, 1));
    expect(provider.calls.single.$3, LocalDate(2023, 5, 31));
  });
}

final class _Provider implements EconomicSeriesProvider {
  final calls = <(EconomicSeriesCode, LocalDate, LocalDate)>[];
  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async {
    calls.add((code, from, through));
    return const [];
  }
}
