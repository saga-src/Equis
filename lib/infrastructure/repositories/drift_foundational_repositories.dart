import 'package:drift/drift.dart';

import '../../application/ports/foundational_repositories.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/entities/vault_profile.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/taxonomy/tag.dart' as domain;
import '../persistence/database/equis_database.dart';
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftVaultRepository implements VaultRepository {
  const DriftVaultRepository(this.database, {this.syncRecorder});
  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(VaultProfile vault) =>
      syncRecorder?.run(
        vaultId: vault.id.value,
        entityType: SyncEntityType.vault,
        recordId: vault.id.value,
        newRevision: vault.revision,
        operation: vault.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(vault),
      ) ??
      _save(vault);

  Future<void> _save(VaultProfile vault) => database
      .into(database.vaults)
      .insertOnConflictUpdate(
        VaultsCompanion.insert(
          id: Value(vault.id.value),
          name: vault.name,
          baseCurrencyCode: vault.baseCurrency.value,
          locale: Value(vault.locale),
          timezone: vault.timezone,
          createdAt: vault.createdAt.epochMicroseconds,
          updatedAt: vault.updatedAt.epochMicroseconds,
          deletedAt: Value(vault.deletedAt?.epochMicroseconds),
          revision: Value(vault.revision),
        ),
      );

  @override
  Future<VaultProfile?> find(EntityId id) async {
    final query = database.select(database.vaults)
      ..where((row) => row.id.equals(id.value));
    return _vaultFromRow(await query.getSingleOrNull());
  }

  @override
  Future<List<VaultProfile>> listActive() async {
    final query = database.select(database.vaults)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return (await query.get())
        .map(_vaultFromRequiredRow)
        .toList(growable: false);
  }
}

final class DriftAccountRepository implements AccountRepository {
  const DriftAccountRepository(this.database);
  final EquisDatabase database;

  @override
  Future<void> save(AccountProfile account) => database
      .into(database.accounts)
      .insertOnConflictUpdate(
        AccountsCompanion.insert(
          id: Value(account.id.value),
          vaultId: account.vaultId.value,
          name: account.name,
          institution: Value(account.institution),
          accountType: account.type.stored,
          nature: account.nature.name,
          includeInNetWorth: Value(account.includeInNetWorth ? 1 : 0),
          archived: Value(account.archived ? 1 : 0),
          openedOn: Value(account.openedOn?.toString()),
          closedOn: Value(account.closedOn?.toString()),
          sortOrder: Value(account.sortOrder),
          revision: Value(account.revision),
          createdAt: account.createdAt.epochMicroseconds,
          updatedAt: account.updatedAt.epochMicroseconds,
          deletedAt: Value(account.deletedAt?.epochMicroseconds),
        ),
      );

  @override
  Future<AccountProfile?> find(EntityId id) async {
    final query = database.select(database.accounts)
      ..where((row) => row.id.equals(id.value));
    return _accountFromRow(await query.getSingleOrNull());
  }

  @override
  Future<List<AccountProfile>> listForVault(EntityId vaultId) async {
    final query = database.select(database.accounts)
      ..where((row) => row.vaultId.equals(vaultId.value))
      ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]);
    return (await query.get())
        .map(_accountFromRequiredRow)
        .toList(growable: false);
  }
}

