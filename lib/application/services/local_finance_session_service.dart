import '../ports/foundational_repositories.dart';
import '../ports/ledger_repository.dart';
import '../ports/local_unit_of_work.dart';
import '../ports/sync_aggregate_store.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/entities/account_removal_assessment.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/entities/vault_profile.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/taxonomy/tag.dart';
import 'everyday_transaction_service.dart';
import 'local_finance_container_service.dart';
import 'taxonomy_service.dart';

final class LocalFinanceSnapshot {
  const LocalFinanceSnapshot({
    required this.vault,
    this.accounts = const [],
    this.categories = const [],
    this.tags = const [],
    this.recentTransactions = const [],
  });

  final VaultProfile? vault;
  final List<AccountAggregate> accounts;
  final List<CategoryNode> categories;
  final List<Tag> tags;
  final List<LedgerTransaction> recentTransactions;

  bool get requiresSetup => vault == null;
}

final class TransactionDetailData {
  const TransactionDetailData({
    required this.transaction,
    required this.accounts,
    required this.categories,
    required this.tags,
  });

  final LedgerTransaction transaction;
  final List<AccountAggregate> accounts;
  final List<CategoryNode> categories;
  final List<Tag> tags;
}

final class LocalFinanceSessionService {
  const LocalFinanceSessionService({
    required this.vaults,
    required this.accounts,
    required this.categories,
    required this.tags,
    required this.ledger,
    required this.unitOfWork,
    required this.containers,
    required this.taxonomy,
    required this.everydayTransactions,
    this.accountSyncRecovery,
  });

  final VaultRepository vaults;
  final AccountAggregateRepository accounts;
  final CategoryRepository categories;
  final TagRepository tags;
  final LedgerRepository ledger;
  final LocalUnitOfWork unitOfWork;
  final LocalFinanceContainerService containers;
  final TaxonomyService taxonomy;
  final EverydayTransactionService everydayTransactions;
  final AccountSyncRecoveryStore? accountSyncRecovery;

  Future<void> _requireActiveVault(EntityId vaultId) async {
    final activeVaults = await vaults.listActive();
    if (activeVaults.isEmpty || activeVaults.first.id != vaultId) {
      throw const AccountLifecycleConflict();
    }
  }

  Future<List<AccountAggregate>> loadAccountsForManagement(EntityId vaultId) =>
      unitOfWork.run(() async {
        await _requireActiveVault(vaultId);
        return accounts.listAggregatesForVault(vaultId);
      });

  Future<List<AccountSyncRecoveryState>> loadAccountRecoveryStates(
    EntityId vaultId,
  ) => unitOfWork.run(() async {
    await _requireActiveVault(vaultId);
    final store = accountSyncRecovery;
    if (store == null) return const <AccountSyncRecoveryState>[];
    return store.accountRecoveryStates(vaultId.value);
  });

  Future<AccountRemovalAssessment> assessAccountRemoval(
    AccountAggregate account, {
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    await _requireActiveVault(account.account.vaultId);
    return containers.assessAccountRemoval(
      vaultId: account.account.vaultId,
      accountId: account.account.id,
      now: now,
    );
  });

  Future<LocalFinanceSnapshot> removeAccount(
    AccountAggregate account, {
    required UtcInstant now,
  }) async {
    await unitOfWork.run(() async {
      await _requireActiveVault(account.account.vaultId);
      await containers.removeAccount(
        vaultId: account.account.vaultId,
        accountId: account.account.id,
        expectedRevision: account.account.revision,
        now: now,
      );
    });
    return load();
  }

  Future<LocalFinanceSnapshot> restoreAccount(
    AccountAggregate account, {
    required UtcInstant now,
  }) async {
    await unitOfWork.run(() async {
      await _requireActiveVault(account.account.vaultId);
      await containers.restoreAccount(
        vaultId: account.account.vaultId,
        accountId: account.account.id,
        expectedRevision: account.account.revision,
        now: now,
      );
    });
    return load();
  }

  Future<LocalFinanceSnapshot> requestAccountRestore({
    required EntityId vaultId,
    required AccountSyncRecoveryState recovery,
    required UtcInstant now,
  }) async {
    await unitOfWork.run(() async {
      await _requireActiveVault(vaultId);
      final store = accountSyncRecovery;
      if (store == null) throw StateError('Account recovery is unavailable.');
      final states = await store.accountRecoveryStates(vaultId.value);
      if (!states.any(
        (state) =>
            state.accountId == recovery.accountId &&
            state.revision == recovery.revision &&
            !state.restorationPending,
      )) {
        throw const AccountLifecycleConflict();
      }
      await store.requestAccountRestore(
        vaultId: vaultId.value,
        accountId: recovery.accountId,
        expectedRevision: recovery.revision,
        nowMicros: now.epochMicroseconds,
      );
    });
    return load();
  }

