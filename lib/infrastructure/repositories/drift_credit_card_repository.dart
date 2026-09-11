import 'package:drift/drift.dart';

import '../../application/ports/credit_card_repository.dart';
import '../../domain/credit_cards/credit_card_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart'
    hide
        CreditCardLimit,
        CreditCardProfile,
        CreditCardStatement,
        InstallmentPlan;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftCreditCardRepository implements CreditCardRepository {
  const DriftCreditCardRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> saveProfile(CreditCardProfile profile) async {
    final root = await _accountRoot(profile.accountId.value);
    await _mutateAccountAggregate(
      root: root,
      action: () => database.customStatement(
        'INSERT INTO credit_card_profiles '
        '(account_id, default_closing_day, default_due_day) VALUES (?, ?, ?) '
        'ON CONFLICT(account_id) DO UPDATE SET '
        'default_closing_day = excluded.default_closing_day, '
        'default_due_day = excluded.default_due_day',
        [
          profile.accountId.value,
          profile.defaultClosingDay,
          profile.defaultDueDay,
        ],
      ),
    );
  }

  @override
  Future<CreditCardProfile?> findProfile(EntityId accountId) async {
    final rows = await _rows(
      'SELECT * FROM credit_card_profiles WHERE account_id = ?',
      [accountId.value],
      readsFrom: {database.creditCardProfiles},
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CreditCardProfile(
      accountId: accountId,
      defaultClosingDay: row['default_closing_day']! as int,
      defaultDueDay: row['default_due_day']! as int,
    );
  }

  @override
  Future<void> saveLimit(CreditCardLimit limit) async {
    final root = await _accountRootForPocket(limit.accountPocketId.value);
    await _mutateAccountAggregate(
      root: root,
      action: () => database.customStatement(
        'INSERT INTO credit_card_limits (account_pocket_id, limit_minor) '
        'VALUES (?, ?) ON CONFLICT(account_pocket_id) DO UPDATE SET '
        'limit_minor = excluded.limit_minor',
        [limit.accountPocketId.value, limit.limitMinor],
      ),
    );
  }

  Future<_AccountSyncRoot> _accountRoot(String accountId) async {
    final row = await database
        .customSelect(
          'SELECT id, vault_id, revision FROM accounts WHERE id = ?',
          variables: [Variable(accountId)],
          readsFrom: {database.accounts},
        )
        .getSingleOrNull();
    if (row == null) throw StateError('Credit-card account does not exist.');
    return _AccountSyncRoot(
      id: row.read<String>('id'),
      vaultId: row.read<String>('vault_id'),
      revision: row.read<int>('revision'),
    );
  }

  Future<_AccountSyncRoot> _accountRootForPocket(String pocketId) async {
    final row = await database
        .customSelect(
          'SELECT a.id, a.vault_id, a.revision FROM accounts a '
          'JOIN account_pockets p ON p.account_id = a.id WHERE p.id = ?',
          variables: [Variable(pocketId)],
          readsFrom: {database.accounts, database.accountPockets},
        )
        .getSingleOrNull();
    if (row == null) throw StateError('Credit-card pocket does not exist.');
    return _AccountSyncRoot(
      id: row.read<String>('id'),
      vaultId: row.read<String>('vault_id'),
      revision: row.read<int>('revision'),
    );
  }

  Future<void> _mutateAccountAggregate({
    required _AccountSyncRoot root,
    required Future<void> Function() action,
  }) {
    final nextRevision = root.revision + 1;
    Future<void> write() => database.transaction(() async {
      await action();
      final updated = await database.customUpdate(
        'UPDATE accounts SET revision = ?, updated_at = ? '
        'WHERE id = ? AND revision = ?',
        variables: [
          Variable(nextRevision),
          Variable(DateTime.now().toUtc().microsecondsSinceEpoch),
          Variable(root.id),
          Variable(root.revision),
        ],
        updates: {database.accounts},
      );
      if (updated != 1) {
        throw StateError('Credit-card account changed concurrently.');
      }
    });

    return syncRecorder?.run(
          vaultId: root.vaultId,
          entityType: SyncEntityType.account,
          recordId: root.id,
          newRevision: nextRevision,
          operation: SyncOperation.upsert,
          action: write,
        ) ??
        write();
  }

  @override
  Future<CreditCardLimit?> findLimit(EntityId pocketId) async {
    final rows = await _rows(
      'SELECT limit_minor FROM credit_card_limits WHERE account_pocket_id = ?',
      [pocketId.value],
      readsFrom: {database.creditCardLimits},
    );
    return rows.isEmpty
        ? null
        : CreditCardLimit(
            accountPocketId: pocketId,
            limitMinor: rows.single['limit_minor']! as int,
          );
  }

  @override
  Future<void> saveStatement(CreditCardStatement statement) =>
      syncRecorder?.run(
        vaultId: statement.vaultId.value,
        entityType: SyncEntityType.creditCardStatement,
        recordId: statement.id.value,
        newRevision: statement.revision,
        operation: statement.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _saveStatement(statement),
      ) ??
      _saveStatement(statement);

  Future<void> _saveStatement(
    CreditCardStatement statement,
  ) => database.transaction(() async {
    final rows = await _rows(
      'SELECT revision FROM credit_card_statements WHERE id = ?',
      [statement.id.value],
      readsFrom: {database.creditCardStatements},
    );
    if (rows.isEmpty) {
      if (statement.revision != 1) {
        throw CreditCardRevisionConflict(
          recordId: statement.id,
          expectedRevision: statement.revision - 1,
          actualRevision: null,
        );
      }
      await database.customStatement(
        'INSERT INTO credit_card_statements '
        '(id, vault_id, account_pocket_id, period_start, period_end, '
        'closing_date, due_date, status, revision, created_at, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          statement.id.value,
          statement.vaultId.value,
          statement.accountPocketId.value,
          statement.periodStart.toString(),
          statement.periodEnd.toString(),
          statement.closingDate.toString(),
          statement.dueDate.toString(),
          statement.status.name,
          statement.revision,
          statement.createdAt.epochMicroseconds,
          statement.updatedAt.epochMicroseconds,
          statement.deletedAt?.epochMicroseconds,
        ],
      );
      return;
    }
    final actual = rows.single['revision']! as int;
    final expected = statement.revision - 1;
    if (actual != expected) {
      throw CreditCardRevisionConflict(
        recordId: statement.id,
        expectedRevision: expected,
        actualRevision: actual,
      );
    }
    final changed = await database.customUpdate(
      'UPDATE credit_card_statements SET status = ?, revision = ?, '
      'updated_at = ?, deleted_at = ? WHERE id = ? AND revision = ?',
      variables: _variables([
        statement.status.name,
        statement.revision,
        statement.updatedAt.epochMicroseconds,
        statement.deletedAt?.epochMicroseconds,
        statement.id.value,
        expected,
      ]),
      updates: {database.creditCardStatements},
    );
    if (changed != 1) {
      throw CreditCardRevisionConflict(
        recordId: statement.id,
        expectedRevision: expected,
        actualRevision: actual,
      );
    }
  });

  @override
  Future<CreditCardStatement?> findStatementForDate(
    EntityId pocketId,
    LocalDate date,
  ) async {
    final rows = await _rows(
      'SELECT * FROM credit_card_statements '
      'WHERE account_pocket_id = ? AND period_start <= ? AND period_end >= ? '
      'AND deleted_at IS NULL ORDER BY closing_date LIMIT 1',
      [pocketId.value, date.toString(), date.toString()],
      readsFrom: {database.creditCardStatements},
    );
    return rows.isEmpty ? null : _statement(rows.single);
  }

  @override
  Future<List<CreditCardStatement>> listStatements(EntityId pocketId) async {
    final rows = await _rows(
      'SELECT * FROM credit_card_statements '
      'WHERE account_pocket_id = ? AND deleted_at IS NULL '
      'ORDER BY closing_date',
      [pocketId.value],
      readsFrom: {database.creditCardStatements},
    );
    return rows.map(_statement).toList(growable: false);
  }

  @override
  Future<CreditCardStatementAmounts> statementAmounts(
    EntityId statementId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT '
          "COALESCE(SUM(CASE WHEN parent.transaction_type IN ('credit_card_purchase', 'fee') "
          'THEN movement.amount_minor ELSE 0 END), 0) AS charges, '
          "COALESCE(SUM(CASE WHEN parent.transaction_type = 'refund' "
          'THEN -movement.amount_minor ELSE 0 END), 0) AS refunds, '
          "COALESCE(SUM(CASE WHEN parent.transaction_type = 'credit_card_payment' "
          'THEN -movement.amount_minor ELSE 0 END), 0) AS payments '
          'FROM account_movements AS movement '
          'INNER JOIN transactions AS parent ON parent.id = movement.transaction_id '
          'WHERE movement.statement_id = ? AND parent.status != ? '
          'AND parent.deleted_at IS NULL',
          variables: [
            Variable<String>(statementId.value),
            const Variable<String>('cancelled'),
          ],
          readsFrom: {database.accountMovements, database.transactions},
        )
        .getSingle();
    return CreditCardStatementAmounts(
      chargesMinor: rows.read<int>('charges'),
      refundsMinor: rows.read<int>('refunds'),
      paymentsMinor: rows.read<int>('payments'),
    );
  }

  @override
  Future<int> outstandingMinor(EntityId pocketId) async {
    final row = await database
        .customSelect(
          'SELECT COALESCE(SUM(movement.amount_minor), 0) AS outstanding '
          'FROM account_movements AS movement '
          'INNER JOIN transactions AS parent ON parent.id = movement.transaction_id '
          'WHERE movement.account_pocket_id = ? AND parent.status != ? '
          'AND parent.deleted_at IS NULL',
          variables: [
            Variable<String>(pocketId.value),
            const Variable<String>('cancelled'),
          ],
          readsFrom: {database.accountMovements, database.transactions},
        )
        .getSingle();
    return row.read<int>('outstanding');
  }

  @override
  Future<void> saveInstallmentPlan(InstallmentPlanView value) =>
      syncRecorder?.run(
        vaultId: value.plan.vaultId.value,
        entityType: SyncEntityType.installmentPlan,
        recordId: value.plan.id.value,
        newRevision: value.plan.revision,
        operation: value.plan.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _saveInstallmentPlan(value),
      ) ??
      _saveInstallmentPlan(value);

  Future<void> _saveInstallmentPlan(InstallmentPlanView value) =>
      database.transaction(() async {
        final plan = value.plan;
        final rows = await _rows(
          'SELECT revision FROM installment_plans WHERE id = ?',
          [plan.id.value],
          readsFrom: {database.installmentPlans},
        );
        if (rows.isNotEmpty) {
          throw StateError('Installment plans are immutable after creation.');
        }
        await database.customStatement(
          'INSERT INTO installment_plans '
          '(id, vault_id, account_pocket_id, counterparty_id, category_id, '
          'description, currency_code, total_minor, installment_count, '
          'first_installment_date, interest_rate, recognition_mode, status, '
          'revision, created_at, updated_at, deleted_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            plan.id.value,
            plan.vaultId.value,
            plan.accountPocketId.value,
            plan.counterpartyId?.value,
            plan.categoryId?.value,
            plan.description,
            plan.currency.value,
            plan.totalMinor,
            plan.installmentCount,
            plan.firstInstallmentDate.toString(),
            plan.interestRate,
            plan.recognitionMode,
            plan.status.name,
            plan.revision,
            plan.createdAt.epochMicroseconds,
            plan.updatedAt.epochMicroseconds,
            plan.deletedAt?.epochMicroseconds,
          ],
        );
        for (final item in value.items) {
          await saveInstallment(item);
        }
      });

  @override
  Future<void> saveInstallment(
    CardInstallment item,
  ) => database.customStatement(
    'INSERT INTO installments '
    '(id, installment_plan_id, installment_number, amount_minor, expected_date, '
    'transaction_id, statement_id, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(id) DO UPDATE SET transaction_id = excluded.transaction_id, '
    'statement_id = excluded.statement_id, status = excluded.status',
    [
      item.id.value,
      item.installmentPlanId.value,
      item.installmentNumber,
      item.amountMinor,
      item.expectedDate.toString(),
      item.transactionId?.value,
      item.statementId?.value,
      item.status.name,
    ],
  );

  @override
  Future<void> updateInstallmentPlanStatus(
    InstallmentPlan plan,
    InstallmentPlanStatus status, {
    required UtcInstant at,
  }) =>
      syncRecorder?.run(
        vaultId: plan.vaultId.value,
        entityType: SyncEntityType.installmentPlan,
        recordId: plan.id.value,
        newRevision: plan.revision + 1,
        operation: plan.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _updateInstallmentPlanStatus(plan, status, at: at),
      ) ??
      _updateInstallmentPlanStatus(plan, status, at: at);

  Future<void> _updateInstallmentPlanStatus(
    InstallmentPlan plan,
    InstallmentPlanStatus status, {
    required UtcInstant at,
  }) async {
    final changed = await database.customUpdate(
      'UPDATE installment_plans SET status = ?, revision = ?, updated_at = ? '
      'WHERE id = ? AND revision = ?',
      variables: _variables([
        status.name,
        plan.revision + 1,
        at.epochMicroseconds,
        plan.id.value,
        plan.revision,
      ]),
      updates: {database.installmentPlans},
    );
    if (changed != 1) {
      final rows = await _rows(
        'SELECT revision FROM installment_plans WHERE id = ?',
        [plan.id.value],
        readsFrom: {database.installmentPlans},
      );
      throw CreditCardRevisionConflict(
        recordId: plan.id,
        expectedRevision: plan.revision,
        actualRevision: rows.isEmpty ? null : rows.single['revision']! as int,
      );
    }
  }

  @override
  Future<InstallmentPlanView?> findInstallmentPlan(EntityId id) async {
    final plans = await _rows(
      'SELECT * FROM installment_plans WHERE id = ? AND deleted_at IS NULL',
      [id.value],
      readsFrom: {database.installmentPlans},
    );
    if (plans.isEmpty) return null;
    return _planView(plans.single);
  }

  @override
  Future<List<InstallmentPlanView>> listInstallmentPlans(
    EntityId pocketId,
  ) async {
    final plans = await _rows(
      'SELECT * FROM installment_plans '
      'WHERE account_pocket_id = ? AND deleted_at IS NULL '
      'ORDER BY first_installment_date DESC',
      [pocketId.value],
      readsFrom: {database.installmentPlans},
    );
    final result = <InstallmentPlanView>[];
    for (final plan in plans) {
      result.add(await _planView(plan));
    }
    return result;
  }

  Future<InstallmentPlanView> _planView(Map<String, Object?> row) async {
    final id = EntityId.parse(row['id']! as String);
    final itemRows = await _rows(
      'SELECT * FROM installments WHERE installment_plan_id = ? '
      'ORDER BY installment_number',
      [id.value],
      readsFrom: {database.installments},
    );
    final plan = InstallmentPlan(
      id: id,
      vaultId: EntityId.parse(row['vault_id']! as String),
      accountPocketId: EntityId.parse(row['account_pocket_id']! as String),
      counterpartyId: row['counterparty_id'] == null
          ? null
          : EntityId.parse(row['counterparty_id']! as String),
      categoryId: row['category_id'] == null
          ? null
          : EntityId.parse(row['category_id']! as String),
      description: row['description'] as String?,
      currency: CurrencyCode(row['currency_code']! as String),
      totalMinor: row['total_minor']! as int,
      installmentCount: row['installment_count']! as int,
      firstInstallmentDate: LocalDate.parse(
        row['first_installment_date']! as String,
      ),
      interestRate: row['interest_rate'] as String?,
      recognitionMode: row['recognition_mode']! as String,
      status: InstallmentPlanStatus.values.byName(row['status']! as String),
      revision: row['revision']! as int,
      createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
      updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
      deletedAt: row['deleted_at'] == null
          ? null
          : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
    );
    return InstallmentPlanView(
      plan: plan,
      items: [
        for (final item in itemRows)
          CardInstallment(
            id: EntityId.parse(item['id']! as String),
            installmentPlanId: id,
            installmentNumber: item['installment_number']! as int,
            amountMinor: item['amount_minor']! as int,
            expectedDate: LocalDate.parse(item['expected_date']! as String),
            transactionId: item['transaction_id'] == null
                ? null
                : EntityId.parse(item['transaction_id']! as String),
            statementId: item['statement_id'] == null
                ? null
                : EntityId.parse(item['statement_id']! as String),
            status: InstallmentStatus.values.byName(item['status']! as String),
          ),
      ],
    );
  }

  CreditCardStatement _statement(Map<String, Object?> row) =>
      CreditCardStatement(
        id: EntityId.parse(row['id']! as String),
        vaultId: EntityId.parse(row['vault_id']! as String),
        accountPocketId: EntityId.parse(row['account_pocket_id']! as String),
        periodStart: LocalDate.parse(row['period_start']! as String),
        periodEnd: LocalDate.parse(row['period_end']! as String),
        closingDate: LocalDate.parse(row['closing_date']! as String),
        dueDate: LocalDate.parse(row['due_date']! as String),
        status: CreditCardStatementStatus.values.byName(
          row['status']! as String,
        ),
        revision: row['revision']! as int,
        createdAt: UtcInstant.fromEpochMicroseconds(row['created_at']! as int),
        updatedAt: UtcInstant.fromEpochMicroseconds(row['updated_at']! as int),
        deletedAt: row['deleted_at'] == null
            ? null
            : UtcInstant.fromEpochMicroseconds(row['deleted_at']! as int),
      );

  Future<List<Map<String, Object?>>> _rows(
    String sql,
    List<Object?> values, {
    Set<ResultSetImplementation> readsFrom = const {},
  }) => database
      .customSelect(sql, variables: _variables(values), readsFrom: readsFrom)
      .get()
      .then(
        (rows) => rows
            .map((row) => Map<String, Object?>.from(row.data))
            .toList(growable: false),
      );
}

final class _AccountSyncRoot {
  const _AccountSyncRoot({
    required this.id,
    required this.vaultId,
    required this.revision,
  });

  final String id;
  final String vaultId;
  final int revision;
}

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map((value) => Variable<Object>(value)).toList(growable: false);