final class DriftAccountAggregateRepository
    implements AccountAggregateRepository {
  const DriftAccountAggregateRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(AccountAggregate aggregate) =>
      syncRecorder?.run(
        vaultId: aggregate.account.vaultId.value,
        entityType: SyncEntityType.account,
        recordId: aggregate.account.id.value,
        newRevision: aggregate.account.revision,
        operation: aggregate.account.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(aggregate),
      ) ??
      _save(aggregate);

  Future<void> _save(AccountAggregate aggregate) =>
      database.transaction(() async {
        await DriftAccountRepository(database).save(aggregate.account);
        for (final pocket in aggregate.pockets) {
          await database
              .into(database.accountPockets)
              .insertOnConflictUpdate(
                AccountPocketsCompanion.insert(
                  id: Value(pocket.id.value),
                  accountId: pocket.accountId.value,
                  currencyCode: pocket.currency.value,
                  name: Value(pocket.name),
                  isDefault: Value(pocket.isDefault ? 1 : 0),
                  archived: Value(pocket.archived ? 1 : 0),
                ),
              );
        }
      });

  @override
  Future<AccountAggregate?> findAggregate(EntityId id) async {
    final account = await DriftAccountRepository(database).find(id);
    if (account == null) return null;
    return AccountAggregate(account: account, pockets: await _pockets(id));
  }

  @override
  Future<List<AccountAggregate>> listAggregatesForVault(
    EntityId vaultId,
  ) async {
    final profiles = await DriftAccountRepository(
      database,
    ).listForVault(vaultId);
    return Future.wait([
      for (final profile in profiles)
        _pockets(profile.id).then(
          (pockets) => AccountAggregate(account: profile, pockets: pockets),
        ),
    ]);
  }

  Future<List<AccountPocketProfile>> _pockets(EntityId accountId) async {
    final query = database.select(database.accountPockets)
      ..where((row) => row.accountId.equals(accountId.value))
      ..orderBy([(row) => OrderingTerm.desc(row.isDefault)]);
    return (await query.get())
        .map(
          (row) => AccountPocketProfile(
            id: EntityId.parse(row.id!),
            accountId: EntityId.parse(row.accountId),
            currency: CurrencyCode(row.currencyCode),
            name: row.name,
            isDefault: row.isDefault != 0,
            archived: row.archived != 0,
          ),
        )
        .toList(growable: false);
  }
}

final class DriftCategoryRepository implements CategoryRepository {
  const DriftCategoryRepository(this.database, {this.syncRecorder});
  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(CategoryNode category) =>
      syncRecorder?.run(
        vaultId: category.vaultId.value,
        entityType: SyncEntityType.category,
        recordId: category.id.value,
        newRevision: category.revision,
        operation: category.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(category),
      ) ??
      _save(category);

  Future<void> _save(CategoryNode category) => database
      .into(database.categories)
      .insertOnConflictUpdate(
        CategoriesCompanion.insert(
          id: Value(category.id.value),
          vaultId: category.vaultId.value,
          parentId: Value(category.parentId?.value),
          categoryType: category.type.name,
          systemKey: Value(category.systemKey),
          customName: Value(category.customName),
          customNameEnUs: Value(category.customNameEnUs),
          customNamePtBr: Value(category.customNamePtBr),
          archived: Value(category.archived ? 1 : 0),
          sortOrder: Value(category.sortOrder),
          revision: Value(category.revision),
          createdAt: category.createdAt.epochMicroseconds,
          updatedAt: category.updatedAt.epochMicroseconds,
          deletedAt: Value(category.deletedAt?.epochMicroseconds),
        ),
      );

  @override
  Future<CategoryNode?> find(EntityId id) async {
    final query = database.select(database.categories)
      ..where((row) => row.id.equals(id.value));
    return _categoryFromRow(await query.getSingleOrNull());
  }

  @override
  Future<List<CategoryNode>> listForVault(EntityId vaultId) async {
    final query = database.select(database.categories)
      ..where((row) => row.vaultId.equals(vaultId.value))
      ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]);
    return (await query.get())
        .map(_categoryFromRequiredRow)
        .toList(growable: false);
  }
}

final class DriftCurrencyRepository implements CurrencyRepository {
  const DriftCurrencyRepository(this.database);
  final EquisDatabase database;

  @override
  Future<void> save(
    CurrencyDefinition currency, {
    required String nameKey,
    required String symbol,
  }) {
    currency.validate();
    return database
        .into(database.currencies)
        .insertOnConflictUpdate(
          CurrenciesCompanion.insert(
            code: Value(currency.code.value),
            nameKey: nameKey,
            symbol: symbol,
            minorUnits: currency.minorUnits,
          ),
        );
  }

  @override
  Future<CurrencyDefinition?> find(CurrencyCode code) async {
    final query = database.select(database.currencies)
      ..where((row) => row.code.equals(code.value));
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : CurrencyDefinition(
            code: CurrencyCode(row.code!),
            minorUnits: row.minorUnits,
          );
  }
}

final class DriftTagRepository implements TagRepository {
  const DriftTagRepository(this.database, {this.syncRecorder});
  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(domain.Tag tag) =>
      syncRecorder?.run(
        vaultId: tag.vaultId.value,
        entityType: SyncEntityType.tag,
        recordId: tag.id.value,
        newRevision: tag.revision,
        operation: tag.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(tag),
      ) ??
      _save(tag);

