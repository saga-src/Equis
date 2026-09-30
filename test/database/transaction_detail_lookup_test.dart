import 'package:drift/native.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active detail finds the 21st transaction in its vault only', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ledger = DriftLedgerRepository(database);
    final vaultId = EntityId.generate();
    final otherVaultId = EntityId.generate();
    final pocketId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, 1, 1)',
      [vaultId.value, 'Local', 'BRL', 'America/Sao_Paulo'],
    );
    await database.customStatement(
      'INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, 2, 2)',
      [otherVaultId.value, 'Other', 'BRL', 'America/Sao_Paulo'],
    );
    await database.customStatement(
      'INSERT INTO currencies (code, name_key, symbol, minor_units) '
      "VALUES ('BRL', 'currency.brl', 'R\$', 2)",
    );
    final accountId = EntityId.generate();
    await database.customStatement(
      'INSERT INTO accounts '
      '(id, vault_id, name, account_type, nature, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 1, 1)',
      [accountId.value, vaultId.value, 'Checking', 'checking', 'asset'],
    );
    await database.customStatement(
      'INSERT INTO account_pockets (id, account_id, currency_code, is_default) '
      'VALUES (?, ?, ?, 1)',
      [pocketId.value, accountId.value, 'BRL'],
    );

    final transactions = <LedgerTransaction>[];
    for (var index = 1; index <= 21; index++) {
      final now = UtcInstant.fromEpochMicroseconds(index);
      final transaction = LedgerTransaction(
        id: EntityId.generate(),
        vaultId: vaultId,
        type: LedgerTransactionType.openingBalance,
        status: LedgerTransactionStatus.cleared,
        financialDate: LocalDate(2026, 8, index),
        movements: [
          LedgerMovement(
            id: EntityId.generate(),
            pocket: LedgerPocket(
              id: pocketId,
              currency: CurrencyCode.brl,
              nature: AccountNature.asset,
            ),
            amountMinor: index * 100,
            sortOrder: 0,
          ),
        ],
        splits: const [],
        title: 'Opening $index',
        createdAt: now,
        updatedAt: now,
      );
      await ledger.save(transaction);
      transactions.add(transaction);
    }

    final oldest = transactions.first;
    expect(
      (await ledger.listRecentForVault(
        vaultId,
      )).map((transaction) => transaction.id),
      isNot(contains(oldest.id)),
    );
    final detail = await ledger.findActiveForVault(oldest.id, vaultId);
    expect(detail?.title, 'Opening 1');
    expect(detail?.movements.single.amountMinor, 100);
    expect(await ledger.findActiveForVault(oldest.id, otherVaultId), isNull);
    expect(
      await ledger.findActiveForVault(EntityId.generate(), vaultId),
      isNull,
    );

    await ledger.save(
      oldest.softDelete(at: const UtcInstant.fromEpochMicroseconds(100)),
    );
    expect(await ledger.findActiveForVault(oldest.id, vaultId), isNull);
    expect((await ledger.find(oldest.id))?.deletedAt, isNotNull);
  });
}
