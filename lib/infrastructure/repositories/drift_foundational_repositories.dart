import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../application/ports/foundational_repositories.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/entities/account_aggregate.dart';
import '../../domain/entities/account_removal_assessment.dart';
import '../../domain/entities/category_node.dart';
import '../../domain/entities/vault_profile.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/shared/zoned_recurrence.dart';
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
    implements AccountAggregateRepository, AccountLifecycleRepository {
  const DriftAccountAggregateRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<AccountRemovalAssessment> assessRemoval({
    required EntityId vaultId,
    required EntityId accountId,
    required UtcInstant now,
  }) => database.transaction(
    () => _assessRemoval(vaultId: vaultId, accountId: accountId, now: now),
  );

  @override
  Future<AccountLifecycleResult> remove({
    required EntityId vaultId,
    required EntityId accountId,
    required int expectedRevision,
    required UtcInstant now,
  }) async {
    final expectedDisposition = (await assessRemoval(
      vaultId: vaultId,
      accountId: accountId,
      now: now,
    )).disposition;
    Future<AccountLifecycleResult> action() => database.transaction(() async {
      final assessment = await _assessRemoval(
        vaultId: vaultId,
        accountId: accountId,
        now: now,
      );
      if (assessment.aggregate.account.revision != expectedRevision) {
        throw const AccountLifecycleConflict();
      }
      if (assessment.disposition == AccountRemovalDisposition.blocked) {
        throw AccountRemovalBlocked(assessment);
      }
      if (assessment.disposition != expectedDisposition) {
        throw const AccountLifecycleConflict();
      }
      final archive =
          assessment.disposition == AccountRemovalDisposition.archive;
      final nowDate = (await _vaultDate(vaultId, now)).toString();
      final changed = await database.customUpdate(
        'UPDATE accounts SET archived = ?, closed_on = ?, deleted_at = ?, '
        'revision = revision + 1, updated_at = ? '
        'WHERE id = ? AND vault_id = ? AND revision = ? '
        'AND archived = 0 AND deleted_at IS NULL',
        variables: [
          Variable(archive ? 1 : 0),
          Variable(archive ? nowDate : null),
          Variable(archive ? null : now.epochMicroseconds),
          Variable(now.epochMicroseconds),
          Variable(accountId.value),
          Variable(vaultId.value),
          Variable(expectedRevision),
        ],
        updates: {database.accounts},
      );
      if (changed != 1) throw const AccountLifecycleConflict();
      final revised = await findAggregate(accountId);
      if (revised == null) throw const AccountLifecycleConflict();
      return AccountLifecycleResult(aggregate: revised, assessment: assessment);
    });

    return syncRecorder?.run(
          vaultId: vaultId.value,
          entityType: SyncEntityType.account,
          recordId: accountId.value,
          newRevision: expectedRevision + 1,
          operation: expectedDisposition == AccountRemovalDisposition.delete
              ? SyncOperation.delete
              : SyncOperation.upsert,
          action: action,
        ) ??
        action();
  }

  @override
  Future<AccountAggregate> restore({
    required EntityId vaultId,
    required EntityId accountId,
    required int expectedRevision,
    required UtcInstant now,
  }) {
    Future<AccountAggregate> action() => database.transaction(() async {
      await _vaultDate(vaultId, now);
      final current = await findAggregate(accountId);
      if (current == null ||
          current.account.vaultId != vaultId ||
          current.account.deletedAt != null ||
          !current.account.archived ||
          current.account.revision != expectedRevision) {
        throw const AccountLifecycleConflict();
      }
      final changed = await database.customUpdate(
        'UPDATE accounts SET archived = 0, closed_on = NULL, '
        'revision = revision + 1, updated_at = ? '
        'WHERE id = ? AND vault_id = ? AND revision = ? '
        'AND archived = 1 AND deleted_at IS NULL',
        variables: [
          Variable(now.epochMicroseconds),
          Variable(accountId.value),
          Variable(vaultId.value),
          Variable(expectedRevision),
        ],
        updates: {database.accounts},
      );
      if (changed != 1) throw const AccountLifecycleConflict();
      final revised = await findAggregate(accountId);
      if (revised == null) throw const AccountLifecycleConflict();
      return revised;
    });

    return syncRecorder?.run(
          vaultId: vaultId.value,
          entityType: SyncEntityType.account,
          recordId: accountId.value,
          newRevision: expectedRevision + 1,
          operation: SyncOperation.upsert,
          action: action,
        ) ??
        action();
  }

  /// Read-only consistency check for a newly hydrated archived cloud snapshot.
  Future<AccountRemovalAssessment> assessArchivedSnapshot({
    required EntityId vaultId,
    required EntityId accountId,
    required UtcInstant now,
  }) => _assessRemoval(
    vaultId: vaultId,
    accountId: accountId,
    now: now,
    allowArchived: true,
  );

  Future<AccountRemovalAssessment> _assessRemoval({
    required EntityId vaultId,
    required EntityId accountId,
    required UtcInstant now,
    bool allowArchived = false,
  }) async {
    final aggregate = await findAggregate(accountId);
    if (aggregate == null ||
        aggregate.account.vaultId != vaultId ||
        aggregate.account.deletedAt != null ||
        (aggregate.account.archived && !allowArchived)) {
      throw const AccountLifecycleConflict();
    }
    final effectiveOn = await _vaultDate(vaultId, now);
    final balancesByPocket = await database
        .customSelect(
          'SELECT p.id, p.currency_code, COALESCE(SUM(CASE '
          "WHEN t.deleted_at IS NULL AND t.status != 'cancelled' "
          "AND NOT (t.status = 'pending' AND t.recurring_rule_id IS NOT NULL) "
          'THEN m.amount_minor ELSE 0 END), 0) AS balance_minor '
          'FROM account_pockets p '
          'LEFT JOIN account_movements m ON m.account_pocket_id = p.id '
          'LEFT JOIN transactions t ON t.id = m.transaction_id '
          'WHERE p.account_id = ? GROUP BY p.id, p.currency_code',
          variables: [Variable(accountId.value)],
          readsFrom: {
            database.accountPockets,
            database.accountMovements,
            database.transactions,
          },
        )
        .get();
    final balances = [
      for (final row in balancesByPocket)
        AccountPocketBalance(
          pocketId: EntityId.parse(row.read<String>('id')),
          currency: CurrencyCode(row.read<String>('currency_code')),
          minorUnits: row.read<int>('balance_minor'),
        ),
    ];
    final blockers = <AccountRemovalBlocker>{};
    if (balances.any((balance) => balance.minorUnits != 0)) {
      blockers.add(AccountRemovalBlocker.pocketBalance);
    }

    final references = <AccountReferenceKind, int>{
      AccountReferenceKind.movements: await _count(
        'SELECT COUNT(*) AS count FROM account_movements m '
        'JOIN account_pockets p ON p.id = m.account_pocket_id '
        'WHERE p.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.statements: await _count(
        'SELECT COUNT(*) AS count FROM credit_card_statements s '
        'JOIN account_pockets p ON p.id = s.account_pocket_id '
        'WHERE p.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.installmentPlans: await _count(
        'SELECT COUNT(*) AS count FROM installment_plans plan '
        'JOIN account_pockets p ON p.id = plan.account_pocket_id '
        'WHERE p.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.recurrenceTemplates: await _count(
        'SELECT COUNT(*) AS count FROM recurring_template_movements m '
        'JOIN account_pockets p ON p.id = m.account_pocket_id '
        'WHERE p.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.transactions: await _count(
        'SELECT COUNT(DISTINCT t.id) AS count FROM transactions t '
        'JOIN account_movements m ON m.transaction_id = t.id '
        'JOIN account_pockets p ON p.id = m.account_pocket_id '
        'WHERE p.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.goals: await _count(
        'SELECT COUNT(*) AS count FROM goal_accounts ga '
        'JOIN account_pockets p ON p.id = ga.account_pocket_id '
        'WHERE p.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.budgets: await _count(
        'SELECT COUNT(*) AS count FROM budget_accounts ba '
        'WHERE ba.account_id = ?',
        accountId,
      ),
      AccountReferenceKind.attachments: await _count(
        'SELECT COUNT(*) AS count FROM attachment_links link '
        "WHERE (link.entity_type = 'account' AND link.entity_id = ?) "
        "OR (link.entity_type = 'account_pocket' AND link.entity_id IN "
        '(SELECT id FROM account_pockets WHERE account_id = ?))',
        accountId,
        twice: true,
      ),
    };

    if (await _count(
          'SELECT COUNT(*) AS count FROM credit_card_statements s '
          'JOIN account_pockets p ON p.id = s.account_pocket_id '
          "WHERE p.account_id = ? AND s.deleted_at IS NULL "
          "AND s.status NOT IN ('paid', 'cancelled') "
          'AND COALESCE((SELECT SUM(m.amount_minor) FROM account_movements m '
          'JOIN transactions t ON t.id = m.transaction_id '
          "WHERE m.statement_id = s.id AND t.deleted_at IS NULL "
          "AND t.status != 'cancelled'), 0) != 0",
          accountId,
        ) >
        0) {
      blockers.add(AccountRemovalBlocker.openStatement);
    }
    if (await _count(
          'SELECT COUNT(*) AS count FROM installments item '
          'JOIN installment_plans plan ON plan.id = item.installment_plan_id '
          'JOIN account_pockets p ON p.id = plan.account_pocket_id '
          "WHERE p.account_id = ? AND plan.deleted_at IS NULL "
          "AND plan.status = 'active' AND item.status = 'scheduled'",
          accountId,
        ) >
        0) {
      blockers.add(AccountRemovalBlocker.scheduledInstallment);
    }
    if (await _count(
          'SELECT COUNT(*) AS count FROM recurring_template_movements m '
          'JOIN recurring_rules rule ON rule.id = m.recurring_rule_id '
          'JOIN account_pockets p ON p.id = m.account_pocket_id '
          'WHERE p.account_id = ? AND rule.enabled = 1 '
          'AND rule.deleted_at IS NULL',
          accountId,
        ) >
        0) {
      blockers.add(AccountRemovalBlocker.activeRecurrence);
    }
    if (await _count(
          'SELECT COUNT(DISTINCT t.id) AS count FROM transactions t '
          'JOIN account_movements m ON m.transaction_id = t.id '
          'JOIN account_pockets p ON p.id = m.account_pocket_id '
          'WHERE p.account_id = ? AND t.deleted_at IS NULL '
          "AND t.status != 'cancelled' "
          "AND (t.status = 'pending' OR t.financial_date > ?)",
          accountId,
          second: effectiveOn.toString(),
        ) >
        0) {
      blockers.add(AccountRemovalBlocker.pendingTransaction);
    }
    if (await _count(
          'SELECT COUNT(*) AS count FROM goal_accounts ga '
          'JOIN goals goal ON goal.id = ga.goal_id '
          'JOIN account_pockets p ON p.id = ga.account_pocket_id '
          "WHERE p.account_id = ? AND goal.status = 'active' "
          'AND goal.deleted_at IS NULL',
          accountId,
        ) >
        0) {
      blockers.add(AccountRemovalBlocker.activeGoal);
    }
    if (await _count(
          'SELECT COUNT(*) AS count FROM budget_accounts ba '
          'JOIN budgets budget ON budget.id = ba.budget_id '
          'WHERE ba.account_id = ? AND budget.enabled = 1 '
          'AND budget.deleted_at IS NULL',
          accountId,
        ) >
        0) {
      blockers.add(AccountRemovalBlocker.enabledBudget);
    }
    return AccountRemovalAssessment(
      aggregate: aggregate,
      balances: balances,
      blockers: blockers,
      references: references,
    );
  }

  Future<int> _count(
    String sql,
    EntityId accountId, {
    bool twice = false,
    String? second,
  }) async {
    final row = await database
        .customSelect(
          sql,
          variables: [
            Variable(accountId.value),
            if (twice) Variable(accountId.value),
            if (second != null) Variable(second),
          ],
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<LocalDate> _vaultDate(EntityId vaultId, UtcInstant instant) async {
    final vault = await DriftVaultRepository(database).find(vaultId);
    if (vault == null || vault.deletedAt != null) {
      throw const AccountLifecycleConflict();
    }
    ZonedRecurrenceClock.initialize();
    final value = tz.TZDateTime.from(
      instant.toDateTime(),
      vault.timezone == 'UTC' ? tz.UTC : tz.getLocation(vault.timezone),
    );
    return LocalDate(value.year, value.month, value.day);
  }

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

  Future<void> _save(AccountAggregate aggregate) => database.transaction(
    () async {
      final current = await findAggregate(aggregate.account.id);
      final account = aggregate.account;
      if (current == null) {
        await DriftAccountRepository(database).save(account);
      } else {
        final old = current.account;
        final identical =
            _sameAccount(old, account) &&
            current.pockets.length == aggregate.pockets.length &&
            current.pockets.every(
              (pocket) => aggregate.pockets.any(
                (incoming) => _samePocket(pocket, incoming),
              ),
            );
        if (identical) return;
        if (old.vaultId != account.vaultId ||
            account.revision != old.revision + 1 ||
            account.type != old.type ||
            account.nature != old.nature ||
            account.openedOn != old.openedOn ||
            account.createdAt != old.createdAt ||
            old.archived ||
            old.deletedAt != null ||
            account.archived != old.archived ||
            account.closedOn != old.closedOn ||
            account.deletedAt != old.deletedAt ||
            current.pockets.any(
              (pocket) => !aggregate.pockets.any(
                (incoming) =>
                    incoming.id == pocket.id &&
                    incoming.currency == pocket.currency &&
                    incoming.archived == pocket.archived,
              ),
            )) {
          throw const AccountLifecycleConflict();
        }
        final changed =
            await (database.update(database.accounts)..where(
                  (row) =>
                      row.id.equals(account.id.value) &
                      row.vaultId.equals(account.vaultId.value) &
                      row.revision.equals(old.revision),
                ))
                .write(
                  AccountsCompanion(
                    name: Value(account.name),
                    institution: Value(account.institution),
                    includeInNetWorth: Value(account.includeInNetWorth ? 1 : 0),
                    sortOrder: Value(account.sortOrder),
                    revision: Value(account.revision),
                    updatedAt: Value(account.updatedAt.epochMicroseconds),
                  ),
                );
        if (changed != 1) throw const AccountLifecycleConflict();
      }
      for (final pocket in aggregate.pockets) {
        final existing = await (database.select(
          database.accountPockets,
        )..where((row) => row.id.equals(pocket.id.value))).getSingleOrNull();
        if (existing != null &&
            existing.accountId != aggregate.account.id.value) {
          throw const AccountLifecycleConflict();
        }
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
    },
  );

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

bool _samePocket(AccountPocketProfile left, AccountPocketProfile right) =>
    (
      left.id,
      left.accountId,
      left.currency,
      left.name,
      left.isDefault,
      left.archived,
    ) ==
    (
      right.id,
      right.accountId,
      right.currency,
      right.name,
      right.isDefault,
      right.archived,
    );

bool _sameAccount(AccountProfile left, AccountProfile right) =>
    (
      left.id,
      left.vaultId,
      left.name,
      left.institution,
      left.type,
      left.nature,
      left.includeInNetWorth,
      left.archived,
      left.openedOn,
      left.closedOn,
      left.sortOrder,
      left.revision,
      left.createdAt,
      left.updatedAt,
      left.deletedAt,
    ) ==
    (
      right.id,
      right.vaultId,
      right.name,
      right.institution,
      right.type,
      right.nature,
      right.includeInNetWorth,
      right.archived,
      right.openedOn,
      right.closedOn,
      right.sortOrder,
      right.revision,
      right.createdAt,
      right.updatedAt,
      right.deletedAt,
    );

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