  Future<LocalFinanceSnapshot> load() async {
    final activeVaults = await vaults.listActive();
    if (activeVaults.isEmpty) return const LocalFinanceSnapshot(vault: null);
    final vault = activeVaults.first;
    return LocalFinanceSnapshot(
      vault: vault,
      accounts: (await accounts.listAggregatesForVault(vault.id))
          .where(
            (account) =>
                !account.account.archived && account.account.deletedAt == null,
          )
          .toList(growable: false),
      categories: (await categories.listForVault(vault.id))
          .where((category) => !category.archived && category.deletedAt == null)
          .toList(growable: false),
      tags: await tags.listForVault(vault.id),
      recentTransactions: await ledger.listRecentForVault(vault.id),
    );
  }

  Future<LedgerTransaction?> loadTransactionDetail({
    required EntityId id,
    required EntityId vaultId,
  }) async {
    final activeVaults = await vaults.listActive();
    if (activeVaults.isEmpty || activeVaults.first.id != vaultId) return null;
    return ledger.findActiveForVault(id, vaultId);
  }

  Future<TransactionDetailData?> loadTransactionDetailData({
    required EntityId id,
    required EntityId vaultId,
  }) async {
    final transaction = await loadTransactionDetail(id: id, vaultId: vaultId);
    if (transaction == null) return null;
    final accountRows = await accounts.listAggregatesForVault(vaultId);
    final categoryRows = await categories.listForVault(vaultId);
    final tagRows = [...await tags.listForVault(vaultId)];
    final knownTags = tagRows.map((tag) => tag.id).toSet();
    for (final tagId in transaction.tagIds) {
      if (knownTags.contains(tagId)) continue;
      final historical = await tags.find(tagId);
      if (historical != null && historical.vaultId == vaultId) {
        tagRows.add(historical);
        knownTags.add(tagId);
      }
    }
    final activeVaults = await vaults.listActive();
    if (activeVaults.isEmpty || activeVaults.first.id != vaultId) return null;
    return TransactionDetailData(
      transaction: transaction,
      accounts: accountRows,
      categories: categoryRows,
      tags: tagRows,
    );
  }

  Future<LocalFinanceSnapshot> setupLocalVault({
    required String profileName,
    required String accountName,
    required CurrencyCode currency,
    required String locale,
    required String timezone,
    required UtcInstant now,
  }) async {
    await unitOfWork.run(() async {
      final vault = await containers.createLocalProfile(
        name: profileName,
        reportingCurrency: currency,
        locale: locale,
        timezone: timezone,
        now: now,
      );
      await taxonomy.seedDefaults(vault.id, now);
      await containers.createAccount(
        vaultId: vault.id,
        name: accountName,
        type: AccountType.cash,
        nature: AccountNature.asset,
        pocketCurrencies: [currency],
        defaultCurrency: currency,
        now: now,
      );
    });
    return load();
  }