  Future<void> _save(domain.Tag tag) => database
      .into(database.tags)
      .insertOnConflictUpdate(
        TagsCompanion.insert(
          id: Value(tag.id.value),
          vaultId: tag.vaultId.value,
          name: tag.name,
          nameEnUs: Value(tag.nameEnUs),
          namePtBr: Value(tag.namePtBr),
          color: Value(tag.color),
          revision: Value(tag.revision),
          createdAt: tag.createdAt.epochMicroseconds,
          updatedAt: tag.updatedAt.epochMicroseconds,
          deletedAt: Value(tag.deletedAt?.epochMicroseconds),
        ),
      );

  @override
  Future<domain.Tag?> find(EntityId id) async {
    final query = database.select(database.tags)
      ..where((row) => row.id.equals(id.value));
    final row = await query.getSingleOrNull();
    return row == null ? null : _tag(row);
  }

  @override
  Future<List<domain.Tag>> listForVault(EntityId vaultId) async {
    final query = database.select(database.tags)
      ..where(
        (row) => row.vaultId.equals(vaultId.value) & row.deletedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return (await query.get()).map(_tag).toList(growable: false);
  }

  domain.Tag _tag(Tag row) => domain.Tag(
    id: EntityId.parse(row.id!),
    vaultId: EntityId.parse(row.vaultId),
    name: row.name,
    nameEnUs: row.nameEnUs,
    namePtBr: row.namePtBr,
    color: row.color,
    revision: row.revision,
    createdAt: UtcInstant.fromEpochMicroseconds(row.createdAt),
    updatedAt: UtcInstant.fromEpochMicroseconds(row.updatedAt),
    deletedAt: row.deletedAt == null
        ? null
        : UtcInstant.fromEpochMicroseconds(row.deletedAt!),
  );
}

VaultProfile? _vaultFromRow(Vault? row) =>
    row == null ? null : _vaultFromRequiredRow(row);

VaultProfile _vaultFromRequiredRow(Vault row) => VaultProfile(
  id: EntityId.parse(row.id!),
  name: row.name,
  baseCurrency: CurrencyCode(row.baseCurrencyCode),
  locale: row.locale,
  timezone: row.timezone,
  createdAt: UtcInstant.fromEpochMicroseconds(row.createdAt),
  updatedAt: UtcInstant.fromEpochMicroseconds(row.updatedAt),
  deletedAt: row.deletedAt == null
      ? null
      : UtcInstant.fromEpochMicroseconds(row.deletedAt!),
  revision: row.revision,
);

AccountProfile? _accountFromRow(Account? row) =>
    row == null ? null : _accountFromRequiredRow(row);

AccountProfile _accountFromRequiredRow(Account row) => AccountProfile(
  id: EntityId.parse(row.id!),
  vaultId: EntityId.parse(row.vaultId),
  name: row.name,
  institution: row.institution,
  type: AccountType.fromStorage(row.accountType),
  nature: AccountNature.values.byName(row.nature),
  includeInNetWorth: row.includeInNetWorth != 0,
  archived: row.archived != 0,
  openedOn: row.openedOn == null ? null : LocalDate.parse(row.openedOn!),
  closedOn: row.closedOn == null ? null : LocalDate.parse(row.closedOn!),
  sortOrder: row.sortOrder,
  revision: row.revision,
  createdAt: UtcInstant.fromEpochMicroseconds(row.createdAt),
  updatedAt: UtcInstant.fromEpochMicroseconds(row.updatedAt),
  deletedAt: row.deletedAt == null
      ? null
      : UtcInstant.fromEpochMicroseconds(row.deletedAt!),
);

CategoryNode? _categoryFromRow(Category? row) =>
    row == null ? null : _categoryFromRequiredRow(row);

CategoryNode _categoryFromRequiredRow(Category row) => CategoryNode(
  id: EntityId.parse(row.id!),
  vaultId: EntityId.parse(row.vaultId),
  parentId: row.parentId == null ? null : EntityId.parse(row.parentId!),
  type: CategoryType.values.byName(row.categoryType),
  systemKey: row.systemKey,
  customName: row.customName,
  customNameEnUs: row.customNameEnUs,
  customNamePtBr: row.customNamePtBr,
  archived: row.archived != 0,
  sortOrder: row.sortOrder,
  revision: row.revision,
  createdAt: UtcInstant.fromEpochMicroseconds(row.createdAt),
  updatedAt: UtcInstant.fromEpochMicroseconds(row.updatedAt),
  deletedAt: row.deletedAt == null
      ? null
      : UtcInstant.fromEpochMicroseconds(row.deletedAt!),
);
