import 'package:drift/native.dart';
import 'package:equis/infrastructure/persistence/dao/ledger_balance_reader.dart';
import 'package:equis/infrastructure/persistence/dao/transaction_aggregate_loader.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'transaction aggregate loads every atomic sync child and rebuilds balance',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _insertAggregateFixture(database);

      final aggregate = await TransactionAggregateLoader(database).load('txn');
      expect(aggregate, isNotNull);
      expect(aggregate!.movements, hasLength(2));
      expect(aggregate.splits, hasLength(1));
      expect(aggregate.tags, hasLength(1));
      expect(aggregate.fxConversions, hasLength(1));
      expect(aggregate.investmentEvents, hasLength(2));
      expect(aggregate.lotDisposals, hasLength(1));

      expect(await LedgerBalanceReader(database).rebuildAll(), {
        'pocket': 7500,
      });
      await database.customStatement(
        'UPDATE account_movements SET amount_minor = 3000 WHERE id = ?',
        ['movement-out'],
      );
      expect(await LedgerBalanceReader(database).rebuildAll(), {
        'pocket': 13000,
      });
    },
  );
}

Future<void> _insertAggregateFixture(EquisDatabase db) async {
  await db.transaction(() async {
    await db.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('vault', 'Vault', 'BRL', 'America/Sao_Paulo', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'currency.brl', 'R\$', 2)",
    );
    await db.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES ('account', 'vault', 'Cash', 'cash', 'asset', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code) VALUES ('pocket', 'account', 'BRL')",
    );
    await db.customStatement(
      "INSERT INTO categories (id, vault_id, category_type, custom_name, created_at, updated_at) VALUES ('category', 'vault', 'expense', 'Food', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO tags (id, vault_id, name, created_at, updated_at) VALUES ('tag', 'vault', 'Daily', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO transactions (id, vault_id, transaction_type, financial_date, created_at, updated_at) VALUES ('txn', 'vault', 'expense', '2026-08-13', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor, sort_order) VALUES ('movement-in', 'txn', 'pocket', 10000, 0)",
    );
    await db.customStatement(
      "INSERT INTO account_movements (id, transaction_id, account_pocket_id, amount_minor, sort_order) VALUES ('movement-out', 'txn', 'pocket', -2500, 1)",
    );
    await db.customStatement(
      "INSERT INTO transaction_splits (id, transaction_id, category_id, currency_code, amount_minor) VALUES ('split', 'txn', 'category', 'BRL', 2500)",
    );
    await db.customStatement(
      "INSERT INTO transaction_tags (transaction_id, tag_id) VALUES ('txn', 'tag')",
    );
    await db.customStatement(
      "INSERT INTO fx_conversions (id, transaction_id, from_movement_id, to_movement_id, exchange_rate, rate_source) VALUES ('fx', 'txn', 'movement-out', 'movement-in', '5.43', 'manual')",
    );
    await db.customStatement(
      "INSERT INTO investment_instruments (id, vault_id, name, asset_class, currency_code, created_at, updated_at) VALUES ('instrument', 'vault', 'Fund', 'fund', 'BRL', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO investment_events (id, transaction_id, instrument_id, event_type, quantity) VALUES ('event-buy', 'txn', 'instrument', 'buy', '10.5')",
    );
    await db.customStatement(
      "INSERT INTO investment_events (id, transaction_id, instrument_id, event_type, quantity) VALUES ('event-sell', 'txn', 'instrument', 'sell', '1.5')",
    );
    await db.customStatement(
      "INSERT INTO investment_lots (id, acquisition_event_id, instrument_id, acquired_on, original_quantity, cost_basis_minor, cost_currency_code) VALUES ('lot', 'event-buy', 'instrument', '2026-08-13', '10.5', 10000, 'BRL')",
    );
    await db.customStatement(
      "INSERT INTO investment_lot_disposals (id, disposal_event_id, lot_id, quantity, allocated_cost_minor) VALUES ('disposal', 'event-sell', 'lot', '1.5', 1500)",
    );
  });
}
