import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'generated_migrations/schema.dart';

void main() {
  test(
    'v7 monthly migration preserves roots, financial rows and outbox including deleted budgets',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(7);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      raw.execute(
        "INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) VALUES ('v','Vault','BRL','America/Sao_Paulo',1,1)",
      );
      raw.execute(
        "INSERT INTO accounts (id,vault_id,name,account_type,nature,created_at,updated_at) VALUES ('a','v','Bank','checking','asset',1,1)",
      );
      raw.execute(
        "INSERT INTO budgets (id,vault_id,name,currency_code,limit_minor,period_type,revision,created_at,updated_at,deleted_at) VALUES ('b','v','Budget','BRL',100000,'monthly',9,?,?,99)",
        [DateTime.utc(2026, 8, 1, 1).microsecondsSinceEpoch, 99],
      );
      raw.execute("INSERT INTO budget_accounts VALUES ('b','a')");
      raw.execute(
        "INSERT INTO budgets (id,vault_id,name,currency_code,limit_minor,period_type,created_at,updated_at) VALUES ('weekly','v','Weekly','BRL',100,'weekly',1,1)",
      );
      raw.execute(
        "INSERT INTO transactions (id,vault_id,transaction_type,status,financial_date,created_at,updated_at) VALUES ('t','v','expense','confirmed','2026-07-15',1,1)",
      );
      raw.execute(
        "INSERT INTO sync_outbox (operation_id,vault_id,entity_type,record_id,new_revision,operation,created_at) VALUES ('op','v','budget','b',9,'delete',1)",
      );
      final before = raw
          .select('SELECT * FROM transactions')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      final db = EquisDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(
        db,
        8,
        options: const ValidationOptions(validateDropped: true),
      );
      final config = await db
          .customSelect('SELECT * FROM budget_monthly_configurations')
          .getSingle();
      expect(config.read<String>('budget_id'), 'b');
      expect(config.read<String>('month_start'), '2026-07-01');
      expect(config.read<String>('limit_method'), 'fixed');
      expect(config.read<int>('amount_minor'), 100000);
      final root = await db
          .customSelect("SELECT * FROM budgets WHERE id='b'")
          .getSingle();
      expect(root.read<int>('revision'), 9);
      expect(root.read<int>('updated_at'), 99);
      expect(root.read<int>('deleted_at'), 99);
      expect(root.read<int>('monthly_history_edited'), 0);
      expect(
        (await db.customSelect('SELECT * FROM transactions').get())
            .map((row) => row.data)
            .toList(),
        before,
      );
      expect(
        (await db
                .customSelect('SELECT new_revision FROM sync_outbox')
                .getSingle())
            .read<int>('new_revision'),
        9,
      );
      expect(
        await db.customSelect('SELECT * FROM recurring_rule_versions').get(),
        isEmpty,
      );
      expect(
        (await db
                .customSelect('SELECT account_id FROM budget_monthly_accounts')
                .getSingle())
            .read<String>('account_id'),
        'a',
      );
    },
  );

  for (final invalid in ['timezone', 'ownership']) {
    test('failed v7 migration rolls back schema and data: $invalid', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(7);
      addTearDown(schema.close);
      final raw = schema.rawDatabase;
      raw.execute(
        "INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) VALUES ('v','Vault','BRL',?,1,1)",
        [invalid == 'timezone' ? 'invalid/zone' : 'UTC'],
      );
      raw.execute(
        "INSERT INTO budgets (id,vault_id,name,currency_code,limit_minor,period_type,created_at,updated_at) VALUES ('b','v','Budget','BRL',100,'monthly',1,1)",
      );
      if (invalid == 'ownership') {
        raw.execute(
          "INSERT INTO budget_accounts VALUES ('b','missing-account')",
        );
      }
      final db = EquisDatabase(schema.newConnection());
      addTearDown(db.close);
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      expect(raw.userVersion, 7);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name='budget_monthly_configurations'",
        ),
        isEmpty,
      );
      expect(
        raw
            .select("SELECT revision FROM budgets WHERE id='b'")
            .single['revision'],
        1,
      );
    });
  }
  test('v6 upgrade adds empty private lot terms and durable sync guards', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(6);
    addTearDown(schema.close);
    schema.rawDatabase.execute(
      "INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) "
      "VALUES ('old-vault','Existing','BRL','UTC',1,1)",
    );
    schema.rawDatabase.execute(
      "INSERT INTO sync_outbox (operation_id,vault_id,entity_type,record_id,new_revision,operation,created_at) "
      "VALUES ('old-account-op','old-vault','account','old-account',2,'upsert',1)",
    );
    final db = EquisDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(
      db,
      8,
      options: const ValidationOptions(validateDropped: true),
    );
    expect(
      await db.customSelect('SELECT * FROM fixed_income_contracts').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT * FROM fixed_income_manual_values').get(),
      isEmpty,
    );
    expect(
      await db.customSelect('SELECT * FROM sync_quarantine').get(),
      isEmpty,
    );
    final dependency = await db
        .customSelect(
          "SELECT account_id FROM sync_outbox_dependencies WHERE operation_id='old-account-op'",
        )
        .getSingle();
    expect(dependency.read<String>('account_id'), 'old-account');
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });

  test(
    'v5 upgrade preserves vault and pending changes without inventing activity',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(5);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        "INSERT INTO vaults (id,name,base_currency_code,timezone,created_at,updated_at) VALUES ('v5-vault','Preserved','BRL','UTC',1,1)",
      );
      schema.rawDatabase.execute(
        "INSERT INTO sync_outbox (operation_id,vault_id,entity_type,record_id,new_revision,operation,created_at) VALUES ('pending-op','v5-vault','vault','v5-vault',7,'upsert',1)",
      );
      final db = EquisDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(
        db,
        8,
        options: const ValidationOptions(validateDropped: true),
      );
      expect(
        (await db
                .customSelect("SELECT name FROM vaults WHERE id='v5-vault'")
                .getSingle())
            .read<String>('name'),
        'Preserved',
      );
      expect(
        (await db
                .customSelect('SELECT new_revision FROM sync_outbox')
                .getSingle())
            .read<int>('new_revision'),
        7,
      );
      expect(
        await db.customSelect('SELECT * FROM sync_activity_events').get(),
        isEmpty,
      );
    },
  );
  test(
    'empty database creates and validates against the current schema',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').getSingle();
      await database.validateDatabaseSchema(
        options: const ValidationOptions(validateDropped: true),
      );
    },
  );

  test(
    'committed v1 fixture remains valid and preserves representative data',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(1);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('fixture-vault', 'Historical', 'BRL', 'America/Sao_Paulo', 1, 1)",
      );
      final database = EquisDatabase(schema.newConnection());
      addTearDown(database.close);
      await verifier.migrateAndValidate(
        database,
        8,
        options: const ValidationOptions(validateDropped: true),
      );
      final row = await database
          .customSelect("SELECT name FROM vaults WHERE id = 'fixture-vault'")
          .getSingle();
      expect(row.read<String>('name'), 'Historical');
      final indexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
          )
          .get();
      expect(
        indexes.map((row) => row.read<String>('name')),
        containsAll(const [
          'idx_transactions_vault_history',
          'idx_transactions_vault_type_status_date',
          'idx_movements_amount',
          'idx_splits_category',
          'idx_transaction_tags_tag',
          'idx_pockets_currency',
          'idx_transactions_recurrence',
          'idx_recurring_rules_vault_next',
        ]),
      );
    },
  );

  test('committed v2 schema upgrades through localized taxonomy v5', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(2);
    addTearDown(schema.close);
    final database = EquisDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(
      database,
      8,
      options: const ValidationOptions(validateDropped: true),
    );
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
        )
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')),
      containsAll(const [
        'idx_transactions_recurrence',
        'idx_recurring_rules_vault_next',
      ]),
    );
  });

  test('committed v3 outbox upgrades without losing pending work', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(3);
    addTearDown(schema.close);
    schema.rawDatabase.execute(
      "INSERT INTO sync_outbox (operation_id, vault_id, entity_type, record_id, new_revision, operation, created_at) VALUES ('op-1', 'vault-1', 'transaction', 'record-1', 2, 'upsert', 1)",
    );
    final database = EquisDatabase(schema.newConnection());
    addTearDown(database.close);

    await verifier.migrateAndValidate(
      database,
      8,
      options: const ValidationOptions(validateDropped: true),
    );

    final row = await database
        .customSelect(
          "SELECT operation_id, base_snapshot FROM sync_outbox WHERE operation_id = 'op-1'",
        )
        .getSingle();
    expect(row.read<String>('operation_id'), 'op-1');
    expect(row.readNullable<String>('base_snapshot'), isNull);
  });

  test('committed v4 taxonomy gains optional localized names', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(4);
    addTearDown(schema.close);
    final database = EquisDatabase(schema.newConnection());
    addTearDown(database.close);

    await verifier.migrateAndValidate(
      database,
      8,
      options: const ValidationOptions(validateDropped: true),
    );

    final categoryColumns = await database
        .customSelect('PRAGMA table_info(categories)')
        .get();
    final tagColumns = await database
        .customSelect('PRAGMA table_info(tags)')
        .get();
    expect(
      categoryColumns.map((row) => row.read<String>('name')),
      containsAll(['custom_name_en_us', 'custom_name_pt_br']),
    );
    expect(
      tagColumns.map((row) => row.read<String>('name')),
      containsAll(['name_en_us', 'name_pt_br']),
    );
  });

  test('a failed database mutation rolls back all statements', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await expectLater(
      database.transaction(() async {
        await database.customStatement(
          "INSERT INTO vaults (id, name, base_currency_code, timezone, created_at, updated_at) VALUES ('rollback', 'Transient', 'BRL', 'UTC', 1, 1)",
        );
        throw StateError('simulated migration failure');
      }),
      throwsStateError,
    );
    expect(
      await database
          .customSelect("SELECT id FROM vaults WHERE id = 'rollback'")
          .get(),
      isEmpty,
    );
  });

  test(
    'every historical schema survives repeated integrity validation',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      for (final version in [1, 2, 3, 4, 5, 6, 7]) {
        final schema = await verifier.schemaAt(version);
        final database = EquisDatabase(schema.newConnection());
        await verifier.migrateAndValidate(
          database,
          8,
          options: const ValidationOptions(validateDropped: true),
        );
        final integrity = await database
            .customSelect('PRAGMA integrity_check')
            .getSingle();
        final foreignKeys = await database
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(integrity.read<String>('integrity_check'), 'ok');
        expect(foreignKeys, isEmpty);
        await database.close();
        schema.close();
      }
    },
  );

  test('newer database is rejected without destructive downgrade', () async {
    final temporary = await Directory.systemTemp.createTemp('equis-newer-db-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File(
      '${temporary.path}${Platform.pathSeparator}future.sqlite',
    );
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('CREATE TABLE future_data (value TEXT NOT NULL)');
    raw.execute("INSERT INTO future_data VALUES ('preserve-me')");
    raw.execute('PRAGMA user_version = 999');
    raw.close();

    final database = EquisDatabase(NativeDatabase(file));
    await expectLater(
      database.customSelect('SELECT 1').getSingle(),
      throwsA(anything),
    );
    await database.close();

    final preserved = sqlite.sqlite3.open(file.path);
    expect(preserved.userVersion, 999);
    expect(
      preserved.select('SELECT value FROM future_data').single['value'],
      'preserve-me',
    );
    preserved.close();
  });
}
