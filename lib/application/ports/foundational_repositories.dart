import '../../domain/entities/account_profile.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/entities/vault_profile.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/taxonomy/tag.dart';

abstract interface class VaultRepository {
  Future<void> save(VaultProfile vault);
  Future<VaultProfile?> find(EntityId id);
  Future<List<VaultProfile>> listActive();
}

abstract interface class AccountRepository {
  Future<void> save(AccountProfile account);
  Future<AccountProfile?> find(EntityId id);
  Future<List<AccountProfile>> listForVault(EntityId vaultId);
}

abstract interface class AccountAggregateRepository {
  Future<void> save(AccountAggregate account);
  Future<AccountAggregate?> findAggregate(EntityId id);
  Future<List<AccountAggregate>> listAggregatesForVault(EntityId vaultId);
}

abstract interface class CategoryRepository {
  Future<void> save(CategoryNode category);
  Future<CategoryNode?> find(EntityId id);
  Future<List<CategoryNode>> listForVault(EntityId vaultId);
}

abstract interface class CurrencyRepository {
  Future<void> save(
    CurrencyDefinition currency, {
    required String nameKey,
    required String symbol,
  });
  Future<CurrencyDefinition?> find(CurrencyCode code);
}

abstract interface class TagRepository {
  Future<void> save(Tag tag);
  Future<Tag?> find(EntityId id);
  Future<List<Tag>> listForVault(EntityId vaultId);
}
