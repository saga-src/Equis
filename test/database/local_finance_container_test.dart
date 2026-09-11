import 'package:drift/native.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/infrastructure/persistence/dao/ledger_balance_reader.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local profile seeds BRL/USD and one account supports both pockets',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _service(database);
      const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
      final vault = await service.createLocalProfile(
        name: 'Local only',
        reportingCurrency: CurrencyCode.brl,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        now: now,
      );
      expect(
        await DriftCurrencyRepository(database).find(CurrencyCode.brl),
        isNotNull,
      );
      expect(
        await DriftCurrencyRepository(database).find(CurrencyCode.usd),
        isNotNull,
      );

      final account = await service.createAccount(
        vaultId: vault.id,
        name: 'Multicurrency',
        type: AccountType.checking,
        nature: AccountNature.asset,
        pocketCurrencies: [CurrencyCode.brl, CurrencyCode.usd],
        defaultCurrency: CurrencyCode.brl,
        openedOn: LocalDate.parse('2026-08-13'),
        openingBalances: {
          CurrencyCode.brl: Money(
            currency: CurrencyCode.brl,
            minorUnits: 10000,
          ),
          CurrencyCode.usd: Money(currency: CurrencyCode.usd, minorUnits: 2500),
        },
        now: now,
      );
      final reloaded = await DriftAccountAggregateRepository(
        database,
      ).findAggregate(account.account.id);
      expect(reloaded?.pockets.map((pocket) => pocket.currency).toSet(), {
        CurrencyCode.brl,
        CurrencyCode.usd,
      });
      final balances = await LedgerBalanceReader(database).rebuildAll();
      expect(
        balances[account.pockets
            .singleWhere((p) => p.currency == CurrencyCode.brl)
            .id
            .value],
        10000,
      );
      expect(
        balances[account.pockets
            .singleWhere((p) => p.currency == CurrencyCode.usd)
            .id
            .value],
        2500,
      );
    },
  );

  test(
    'account archive and reporting-currency changes preserve ledger history',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _service(database);
      const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
      var vault = await service.createLocalProfile(
        name: 'Local',
        reportingCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        now: now,
      );
      var account = await service.createAccount(
        vaultId: vault.id,
        name: 'USD account',
        type: AccountType.savings,
        nature: AccountNature.asset,
        pocketCurrencies: [CurrencyCode.usd],
        defaultCurrency: CurrencyCode.usd,
        openingBalances: {
          CurrencyCode.usd: Money(currency: CurrencyCode.usd, minorUnits: 9999),
        },
        now: now,
      );
      vault = await service.changeReportingCurrency(
        vault,
        CurrencyCode.usd,
        now: now,
      );
      account = await service.setNetWorthInclusion(account, false, now: now);
      account = await service.archiveAccount(account, now: now);

      expect(vault.baseCurrency, CurrencyCode.usd);
      expect(account.account.includeInNetWorth, isFalse);
      expect(account.account.archived, isTrue);
      expect(await LedgerBalanceReader(database).rebuildAll(), {
        account.pockets.single.id.value: 9999,
      });
      final movement = await database
          .customSelect(
            'SELECT pocket.currency_code, movement.amount_minor FROM account_movements movement '
            'JOIN account_pockets pocket ON pocket.id = movement.account_pocket_id',
          )
          .getSingle();
      expect(movement.read<String>('currency_code'), 'USD');
      expect(movement.read<int>('amount_minor'), 9999);
    },
  );

  test('account creation has no artificial quantity limit', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final service = _service(database);
    const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
    final vault = await service.createLocalProfile(
      name: 'Local',
      reportingCurrency: CurrencyCode.brl,
      locale: 'pt-BR',
      timezone: 'UTC',
      now: now,
    );
    for (var index = 0; index < 30; index++) {
      await service.createAccount(
        vaultId: vault.id,
        name: 'Account $index',
        type: AccountType.custom,
        nature: AccountNature.asset,
        pocketCurrencies: [CurrencyCode.brl],
        defaultCurrency: CurrencyCode.brl,
        now: now,
      );
    }
    expect(
      await DriftAccountAggregateRepository(
        database,
      ).listAggregatesForVault(vault.id),
      hasLength(30),
    );
  });

  test(
    'all v1 account types are represented and failed opening setup rolls back',
    () async {
      expect(AccountType.values.map((type) => type.stored).toSet(), {
        'checking',
        'savings',
        'cash',
        'credit_card',
        'digital_wallet',
        'investment',
        'loan',
        'mortgage',
        'financing',
        'other_asset',
        'other_liability',
        'custom',
      });
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _service(database);
      const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
      final vault = await service.createLocalProfile(
        name: 'Local',
        reportingCurrency: CurrencyCode.brl,
        locale: 'pt-BR',
        timezone: 'UTC',
        now: now,
      );
      await expectLater(
        service.createAccount(
          vaultId: vault.id,
          name: 'Must rollback',
          type: AccountType.checking,
          nature: AccountNature.asset,
          pocketCurrencies: [CurrencyCode.brl],
          defaultCurrency: CurrencyCode.brl,
          openingBalances: {
            CurrencyCode.usd: Money(currency: CurrencyCode.usd, minorUnits: 1),
          },
          now: now,
        ),
        throwsStateError,
      );
      expect(
        await DriftAccountAggregateRepository(
          database,
        ).listAggregatesForVault(vault.id),
        isEmpty,
      );
    },
  );
}

LocalFinanceContainerService _service(EquisDatabase database) =>
    LocalFinanceContainerService(
      vaults: DriftVaultRepository(database),
      currencies: DriftCurrencyRepository(database),
      accounts: DriftAccountAggregateRepository(database),
      ledger: DriftLedgerRepository(database),
      unitOfWork: DriftLocalUnitOfWork(database),
    );
