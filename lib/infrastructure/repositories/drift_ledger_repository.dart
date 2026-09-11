import 'package:drift/drift.dart';

import '../../application/ports/ledger_repository.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftLedgerRepository implements LedgerRepository {
  const DriftLedgerRepository(this.database, {this.syncRecorder});

  final EquisDatabase database;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(LedgerTransaction aggregate) =>
      syncRecorder?.run(
        vaultId: aggregate.vaultId.value,
        entityType: SyncEntityType.transaction,
        recordId: aggregate.id.value,
        newRevision: aggregate.revision,
        operation: aggregate.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(aggregate),
      ) ??
      _save(aggregate);

  Future<void> _save(
    LedgerTransaction aggregate,
  ) => database.transaction(() async {
    aggregate.validate();
    final revisionRows = await database
        .customSelect(
          'SELECT revision FROM transactions WHERE id = ?',
          variables: [Variable<String>(aggregate.id.value)],
          readsFrom: {database.transactions},
        )
        .get();
    final actualRevision = revisionRows.isEmpty
        ? null
        : revisionRows.single.read<int>('revision');

    if (actualRevision == null) {
      if (aggregate.revision != 1) {
        throw LedgerRevisionConflict(
          transactionId: aggregate.id,
          expectedRevision: aggregate.revision - 1,
          actualRevision: null,
        );
      }
      await _insertRoot(aggregate);
    } else {
      final expected = aggregate.revision - 1;
      if (actualRevision != expected) {
        throw LedgerRevisionConflict(
          transactionId: aggregate.id,
          expectedRevision: expected,
          actualRevision: actualRevision,
        );
      }
      final changed = await database.customUpdate(
        'UPDATE transactions SET transaction_type = ?, status = ?, title = ?, notes = ?, '
        'occurred_at = ?, financial_date = ?, timezone = ?, recurring_rule_id = ?, '
        'recurrence_date = ?, reversal_of_id = ?, revision = ?, updated_at = ?, deleted_at = ? '
        'WHERE id = ? AND revision = ?',
        variables: _variables([
          aggregate.type.stored,
          aggregate.status.name,
          aggregate.title,
          aggregate.notes,
          aggregate.occurredAt?.epochMicroseconds,
          aggregate.financialDate.toString(),
          aggregate.timezone,
          aggregate.recurringRuleId?.value,
          aggregate.recurrenceDate?.toString(),
          aggregate.reversalOfId?.value,
          aggregate.revision,
          aggregate.updatedAt.epochMicroseconds,
          aggregate.deletedAt?.epochMicroseconds,
          aggregate.id.value,
          expected,
        ]),
        updates: {database.transactions},
      );
      if (changed != 1) {
        throw LedgerRevisionConflict(
          transactionId: aggregate.id,
          expectedRevision: expected,
          actualRevision: actualRevision,
        );
      }
      await _deleteChildren(aggregate.id);
    }

    await _insertChildren(aggregate);
  });

  Future<void> _insertRoot(
    LedgerTransaction aggregate,
  ) => database.customStatement(
    'INSERT INTO transactions '
    '(id, vault_id, transaction_type, status, title, notes, occurred_at, '
    'financial_date, timezone, recurring_rule_id, recurrence_date, reversal_of_id, '
    'revision, created_at, updated_at, deleted_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    _values([
      aggregate.id.value,
      aggregate.vaultId.value,
      aggregate.type.stored,
      aggregate.status.name,
      aggregate.title,
      aggregate.notes,
      aggregate.occurredAt?.epochMicroseconds,
      aggregate.financialDate.toString(),
      aggregate.timezone,
      aggregate.recurringRuleId?.value,
      aggregate.recurrenceDate?.toString(),
      aggregate.reversalOfId?.value,
      aggregate.revision,
      aggregate.createdAt.epochMicroseconds,
      aggregate.updatedAt.epochMicroseconds,
      aggregate.deletedAt?.epochMicroseconds,
    ]),
  );

  Future<void> _deleteChildren(EntityId id) async {
    final value = [id.value];
    await database.customStatement(
      'DELETE FROM transaction_tags WHERE transaction_id = ?',
      value,
    );
    await database.customStatement(
      'DELETE FROM investment_events WHERE transaction_id = ?',
      value,
    );
    await database.customStatement(
      'DELETE FROM fx_conversions WHERE transaction_id = ?',
      value,
    );
    await database.customStatement(
      'DELETE FROM transaction_splits WHERE transaction_id = ?',
      value,
    );
    await database.customStatement(
      'DELETE FROM account_movements WHERE transaction_id = ?',
      value,
    );
  }

  Future<void> _insertChildren(LedgerTransaction aggregate) async {
    for (final movement in aggregate.movements) {
      await database.customStatement(
        'INSERT INTO account_movements '
        '(id, transaction_id, account_pocket_id, amount_minor, sort_order, statement_id) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        _values([
          movement.id.value,
          aggregate.id.value,
          movement.pocket.id.value,
          movement.amountMinor,
          movement.sortOrder,
          movement.statementId?.value,
        ]),
      );
    }
    for (final split in aggregate.splits) {
      await database.customStatement(
        'INSERT INTO transaction_splits '
        '(id, transaction_id, category_id, currency_code, amount_minor, memo, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        _values([
          split.id.value,
          aggregate.id.value,
          split.categoryId.value,
          split.money.currency.value,
          split.money.minorUnits,
          split.memo,
          split.sortOrder,
        ]),
      );
    }
    for (final tagId in aggregate.tagIds) {
      await database.customStatement(
        'INSERT INTO transaction_tags (transaction_id, tag_id) VALUES (?, ?)',
        [aggregate.id.value, tagId.value],
      );
    }
    final fx = aggregate.fxConversion;
    if (fx != null) {
      await database.customStatement(
        'INSERT INTO fx_conversions '
        '(id, transaction_id, from_movement_id, to_movement_id, exchange_rate, '
        'rate_source, rate_date, provider) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        _values([
          fx.id.value,
          aggregate.id.value,
          fx.fromMovementId.value,
          fx.toMovementId.value,
          fx.exchangeRate,
          fx.rateSource,
          fx.rateDate?.toString(),
          fx.provider,
        ]),
      );
    }
    for (final event in aggregate.investmentEvents) {
      await database.customStatement(
        'INSERT INTO investment_events '
        '(id, transaction_id, instrument_id, event_type, quantity, unit_price, '
        'price_currency_code, gross_minor, fees_minor, taxes_minor) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        _values([
          event.id.value,
          aggregate.id.value,
          event.instrumentId.value,
          event.eventType,
          event.quantity,
          event.unitPrice,
          event.priceCurrency?.value,
          event.grossMinor,
          event.feesMinor,
          event.taxesMinor,
        ]),
      );
    }
  }

  @override
  Future<LedgerTransaction?> find(
    EntityId id,
  ) => database.transaction(() async {
    final roots = await _rows(
      'SELECT * FROM transactions WHERE id = ?',
      [id.value],
      readsFrom: {database.transactions},
    );
    if (roots.isEmpty) return null;
    final movements = await _rows(
      'SELECT movement.*, pocket.currency_code, account.nature '
      'FROM account_movements AS movement '
      'INNER JOIN account_pockets AS pocket ON pocket.id = movement.account_pocket_id '
      'INNER JOIN accounts AS account ON account.id = pocket.account_id '
      'WHERE movement.transaction_id = ? ORDER BY movement.sort_order, movement.id',
      [id.value],
      readsFrom: {
        database.accountMovements,
        database.accountPockets,
        database.accounts,
      },
    );
    final splits = await _rows(
      'SELECT * FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order, id',
      [id.value],
      readsFrom: {database.transactionSplits},
    );
    final fxRows = await _rows(
      'SELECT * FROM fx_conversions WHERE transaction_id = ?',
      [id.value],
      readsFrom: {database.fxConversions},
    );
    final tagRows = await _rows(
      'SELECT tag_id FROM transaction_tags WHERE transaction_id = ? ORDER BY tag_id',
      [id.value],
      readsFrom: {database.transactionTags},
    );
    final events = await _rows(
      'SELECT * FROM investment_events WHERE transaction_id = ? ORDER BY id',
      [id.value],
      readsFrom: {database.investmentEvents},
    );
    return _mapAggregate(
      roots.single,
      movements,
      splits,
      fxRows,
      events,
      tagRows,
    );
  });

  @override
  Future<List<LedgerTransaction>> listRecentForVault(
    EntityId vaultId, {
    int limit = 20,
  }) async {
    if (limit < 1) throw RangeError.value(limit, 'limit');
    final roots = await database
        .customSelect(
          'SELECT id FROM transactions '
          'WHERE vault_id = ? AND deleted_at IS NULL '
          'ORDER BY financial_date DESC, created_at DESC LIMIT ?',
          variables: [Variable<String>(vaultId.value), Variable<int>(limit)],
          readsFrom: {database.transactions},
        )
        .get();
    final result = <LedgerTransaction>[];
    for (final root in roots) {
      final transaction = await find(EntityId.parse(root.read<String>('id')));
      if (transaction != null) result.add(transaction);
    }
    return result;
  }

  LedgerTransaction _mapAggregate(
    Map<String, Object?> root,
    List<Map<String, Object?>> movementRows,
    List<Map<String, Object?>> splitRows,
    List<Map<String, Object?>> fxRows,
    List<Map<String, Object?>> eventRows,
    List<Map<String, Object?>> tagRows,
  ) {
    final movements = movementRows
        .map(
          (row) => LedgerMovement(
            id: EntityId.parse(row['id']! as String),
            pocket: LedgerPocket(
              id: EntityId.parse(row['account_pocket_id']! as String),
              currency: CurrencyCode(row['currency_code']! as String),
              nature: AccountNature.values.byName(row['nature']! as String),
            ),
            amountMinor: row['amount_minor']! as int,
            sortOrder: row['sort_order']! as int,
            statementId: row['statement_id'] == null
                ? null
                : EntityId.parse(row['statement_id']! as String),
          ),
        )
        .toList(growable: false);
    final splits = splitRows
        .map(
          (row) => LedgerSplit(
            id: EntityId.parse(row['id']! as String),
            categoryId: EntityId.parse(row['category_id']! as String),
            money: Money(
              currency: CurrencyCode(row['currency_code']! as String),
              minorUnits: row['amount_minor']! as int,
            ),
            memo: row['memo'] as String?,
            sortOrder: row['sort_order']! as int,
          ),
        )
        .toList(growable: false);
    final fx = fxRows.isEmpty
        ? null
        : LedgerFxConversion(
            id: EntityId.parse(fxRows.single['id']! as String),
            fromMovementId: EntityId.parse(
              fxRows.single['from_movement_id']! as String,
            ),
            toMovementId: EntityId.parse(
              fxRows.single['to_movement_id']! as String,
            ),
            exchangeRate: fxRows.single['exchange_rate']! as String,
            rateSource: fxRows.single['rate_source']! as String,
            rateDate: fxRows.single['rate_date'] == null
                ? null
                : LocalDate.parse(fxRows.single['rate_date']! as String),
            provider: fxRows.single['provider'] as String?,
          );
    final events = eventRows
        .map(
          (row) => LedgerInvestmentEvent(
            id: EntityId.parse(row['id']! as String),
            instrumentId: EntityId.parse(row['instrument_id']! as String),
            eventType: row['event_type']! as String,
            quantity: row['quantity'] as String?,
            unitPrice: row['unit_price'] as String?,
            priceCurrency: row['price_currency_code'] == null
                ? null
                : CurrencyCode(row['price_currency_code']! as String),
            grossMinor: row['gross_minor'] as int?,
            feesMinor: row['fees_minor'] as int?,
            taxesMinor: row['taxes_minor'] as int?,
          ),
        )
        .toList(growable: false);
    return LedgerTransaction(
      id: EntityId.parse(root['id']! as String),
      vaultId: EntityId.parse(root['vault_id']! as String),
      type: LedgerTransactionType.fromStorage(
        root['transaction_type']! as String,
      ),
      status: LedgerTransactionStatus.values.byName(root['status']! as String),
      financialDate: LocalDate.parse(root['financial_date']! as String),
      movements: movements,
      splits: splits,
      fxConversion: fx,
      investmentEvents: events,
      title: root['title'] as String?,
      notes: root['notes'] as String?,
      occurredAt: root['occurred_at'] == null
          ? null
          : UtcInstant.fromEpochMicroseconds(root['occurred_at']! as int),
      timezone: root['timezone'] as String?,
      reversalOfId: root['reversal_of_id'] == null
          ? null
          : EntityId.parse(root['reversal_of_id']! as String),
      recurringRuleId: root['recurring_rule_id'] == null
          ? null
          : EntityId.parse(root['recurring_rule_id']! as String),
      recurrenceDate: root['recurrence_date'] == null
          ? null
          : LocalDate.parse(root['recurrence_date']! as String),
      tagIds: tagRows
          .map((row) => EntityId.parse(row['tag_id']! as String))
          .toList(growable: false),
      deletedAt: root['deleted_at'] == null
          ? null
          : UtcInstant.fromEpochMicroseconds(root['deleted_at']! as int),
      revision: root['revision']! as int,
      createdAt: UtcInstant.fromEpochMicroseconds(root['created_at']! as int),
      updatedAt: UtcInstant.fromEpochMicroseconds(root['updated_at']! as int),
    );
  }

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

List<Variable<Object>> _variables(List<Object?> values) =>
    values.map((value) => Variable<Object>(value)).toList(growable: false);

List<Object?> _values(List<Object?> values) => values;
