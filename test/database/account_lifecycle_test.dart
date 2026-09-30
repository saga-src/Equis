import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:equis/application/services/local_finance_container_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/account_removal_assessment.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/drift_local_unit_of_work.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart';
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_ledger_repository.dart';
import 'package:equis/infrastructure/portability/vault_logical_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = UtcInstant.fromEpochMicroseconds(1786636800123456);

void main() {
  for (final pending in [false, true]) {
    test(
      '${pending ? 'pending' : 'future'} transactions block even with zero balances',
      () async {
        final db = EquisDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final service = _service(db);
        final vaultId = await _vault(service);
        final account = await _account(service, vaultId);
        for (final amount in [100, -100]) {
          await _movement(
            db,
            vaultId,
            account.pockets.single.id,
            amount,
            status: pending ? 'pending' : 'cleared',
            financialDate: pending ? '2026-08-12' : '2026-08-14',
          );
        }
        final assessment = await service.assessAccountRemoval(
          vaultId: vaultId,
          accountId: account.account.id,
          now: _now,
        );
        expect(assessment.balances.single.minorUnits, 0);
        expect(assessment.blockers, {AccountRemovalBlocker.pendingTransaction});
        await expectLater(
          service.removeAccount(
            vaultId: vaultId,
            accountId: account.account.id,
            expectedRevision: 1,
            now: _now,
          ),
          throwsA(isA<AccountRemovalBlocked>()),
        );
        expect(
          (await DriftAccountAggregateRepository(
            db,
          ).findAggregate(account.account.id))!.account.archived,
          isFalse,
        );
      },
    );
  }

  test(
    'logical backup preserves archived history and empty card tombstone children',
    () async {
      final source = EquisDatabase(NativeDatabase.memory());
      final target = EquisDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      addTearDown(target.close);
      final service = _service(source);
      final vaultId = await _vault(service);
      final used = await _account(service, vaultId);
      final card = await _account(service, vaultId, card: true);
      await _movement(source, vaultId, used.pockets.single.id, 100);
      await _movement(source, vaultId, used.pockets.single.id, -100);
      await source.customStatement(
        'INSERT INTO credit_card_profiles '
        '(account_id, default_closing_day, default_due_day) VALUES (?, 5, 15)',
        [card.account.id.value],
      );
      await source.customStatement(
        'INSERT INTO credit_card_limits '
        '(account_pocket_id, limit_minor) VALUES (?, 10000)',
        [card.pockets.single.id.value],
      );
      for (final aggregate in [used, card]) {
        await service.removeAccount(
          vaultId: vaultId,
          accountId: aggregate.account.id,
          expectedRevision: 1,
          now: _now,
        );
      }
      final snapshot = await VaultLogicalSnapshotStore(
        source,
      ).capture(vaultId.value);
      await VaultLogicalSnapshotStore(
        target,
      ).restore(VaultLogicalSnapshot.fromJson(snapshot.toJson()));
      final accounts = DriftAccountAggregateRepository(target);
      final historic = (await accounts.findAggregate(used.account.id))!;
      final deleted = (await accounts.findAggregate(card.account.id))!;
      expect(historic.account.archived, isTrue);
      expect(historic.account.closedOn.toString(), '2026-08-13');
      expect(deleted.account.deletedAt, _now);
      expect(deleted.pockets.single.id, card.pockets.single.id);
      expect(
        await target.customSelect('SELECT * FROM account_movements').get(),
        hasLength(2),
      );
      expect(
        await target.customSelect('SELECT * FROM credit_card_profiles').get(),
        hasLength(1),
      );
      expect(
        await target.customSelect('SELECT * FROM credit_card_limits').get(),
        hasLength(1),
      );
      expect(
        await target.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      await _service(target).restoreAccount(
        vaultId: vaultId,
        accountId: used.account.id,
        expectedRevision: 2,
        now: _now,
      );
      expect(
        (await accounts.findAggregate(used.account.id))!.account.closedOn,
        isNull,
      );
    },
  );

  test(
    'generic account save rejects stale state and lifecycle bypasses',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _service(db);
      final vaultId = await _vault(service);
      final original = await _account(service, vaultId);
      final accounts = DriftAccountAggregateRepository(db);
      await expectLater(
        accounts.save(
          original.withAccount(
            original.account.revise(archived: true, at: _now),
          ),
        ),
        throwsA(isA<AccountLifecycleConflict>()),
      );
      final edited = await service.setNetWorthInclusion(
        original,
        false,
        now: _now,
      );
      await accounts.save(edited);
      await expectLater(
        service.setNetWorthInclusion(original, true, now: _now),
        throwsA(isA<AccountLifecycleConflict>()),
      );
      await service.removeAccount(
        vaultId: vaultId,
        accountId: original.account.id,
        expectedRevision: 2,
        now: _now,
      );
      await expectLater(
        accounts.save(
          edited.withAccount(
            edited.account.revise(name: 'Stale edit', at: _now),
          ),
        ),
        throwsA(isA<AccountLifecycleConflict>()),
      );
      expect(
        (await accounts.findAggregate(original.account.id))!.account.deletedAt,
        isNotNull,
      );
    },
  );

  test('closing date and future checks use the vault timezone', () async {
    final db = EquisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _service(db);
    final vaultId = await _vault(service);
    await db.customStatement(
      "UPDATE vaults SET timezone = 'America/Sao_Paulo' WHERE id = ?",
      [vaultId.value],
    );
    final account = await _account(service, vaultId);
    await _movement(db, vaultId, account.pockets.single.id, 100);
    await _movement(db, vaultId, account.pockets.single.id, -100);
    final instant = UtcInstant.fromEpochMicroseconds(
      DateTime.utc(2026, 8, 13, 1).microsecondsSinceEpoch,
    );
    final result = await service.removeAccount(
      vaultId: vaultId,
      accountId: account.account.id,
      expectedRevision: 1,
      now: instant,
    );
    expect(result.aggregate.account.closedOn?.toString(), '2026-08-12');
  });

  test(
    'empty account becomes a tombstone retaining pocket IDs and card rows',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _service(db);
      final vaultId = await _vault(service);
      final account = await _account(service, vaultId, card: true);
      await db.customStatement(
        'INSERT INTO credit_card_profiles '
        '(account_id, default_closing_day, default_due_day) VALUES (?, 5, 15)',
        [account.account.id.value],
      );
      final originalPocketIds = account.pockets.map((p) => p.id).toSet();

      final assessment = await service.assessAccountRemoval(
        vaultId: vaultId,
        accountId: account.account.id,
        now: _now,
      );
      expect(assessment.disposition, AccountRemovalDisposition.delete);
      expect(assessment.balances.map((b) => b.minorUnits), everyElement(0));

      final result = await service.removeAccount(
        vaultId: vaultId,
        accountId: account.account.id,
        expectedRevision: 1,
        now: _now,
      );
      expect(result.disposition, AccountRemovalDisposition.delete);
      expect(result.aggregate.account.deletedAt, _now);
      expect(result.aggregate.account.revision, 2);
      expect(
        result.aggregate.pockets.map((p) => p.id).toSet(),
        originalPocketIds,
      );
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS count FROM credit_card_profiles WHERE account_id = ?',
                  variables: [Variable(account.account.id.value)],
                )
                .getSingle())
            .read<int>('count'),
        1,
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      await expectLater(
        service.removeAccount(
          vaultId: vaultId,
          accountId: account.account.id,
          expectedRevision: 1,
          now: _now,
        ),
        throwsA(isA<AccountLifecycleConflict>()),
      );
    },
  );

  test(
    'zeroed historical movements archive, then restore clears closedOn',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _service(db);
      final vaultId = await _vault(service);
      final account = await _account(service, vaultId);
      await _movement(db, vaultId, account.pockets.first.id, 100);
      await _movement(db, vaultId, account.pockets.first.id, -100);

      final result = await service.removeAccount(
        vaultId: vaultId,
        accountId: account.account.id,
        expectedRevision: 1,
        now: _now,
      );
      expect(result.disposition, AccountRemovalDisposition.archive);
      expect(result.aggregate.account.archived, isTrue);
      expect(result.aggregate.account.deletedAt, isNull);
      expect(result.aggregate.account.closedOn?.toString(), '2026-08-13');
      expect(result.assessment.references[AccountReferenceKind.movements], 2);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      final restored = await service.restoreAccount(
        vaultId: vaultId,
        accountId: account.account.id,
        expectedRevision: 2,
        now: _now,
      );
      expect(restored.account.archived, isFalse);
      expect(restored.account.closedOn, isNull);
      expect(restored.account.revision, 3);
      expect(
        restored.pockets.map((p) => p.id),
        result.aggregate.pockets.map((p) => p.id),
      );
    },
  );

  test(
    'balances in different pockets never cancel and stale revision loses',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _service(db);
      final vaultId = await _vault(service);
      final account = await _account(
        service,
        vaultId,
        currencies: [CurrencyCode.brl, CurrencyCode.usd],
      );
      await _movement(db, vaultId, account.pockets[0].id, 100);
      await _movement(db, vaultId, account.pockets[1].id, -100);

      final assessment = await service.assessAccountRemoval(
        vaultId: vaultId,
        accountId: account.account.id,
        now: _now,
      );
      expect(assessment.disposition, AccountRemovalDisposition.blocked);
      expect(
        assessment.blockers,
        contains(AccountRemovalBlocker.pocketBalance),
      );
      expect(assessment.balances.map((b) => b.minorUnits).toSet(), {100, -100});
      await expectLater(
        service.removeAccount(
          vaultId: vaultId,
          accountId: account.account.id,
          expectedRevision: 1,
          now: _now,
        ),
        throwsA(isA<AccountRemovalBlocked>()),
      );

      final otherVaultId = await _vault(service);
      await expectLater(
        service.assessAccountRemoval(
          vaultId: otherVaultId,
          accountId: account.account.id,
          now: _now,
        ),
        throwsA(isA<AccountLifecycleConflict>()),
      );
    },
  );

  test(
    'attachment reference archives and concurrent revision is conditional',
    () async {
      final db = EquisDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = _service(db);
      final vaultId = await _vault(service);
      final account = await _account(service, vaultId);
      final attachmentId = EntityId.generate();
      await db.customStatement(
        'INSERT INTO attachments (id, vault_id, byte_size, sha256, created_at, updated_at) '
        "VALUES (?, ?, 0, 'hash', ?, ?)",
        [
          attachmentId.value,
          vaultId.value,
          _now.epochMicroseconds,
          _now.epochMicroseconds,
        ],
      );
      await db.customStatement(
        "INSERT INTO attachment_links (attachment_id, entity_type, entity_id) VALUES (?, 'account', ?)",
        [attachmentId.value, account.account.id.value],
      );
      final attempts = await Future.wait([
        service
            .removeAccount(
              vaultId: vaultId,
              accountId: account.account.id,
              expectedRevision: 1,
              now: _now,
            )
            .then<Object>((value) => value, onError: (Object error) => error),
        service
            .removeAccount(
              vaultId: vaultId,
              accountId: account.account.id,
              expectedRevision: 1,
              now: _now,
            )
            .then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(attempts.whereType<AccountLifecycleResult>(), hasLength(1));
      expect(attempts.whereType<AccountLifecycleConflict>(), hasLength(1));
      expect(
        (attempts.whereType<AccountLifecycleResult>().single).disposition,
        AccountRemovalDisposition.archive,
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test('open obligations and enabled links block removal', () async {
    final db = EquisDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _service(db);
    final vaultId = await _vault(service);
    final account = await _account(service, vaultId, card: true);
    final pocketId = account.pockets.single.id;
    final statementId = EntityId.generate();
    await db.customStatement(
      'INSERT INTO credit_card_statements '
      '(id, vault_id, account_pocket_id, period_start, period_end, '
      'closing_date, due_date, status, created_at, updated_at) '
      "VALUES (?, ?, ?, '2026-08-01', '2026-08-31', '2026-09-01', "
      "'2026-09-10', 'open', ?, ?)",
      [
        statementId.value,
        vaultId.value,
        pocketId.value,
        _now.epochMicroseconds,
        _now.epochMicroseconds,
      ],
    );
    await _movement(db, vaultId, pocketId, 100, statementId: statementId);
    await _movement(db, vaultId, pocketId, -100);
    final planId = EntityId.generate();
    await db.customStatement(
      'INSERT INTO installment_plans '
      '(id, vault_id, account_pocket_id, currency_code, total_minor, '
      'installment_count, first_installment_date, created_at, updated_at) '
      "VALUES (?, ?, ?, 'BRL', 100, 1, '2026-09-01', ?, ?)",
      [
        planId.value,
        vaultId.value,
        pocketId.value,
        _now.epochMicroseconds,
        _now.epochMicroseconds,
      ],
    );
    await db.customStatement(
      'INSERT INTO installments '
      '(id, installment_plan_id, installment_number, amount_minor, expected_date) '
      "VALUES (?, ?, 1, 100, '2026-09-01')",
      [EntityId.generate().value, planId.value],
    );
    final ruleId = EntityId.generate();
    await db.customStatement(
      'INSERT INTO recurring_rules '
      '(id, vault_id, name, rrule, timezone, starts_on, created_at, updated_at) '
      "VALUES (?, ?, 'Rule', 'FREQ=MONTHLY', 'UTC', '2026-08-01', ?, ?)",
      [
        ruleId.value,
        vaultId.value,
        _now.epochMicroseconds,
        _now.epochMicroseconds,
      ],
    );
    await db.customStatement(
      'INSERT INTO recurring_template_movements '
      '(id, recurring_rule_id, account_pocket_id, amount_minor) '
      'VALUES (?, ?, ?, 10)',
      [EntityId.generate().value, ruleId.value, pocketId.value],
    );
    final goalId = EntityId.generate();
    await db.customStatement(
      'INSERT INTO goals '
      '(id, vault_id, name, goal_type, currency_code, target_minor, '
      'tracking_mode, created_at, updated_at) '
      "VALUES (?, ?, 'Goal', 'savings', 'BRL', 100, 'manual', ?, ?)",
      [
        goalId.value,
        vaultId.value,
        _now.epochMicroseconds,
        _now.epochMicroseconds,
      ],
    );
    await db.customStatement(
      'INSERT INTO goal_accounts (goal_id, account_pocket_id) VALUES (?, ?)',
      [goalId.value, pocketId.value],
    );
    final budgetId = EntityId.generate();
    await db.customStatement(
      'INSERT INTO budgets '
      '(id, vault_id, name, currency_code, limit_minor, period_type, '
      'created_at, updated_at) '
      "VALUES (?, ?, 'Budget', 'BRL', 100, 'monthly', ?, ?)",
      [
        budgetId.value,
        vaultId.value,
        _now.epochMicroseconds,
        _now.epochMicroseconds,
      ],
    );
    await db.customStatement(
      'INSERT INTO budget_accounts (budget_id, account_id) VALUES (?, ?)',
      [budgetId.value, account.account.id.value],
    );

    final assessment = await service.assessAccountRemoval(
      vaultId: vaultId,
      accountId: account.account.id,
      now: _now,
    );
    expect(assessment.balances.single.minorUnits, 0);
    expect(
      assessment.blockers,
      containsAll({
        AccountRemovalBlocker.openStatement,
        AccountRemovalBlocker.scheduledInstallment,
        AccountRemovalBlocker.activeRecurrence,
        AccountRemovalBlocker.activeGoal,
        AccountRemovalBlocker.enabledBudget,
      }),
    );
    expect(assessment.disposition, AccountRemovalDisposition.blocked);

    // Inactive links and cancelled movements are history, not obligations.
    await db.customStatement("UPDATE transactions SET status = 'cancelled'");
    await db.customStatement(
      "UPDATE installment_plans SET status = 'cancelled'",
    );
    await db.customStatement('UPDATE recurring_rules SET enabled = 0');
    await db.customStatement("UPDATE goals SET status = 'completed'");
    await db.customStatement('UPDATE budgets SET enabled = 0');
    final result = await service.removeAccount(
      vaultId: vaultId,
      accountId: account.account.id,
      expectedRevision: 1,
      now: _now,
    );
    expect(result.disposition, AccountRemovalDisposition.archive);
    for (final table in [
      'recurring_template_movements',
      'installment_plans',
      'credit_card_statements',
      'goal_accounts',
      'budget_accounts',
    ]) {
      expect(await db.customSelect('SELECT * FROM $table').get(), hasLength(1));
    }
    expect(
      await db.customSelect('SELECT * FROM account_movements').get(),
      hasLength(2),
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}

LocalFinanceContainerService _service(EquisDatabase db) {
  final accounts = DriftAccountAggregateRepository(db);
  return LocalFinanceContainerService(
    vaults: DriftVaultRepository(db),
    currencies: DriftCurrencyRepository(db),
    accounts: accounts,
    lifecycleAccounts: accounts,
    ledger: DriftLedgerRepository(db),
    unitOfWork: DriftLocalUnitOfWork(db),
  );
}

Future<EntityId> _vault(LocalFinanceContainerService service) async =>
    (await service.createLocalProfile(
      name: 'Vault',
      reportingCurrency: CurrencyCode.brl,
      locale: 'en-US',
      timezone: 'UTC',
      now: _now,
    )).id;

Future<AccountAggregate> _account(
  LocalFinanceContainerService service,
  EntityId vaultId, {
  bool card = false,
  List<CurrencyCode> currencies = const [],
}) => service.createAccount(
  vaultId: vaultId,
  name: 'Account',
  type: card ? AccountType.creditCard : AccountType.checking,
  nature: card ? AccountNature.liability : AccountNature.asset,
  pocketCurrencies: currencies.isEmpty ? [CurrencyCode.brl] : currencies,
  defaultCurrency: currencies.isEmpty ? CurrencyCode.brl : currencies.first,
  now: _now,
);

Future<void> _movement(
  EquisDatabase db,
  EntityId vaultId,
  EntityId pocketId,
  int amount, {
  EntityId? statementId,
  String status = 'cleared',
  String financialDate = '2026-08-12',
}) async {
  final transactionId = EntityId.generate();
  await db.customStatement(
    'INSERT INTO transactions '
    '(id, vault_id, transaction_type, status, financial_date, created_at, updated_at) '
    "VALUES (?, ?, 'adjustment', ?, ?, ?, ?)",
    [
      transactionId.value,
      vaultId.value,
      status,
      financialDate,
      _now.epochMicroseconds,
      _now.epochMicroseconds,
    ],
  );
  await db.customStatement(
    'INSERT INTO account_movements '
    '(id, transaction_id, account_pocket_id, amount_minor, statement_id) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      EntityId.generate().value,
      transactionId.value,
      pocketId.value,
      amount,
      statementId?.value,
    ],
  );
}
