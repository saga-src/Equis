import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:equis/application/ports/wealth_repository.dart';
import 'package:equis/application/services/wealth_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/wealth/asset_models.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide AssetValuation;
import 'package:equis/infrastructure/repositories/drift_dashboard_repository.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/repositories/drift_wealth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;
  late DriftWealthRepository repository;
  late WealthService service;
  late EntityId vaultId;
  late PhysicalAsset vehicle;

  setUp(() async {
    database = EquisDatabase(NativeDatabase.memory());
    repository = DriftWealthRepository(database);
    service = WealthService(
      repository: repository,
      reporting: DriftDashboardRepository(database),
    );
    vaultId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, 1, 1)',
      [vaultId.value, 'Local', 'BRL', 'UTC'],
    );
    await database.customStatement(
      "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL','brl','R\$',2)",
    );
    await _account(
      database,
      vaultId,
      'Cash',
      AccountNature.asset,
      100000,
      included: true,
    );
    await _account(
      database,
      vaultId,
      'Excluded',
      AccountNature.asset,
      50000,
      included: false,
    );
    await _account(
      database,
      vaultId,
      'Loan',
      AccountNature.liability,
      20000,
      included: true,
    );
    vehicle = await service.createAsset(
      vaultId: vaultId,
      name: 'Vehicle',
      type: PhysicalAssetType.vehicle,
      currency: CurrencyCode.brl,
      acquiredOn: LocalDate(2025, 1, 15),
      acquisitionCostMinor: 1200000,
      valuationMethod: AssetValuationMethod.straightLine,
      usefulLifeMonths: 60,
      salvageValueMinor: 200000,
      now: const UtcInstant.fromEpochMicroseconds(1),
    );
  });

  tearDown(() => database.close());

  test(
    'net worth subtracts included liabilities and excludes opted-out accounts',
    () async {
      final report = await service.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 15),
        historyMonths: 2,
      );
      expect(report.current.assetsMinor, 1100000);
      expect(report.current.liabilitiesMinor, 20000);
      expect(report.current.netWorthMinor, 1080000);
      expect(report.physicalAssets.single.valueMinor, 1000000);
      expect(report.current.missingRates, isEmpty);
    },
  );

  test(
    'manual valuation wins on the same date and history remains reproducible',
    () async {
      await repository.addValuation(
        AssetValuation(
          id: EntityId.generate(),
          assetId: vehicle.id,
          date: LocalDate(2026, 1, 15),
          valueMinor: 950000,
          source: AssetValuationSource.calculated,
        ),
      );
      await service.overrideValue(
        asset: vehicle,
        date: LocalDate(2026, 1, 15),
        valueMinor: 900000,
        notes: 'Dealer quote',
      );
      final first = await service.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 15),
        historyMonths: 3,
      );
      final second = await service.report(
        vaultId: vaultId,
        currency: CurrencyCode.brl,
        asOf: LocalDate(2026, 1, 15),
        historyMonths: 3,
      );
      expect(first.physicalAssets.single.valueMinor, 900000);
      expect(first.current.netWorthMinor, 980000);
      expect(
        first.history.map((point) => point.netWorthMinor),
        second.history.map((point) => point.netWorthMinor),
      );
      expect((await repository.valuations(vehicle.id)), hasLength(2));
      expect(first.history.first.date, LocalDate(2025, 11, 30));
      expect(first.history.first.netWorthMinor, 1113334);
    },
  );

  test(
    'asset revisions conflict and valuation records are preserved',
    () async {
      final loaded = await repository.findAsset(vehicle.id);
      final changed = loaded!.revise(
        name: 'Car',
        at: const UtcInstant.fromEpochMicroseconds(2),
      );
      await repository.saveAsset(changed);
      expect((await repository.findAsset(vehicle.id))!.name, 'Car');
      await expectLater(
        repository.saveAsset(
          loaded.revise(
            name: 'Stale',
            at: const UtcInstant.fromEpochMicroseconds(3),
          ),
        ),
        throwsA(isA<AssetRevisionConflict>()),
      );
    },
  );

  test('percentage and custom models are deterministic', () {
    final base = PhysicalAsset(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'Model',
      type: PhysicalAssetType.other,
      currency: CurrencyCode.brl,
      acquiredOn: LocalDate(2025, 1, 1),
      acquisitionCostMinor: 10000,
      valuationMethod: AssetValuationMethod.percentageDepreciation,
      annualRate: Decimal.parse('0.12'),
      createdAt: const UtcInstant.fromEpochMicroseconds(1),
      updatedAt: const UtcInstant.fromEpochMicroseconds(1),
    );
    expect(modelAssetValue(base, LocalDate(2026, 1, 1)), 8864);
    expect(
      modelAssetValue(
        base.revise(
          valuationMethod: AssetValuationMethod.percentageAppreciation,
          at: const UtcInstant.fromEpochMicroseconds(2),
        ),
        LocalDate(2026, 1, 1),
      ),
      11268,
    );
    expect(
      modelAssetValue(
        base.revise(
          valuationMethod: AssetValuationMethod.custom,
          at: const UtcInstant.fromEpochMicroseconds(2),
        ),
        LocalDate(2026, 1, 1),
      ),
      10000,
    );
  });
}

Future<void> _account(
  EquisDatabase database,
  EntityId vaultId,
  String name,
  AccountNature nature,
  int balance, {
  required bool included,
}) async {
  final accountId = EntityId.generate();
  final pocketId = EntityId.generate();
  await database.customStatement(
    'INSERT INTO accounts (id, vault_id, name, account_type, nature, include_in_net_worth, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, 1, 1)',
    [
      accountId.value,
      vaultId.value,
      name,
      nature == AccountNature.asset ? 'checking' : 'loan',
      nature.name,
      included ? 1 : 0,
    ],
  );
  await database.customStatement(
    'INSERT INTO account_pockets (id, account_id, currency_code, is_default) VALUES (?, ?, ?, 1)',
    [pocketId.value, accountId.value, 'BRL'],
  );
  final ledger = DriftLedgerRepository(database);
  await ledger.save(
    LedgerEngine().openingBalance(
      vaultId: vaultId,
      pocket: LedgerPocket(
        id: pocketId,
        currency: CurrencyCode.brl,
        nature: nature,
      ),
      signedAmount: Money(currency: CurrencyCode.brl, minorUnits: balance),
      date: LocalDate(2025, 1, 1),
      now: const UtcInstant.fromEpochMicroseconds(1),
    ),
  );
}