  Future<LocalFinanceSnapshot> createEverydayTransaction({
    required EverydayTransactionType type,
    required LedgerPocket source,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? categoryId,
    LedgerPocket? destination,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) async {
    final vault = (await load()).vault;
    if (vault == null) throw StateError('A local vault is required.');
    await everydayTransactions.create(
      type: type,
      vaultId: vault.id,
      source: source,
      destination: destination,
      amount: amount,
      categoryId: categoryId,
      date: date,
      now: now,
      tagIds: tagIds,
      title: title,
      notes: notes,
    );
    return load();
  }

  Future<LocalFinanceSnapshot> updateEverydayTransaction({
    required LedgerTransaction existing,
    required LedgerPocket source,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? categoryId,
    LedgerPocket? destination,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) async {
    await unitOfWork.run(() async {
      final activeVaults = await vaults.listActive();
      if (activeVaults.isEmpty || activeVaults.first.id != existing.vaultId) {
        throw StateError('The active vault has changed.');
      }
      final current = await ledger.findActiveForVault(
        existing.id,
        existing.vaultId,
      );
      if (current == null) throw StateError('Transaction no longer exists.');
      if (current.revision != existing.revision) {
        throw LedgerRevisionConflict(
          transactionId: existing.id,
          expectedRevision: existing.revision,
          actualRevision: current.revision,
        );
      }
      final accountRows = await accounts.listAggregatesForVault(
        existing.vaultId,
      );
      final categoryRows = await categories.listForVault(existing.vaultId);
      if (!everydayTransactionCanEdit(
        current,
        accounts: accountRows,
        categories: categoryRows,
      )) {
        throw StateError('This transaction is not editable.');
      }
      LedgerPocket? activePocket(EntityId id) {
        for (final account in accountRows) {
          if (account.account.vaultId != existing.vaultId ||
              account.account.archived ||
              account.account.deletedAt != null) {
            continue;
          }
          for (final pocket in account.pockets) {
            if (pocket.id == id && !pocket.archived) {
              return LedgerPocket(
                id: pocket.id,
                currency: pocket.currency,
                nature: account.account.nature,
              );
            }
          }
        }
        return null;
      }

      final currentSource = activePocket(source.id);
      final currentDestination = destination == null
          ? null
          : activePocket(destination.id);
      if (currentSource == null ||
          (current.type == LedgerTransactionType.transfer) !=
              (destination != null) ||
          (destination != null && currentDestination == null) ||
          currentSource.currency != source.currency ||
          currentSource.nature != source.nature ||
          (destination != null &&
              (currentDestination!.currency != destination.currency ||
                  currentDestination.nature != destination.nature))) {
        throw StateError('An account is no longer active.');
      }
      if (current.type != LedgerTransactionType.transfer) {
        final expectedType = current.type == LedgerTransactionType.income
            ? CategoryType.income
            : CategoryType.expense;
        if (categoryId == null ||
            !categoryRows.any(
              (category) =>
                  category.id == categoryId &&
                  category.vaultId == existing.vaultId &&
                  category.type == expectedType &&
                  !category.archived &&
                  category.deletedAt == null,
            )) {
          throw StateError('The category is no longer active.');
        }
      }
      await everydayTransactions.update(
        existing: current,
        source: currentSource,
        destination: currentDestination,
        amount: amount,
        categoryId: categoryId,
        date: date,
        now: now,
        tagIds: tagIds,
        title: title,
        notes: notes,
      );
    });
    return load();
  }

  Future<LocalFinanceSnapshot> deleteTransaction(
    LedgerTransaction transaction, {
    required UtcInstant now,
  }) async {
    await ledger.save(transaction.softDelete(at: now));
    return load();
  }

  Future<LocalFinanceSnapshot> reconcileTransaction(
    LedgerTransaction transaction, {
    required UtcInstant now,
  }) async {
    await ledger.save(
      transaction.transitionTo(LedgerTransactionStatus.reconciled, at: now),
    );
    return load();
  }

  Future<LocalFinanceSnapshot> createCategory({
    required CategoryType type,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
    EntityId? parentId,
  }) async {
    final vault = (await load()).vault;
    if (vault == null) throw StateError('A local vault is required.');
    await taxonomy.createCategory(
      vaultId: vault.id,
      type: type,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      parentId: parentId,
      now: now,
    );
    return load();
  }

  Future<LocalFinanceSnapshot> archiveCategory(
    CategoryNode category, {
    required UtcInstant now,
  }) async {
    await taxonomy.archiveUserCategory(category, now: now);
    return load();
  }

  Future<LocalFinanceSnapshot> createTag({
    required String name,
    String? nameEnUs,
    String? namePtBr,
    String? color,
    required UtcInstant now,
  }) async {
    final vault = (await load()).vault;
    if (vault == null) throw StateError('A local vault is required.');
    await taxonomy.createTag(
      vaultId: vault.id,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      color: color,
      now: now,
    );
    return load();
  }

  Future<LocalFinanceSnapshot> updateCategoryNames({
    required CategoryNode category,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
  }) async {
    await taxonomy.updateCategoryNames(
      category: category,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      now: now,
    );
    return load();
  }

  Future<LocalFinanceSnapshot> updateTagNames({
    required Tag tag,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    required UtcInstant now,
  }) async {
    await taxonomy.updateTagNames(
      tag: tag,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      now: now,
    );
    return load();
  }

  Future<LocalFinanceSnapshot> createAccount({
    required String name,
    required AccountType type,
    required AccountNature nature,
    required CurrencyCode currency,
    required UtcInstant now,
  }) async {
    final vault = (await load()).vault;
    if (vault == null) throw StateError('A local vault is required.');
    await containers.createAccount(
      vaultId: vault.id,
      name: name,
      type: type,
      nature: nature,
      pocketCurrencies: [currency],
      defaultCurrency: currency,
      now: now,
    );
    return load();
  }

  Future<LocalFinanceSnapshot> setAccountNetWorthInclusion(
    AccountAggregate account,
    bool included, {
    required UtcInstant now,
  }) async {
    await containers.setNetWorthInclusion(account, included, now: now);
    return load();
  }
}
