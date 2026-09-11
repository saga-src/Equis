import 'package:drift/native.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foundational repositories persist and reload equivalent values',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const now = UtcInstant.fromEpochMicroseconds(1723392000123456);
      final vaultId = EntityId.generate();
      final accountId = EntityId.generate();
      final categoryId = EntityId.generate();
      final currencies = DriftCurrencyRepository(database);
      final vaults = DriftVaultRepository(database);
      final accounts = DriftAccountRepository(database);
      final categories = DriftCategoryRepository(database);

      await currencies.save(
        CurrencyDefinition(code: CurrencyCode.brl, minorUnits: 2),
        nameKey: 'currency.brl',
        symbol: r'R$',
      );
      await vaults.save(
        VaultProfile(
          id: vaultId,
          name: 'Principal',
          baseCurrency: CurrencyCode.brl,
          locale: 'pt-BR',
          timezone: 'America/Sao_Paulo',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await accounts.save(
        AccountProfile(
          id: accountId,
          vaultId: vaultId,
          name: 'Conta corrente',
          type: AccountType.checking,
          nature: AccountNature.asset,
          openedOn: LocalDate.parse('2026-08-13'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await categories.save(
        CategoryNode(
          id: categoryId,
          vaultId: vaultId,
          type: CategoryType.expense,
          customName: 'Mercado',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final reloadedVault = await vaults.find(vaultId);
      final reloadedAccount = await accounts.find(accountId);
      final reloadedCategory = await categories.find(categoryId);
      expect(reloadedVault?.baseCurrency, CurrencyCode.brl);
      expect(reloadedVault?.createdAt, now);
      expect(reloadedAccount?.openedOn, LocalDate.parse('2026-08-13'));
      expect(reloadedAccount?.type, AccountType.checking);
      expect(reloadedCategory?.customName, 'Mercado');
      expect((await accounts.listForVault(vaultId)).single.id, accountId);
      expect((await categories.listForVault(vaultId)).single.id, categoryId);
    },
  );
}
