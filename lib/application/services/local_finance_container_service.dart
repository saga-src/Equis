import '../ports/foundational_repositories.dart';
import '../ports/ledger_repository.dart';
import '../ports/local_unit_of_work.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/entities/vault_profile.dart';
import '../../domain/ledger/ledger_engine.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

enum FirstRunChoice { localOnly, cloudAccount }

final class LocalFinanceContainerService {
  LocalFinanceContainerService({
    required this.vaults,
    required this.currencies,
    required this.accounts,
    required this.ledger,
    required this.unitOfWork,
    LedgerEngine? ledgerEngine,
    this.onVaultCreated,
  }) : _ledgerEngine = ledgerEngine ?? LedgerEngine();

  final VaultRepository vaults;
  final CurrencyRepository currencies;
  final AccountAggregateRepository accounts;
  final LedgerRepository ledger;
  final LocalUnitOfWork unitOfWork;
  final LedgerEngine _ledgerEngine;
  final Future<void> Function(String)? onVaultCreated;

  Future<VaultProfile> createLocalProfile({
    required String name,
    required CurrencyCode reportingCurrency,
    required String locale,
    required String timezone,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    await _seedRequiredCurrencies();
    final profile = VaultProfile(
      id: EntityId.generate(),
      name: name,
      baseCurrency: reportingCurrency,
      locale: locale,
      timezone: timezone,
      createdAt: now,
      updatedAt: now,
    );
    await onVaultCreated?.call(profile.id.value);
    await vaults.save(profile);
    return profile;
  });

  Future<VaultProfile> changeReportingCurrency(
    VaultProfile profile,
    CurrencyCode currency, {
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    if (await currencies.find(currency) == null) {
      throw StateError('Reporting currency must exist in the local catalog.');
    }
    final revised = profile.revise(baseCurrency: currency, at: now);
    await vaults.save(revised);
    return revised;
  });

  Future<AccountAggregate> createAccount({
    required EntityId vaultId,
    required String name,
    required AccountType type,
    required AccountNature nature,
    required List<CurrencyCode> pocketCurrencies,
    required CurrencyCode defaultCurrency,
    required UtcInstant now,
    LocalDate? openedOn,
    bool includeInNetWorth = true,
    Map<CurrencyCode, Money> openingBalances = const {},
  }) => unitOfWork.run(() async {
    if (pocketCurrencies.isEmpty ||
        !pocketCurrencies.contains(defaultCurrency)) {
      throw ArgumentError(
        'Pocket currencies must include the default currency.',
      );
    }
    if (pocketCurrencies.toSet().length != pocketCurrencies.length) {
      throw ArgumentError('Pocket currencies must be unique.');
    }
    final accountId = EntityId.generate();
    final aggregate = AccountAggregate(
      account: AccountProfile(
        id: accountId,
        vaultId: vaultId,
        name: name,
        type: type,
        nature: nature,
        includeInNetWorth: includeInNetWorth,
        openedOn: openedOn,
        createdAt: now,
        updatedAt: now,
      ),
      pockets: [
        for (final currency in pocketCurrencies)
          AccountPocketProfile(
            id: EntityId.generate(),
            accountId: accountId,
            currency: currency,
            isDefault: currency == defaultCurrency,
          ),
      ],
    );
    await accounts.save(aggregate);
    for (final entry in openingBalances.entries) {
      final pocket = aggregate.pockets.singleWhere(
        (candidate) => candidate.currency == entry.key,
      );
      final instant = now.toDateTime();
      final opening = _ledgerEngine.openingBalance(
        vaultId: vaultId,
        pocket: LedgerPocket(
          id: pocket.id,
          currency: pocket.currency,
          nature: nature,
        ),
        signedAmount: entry.value,
        date: openedOn ?? LocalDate(instant.year, instant.month, instant.day),
        now: now,
      );
      await ledger.save(opening);
    }
    return aggregate;
  });

  Future<AccountAggregate> addCurrencyPocket(
    AccountAggregate aggregate,
    CurrencyCode currency,
  ) async {
    if (await currencies.find(currency) == null) {
      throw StateError('Currency must exist in the local catalog.');
    }
    final revised = aggregate.addPocket(
      AccountPocketProfile(
        id: EntityId.generate(),
        accountId: aggregate.account.id,
        currency: currency,
      ),
    );
    await accounts.save(revised);
    return revised;
  }

  Future<AccountAggregate> archiveAccount(
    AccountAggregate aggregate, {
    required UtcInstant now,
  }) async {
    final revised = aggregate.withAccount(
      aggregate.account.revise(archived: true, at: now),
    );
    await accounts.save(revised);
    return revised;
  }

  Future<AccountAggregate> setNetWorthInclusion(
    AccountAggregate aggregate,
    bool included, {
    required UtcInstant now,
  }) async {
    final revised = aggregate.withAccount(
      aggregate.account.revise(includeInNetWorth: included, at: now),
    );
    await accounts.save(revised);
    return revised;
  }

  Future<void> _seedRequiredCurrencies() async {
    await currencies.save(
      CurrencyDefinition(code: CurrencyCode.brl, minorUnits: 2),
      nameKey: 'currency.brl',
      symbol: r'R$',
    );
    await currencies.save(
      CurrencyDefinition(code: CurrencyCode.usd, minorUnits: 2),
      nameKey: 'currency.usd',
      symbol: r'US$',
    );
  }
}
