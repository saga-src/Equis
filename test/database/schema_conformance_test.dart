import 'package:drift/native.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EquisDatabase database;

  setUp(() => database = EquisDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('fresh database has every locked local table and index', () async {
    await database.customSelect('SELECT 1').getSingle();
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    expect(
      tables.map((row) => row.read<String>('name')).toSet(),
      equals(_expectedTables),
    );

    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL ORDER BY name",
        )
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')).toSet(),
      equals(_expectedIndexes),
    );
  });

  test('foreign keys and busy timeout are enabled', () async {
    expect(
      (await database.customSelect('PRAGMA foreign_keys').getSingle())
          .read<int>('foreign_keys'),
      1,
    );
    expect(
      (await database.customSelect('PRAGMA busy_timeout').getSingle())
          .read<int>('timeout'),
      5000,
    );
  });

  test('accounts and pockets have no authoritative balance column', () async {
    for (final table in ['accounts', 'account_pockets']) {
      final columns = await database
          .customSelect('PRAGMA table_info($table)')
          .get();
      expect(
        columns
            .map((row) => row.read<String>('name'))
            .where((name) => name.contains('balance')),
        isEmpty,
      );
    }
  });

  test(
    'derived financial truth is not persisted as competing totals',
    () async {
      final forbidden = <String, Set<String>>{
        'accounts': {'balance', 'balance_minor', 'available_minor'},
        'account_pockets': {'balance', 'balance_minor', 'available_minor'},
        'credit_card_statements': {
          'total_minor',
          'balance_minor',
          'paid_minor',
        },
        'budgets': {'used_minor', 'remaining_minor', 'percentage'},
        'goals': {'current_minor', 'remaining_minor', 'percentage'},
        'assets': {'current_value_minor', 'net_worth_minor'},
        'investment_lots': {'remaining_quantity', 'market_value_minor'},
      };
      for (final entry in forbidden.entries) {
        final columns = await database
            .customSelect('PRAGMA table_info(${entry.key})')
            .get();
        final names = columns.map((row) => row.read<String>('name')).toSet();
        expect(
          names.intersection(entry.value),
          isEmpty,
          reason: '${entry.key} must not persist derived financial truth.',
        );
      }
    },
  );

  test('foreign-key and unique constraints reject invalid writes', () async {
    await database.customSelect('SELECT 1').getSingle();
    await expectLater(
      database.customStatement(
        "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES ('a', 'missing', 'Cash', 'cash', 'asset', 1, 1)",
      ),
      throwsA(anything),
    );
    await database.customStatement(
      "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('v', 'Vault', 'BRL', 'America/Sao_Paulo', 1, 1)",
    );
    await database.customStatement(
      "INSERT INTO currencies (code, name_key, symbol, minor_units) VALUES ('BRL', 'currency.brl', 'R\$', 2)",
    );
    await database.customStatement(
      "INSERT INTO accounts (id, vault_id, name, account_type, nature, created_at, updated_at) VALUES ('a', 'v', 'Cash', 'cash', 'asset', 1, 1)",
    );
    await database.customStatement(
      "INSERT INTO account_pockets (id, account_id, currency_code) VALUES ('p1', 'a', 'BRL')",
    );
    await expectLater(
      database.customStatement(
        "INSERT INTO account_pockets (id, account_id, currency_code) VALUES ('p2', 'a', 'BRL')",
      ),
      throwsA(anything),
    );
  });
}

const _expectedTables = <String>{
  'vaults',
  'devices',
  'vault_cloud_bindings',
  'currencies',
  'accounts',
  'account_pockets',
  'categories',
  'tags',
  'counterparties',
  'counterparty_aliases',
  'transactions',
  'account_movements',
  'transaction_splits',
  'transaction_tags',
  'fx_conversions',
  'recurring_rules',
  'recurring_templates',
  'recurring_template_movements',
  'recurring_template_splits',
  'credit_card_profiles',
  'credit_card_limits',
  'credit_card_statements',
  'installment_plans',
  'installments',
  'budgets',
  'budget_categories',
  'budget_accounts',
  'budget_tags',
  'goals',
  'goal_accounts',
  'goal_contributions',
  'assets',
  'asset_valuations',
  'investment_instruments',
  'investment_events',
  'investment_lots',
  'investment_lot_disposals',
  'fx_rate_cache',
  'manual_fx_rates',
  'market_price_cache',
  'manual_market_prices',
  'attachments',
  'attachment_links',
  'sync_entity_state',
  'sync_outbox',
  'sync_activity_events',
  'sync_cursors',
  'sync_conflicts',
  'device_preferences',
  'vault_preferences',
};

const _expectedIndexes = <String>{
  'idx_transactions_vault_date',
  'idx_movements_pocket',
  'idx_categories_parent',
  'idx_counterparties_name',
  'idx_statements_account_due',
  'idx_goals_status',
  'idx_investment_events_instrument',
  'idx_sync_outbox_retry',
  'idx_transactions_vault_history',
  'idx_sync_activity_time',
  'idx_transactions_vault_type_status_date',
  'idx_movements_amount',
  'idx_splits_category',
  'idx_transaction_tags_tag',
  'idx_pockets_currency',
  'idx_transactions_recurrence',
  'idx_recurring_rules_vault_next',
};
