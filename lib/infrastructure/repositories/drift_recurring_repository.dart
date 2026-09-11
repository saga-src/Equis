import 'package:drift/drift.dart';

import '../../application/ports/ledger_repository.dart';
import '../../application/ports/recurring_repository.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/recurring/recurrence_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart'
    hide RecurringRule, RecurringTemplate;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';

final class DriftRecurringRepository implements RecurringRepository {
  const DriftRecurringRepository({
    required this.database,
    required this.ledger,
    this.syncRecorder,
  });

  final EquisDatabase database;
  final LedgerRepository ledger;
  final DriftSyncMutationRecorder? syncRecorder;

  @override
  Future<void> save(RecurringSchedule schedule) =>
      syncRecorder?.run(
        vaultId: schedule.rule.vaultId.value,
        entityType: SyncEntityType.recurringRule,
        recordId: schedule.rule.id.value,
        newRevision: schedule.rule.revision,
        operation: schedule.rule.deletedAt == null
            ? SyncOperation.upsert
            : SyncOperation.delete,
        action: () => _save(schedule),
      ) ??
      _save(schedule);

  Future<void> _save(
    RecurringSchedule schedule,
  ) => database.transaction(() async {
    final rule = schedule.rule;
    final rows = await database
        .customSelect(
          'SELECT revision FROM recurring_rules WHERE id = ?',
          variables: [Variable<String>(rule.id.value)],
          readsFrom: {database.recurringRules},
        )
        .get();
    if (rows.isEmpty) {
      if (rule.revision != 1) throw RecurringRevisionConflict(rule.id);
      await database.customStatement(
        'INSERT INTO recurring_rules '
        '(id, vault_id, name, rrule, timezone, starts_on, ends_on, enabled, '
        'next_occurrence, revision, created_at, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          rule.id.value,
          rule.vaultId.value,
          rule.name,
          rule.pattern.serialize(rule.startsOn),
          rule.timezone,
          rule.startsOn.toString(),
          rule.endsOn?.toString(),
          rule.enabled ? 1 : 0,
          rule.nextOccurrence?.toString(),
          rule.revision,
          rule.createdAt.epochMicroseconds,
          rule.updatedAt.epochMicroseconds,
          rule.deletedAt?.epochMicroseconds,
        ],
      );
    } else {
      final expected = rule.revision - 1;
      if (rows.single.read<int>('revision') != expected) {
        throw RecurringRevisionConflict(rule.id);
      }
      final changed = await database.customUpdate(
        'UPDATE recurring_rules SET name = ?, rrule = ?, timezone = ?, '
        'starts_on = ?, ends_on = ?, enabled = ?, next_occurrence = ?, '
        'revision = ?, updated_at = ?, deleted_at = ? '
        'WHERE id = ? AND revision = ?',
        variables: _variables([
          rule.name,
          rule.pattern.serialize(rule.startsOn),
          rule.timezone,
          rule.startsOn.toString(),
          rule.endsOn?.toString(),
          rule.enabled ? 1 : 0,
          rule.nextOccurrence?.toString(),
          rule.revision,
          rule.updatedAt.epochMicroseconds,
          rule.deletedAt?.epochMicroseconds,
          rule.id.value,
          expected,
        ]),
        updates: {database.recurringRules},
      );
      if (changed != 1) throw RecurringRevisionConflict(rule.id);
      await database.customStatement(
        'DELETE FROM recurring_template_splits WHERE recurring_rule_id = ?',
        [rule.id.value],
      );
      await database.customStatement(
        'DELETE FROM recurring_template_movements WHERE recurring_rule_id = ?',
        [rule.id.value],
      );
      await database.customStatement(
        'DELETE FROM recurring_templates WHERE recurring_rule_id = ?',
        [rule.id.value],
      );
    }
    await _insertTemplate(schedule);
  });

  Future<void> _insertTemplate(RecurringSchedule schedule) async {
    final ruleId = schedule.rule.id.value;
    final template = schedule.template;
    await database.customStatement(
      'INSERT INTO recurring_templates '
      '(recurring_rule_id, transaction_type, title, notes) '
      'VALUES (?, ?, ?, ?)',
      [ruleId, template.transactionType.stored, template.title, template.notes],
    );
    for (final movement in template.movements) {
      await database.customStatement(
        'INSERT INTO recurring_template_movements '
        '(id, recurring_rule_id, account_pocket_id, amount_minor) '
        'VALUES (?, ?, ?, ?)',
        [
          movement.id.value,
          ruleId,
          movement.pocket.id.value,
          movement.amountMinor,
        ],
      );
    }
    for (final split in template.splits) {
      await database.customStatement(
        'INSERT INTO recurring_template_splits '
        '(id, recurring_rule_id, category_id, currency_code, amount_minor) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          split.id.value,
          ruleId,
          split.categoryId.value,
          split.money.currency.value,
          split.money.minorUnits,
        ],
      );
    }
  }

  @override
  Future<RecurringSchedule?> find(EntityId ruleId) async {
    final rows = await _rows(
      'SELECT * FROM recurring_rules WHERE id = ?',
      [ruleId.value],
      readsFrom: {database.recurringRules},
    );
    if (rows.isEmpty) return null;
    return _load(rows.single);
  }

  @override
  Future<List<RecurringSchedule>> listForVault(EntityId vaultId) async {
    final roots = await _rows(
      'SELECT * FROM recurring_rules '
      'WHERE vault_id = ? AND deleted_at IS NULL '
      'ORDER BY enabled DESC, next_occurrence, name, id',
      [vaultId.value],
      readsFrom: {database.recurringRules},
    );
    final result = <RecurringSchedule>[];
    for (final root in roots) {
      result.add(await _load(root));
    }
    return result;
  }

  Future<RecurringSchedule> _load(Map<String, Object?> root) async {
    final id = root['id']! as String;
    final templates = await _rows(
      'SELECT * FROM recurring_templates WHERE recurring_rule_id = ?',
      [id],
      readsFrom: {database.recurringTemplates},
    );
    if (templates.length != 1) {
      throw StateError('A recurring rule must have exactly one template.');
    }
    final movements = await _rows(
      'SELECT movement.*, pocket.currency_code, account.nature '
      'FROM recurring_template_movements movement '
      'INNER JOIN account_pockets pocket ON pocket.id = movement.account_pocket_id '
      'INNER JOIN accounts account ON account.id = pocket.account_id '
      'WHERE movement.recurring_rule_id = ? ORDER BY movement.id',
      [id],
      readsFrom: {
        database.recurringTemplateMovements,
        database.accountPockets,
        database.accounts,
      },
    );
    final splits = await _rows(
      'SELECT * FROM recurring_template_splits '
      'WHERE recurring_rule_id = ? ORDER BY id',
      [id],
      readsFrom: {database.recurringTemplateSplits},
    );
    final template = templates.single;
    final startsOn = LocalDate.parse(root['starts_on']! as String);
    return RecurringSchedule(
      rule: RecurringRule(
        id: EntityId.parse(id),
        vaultId: EntityId.parse(root['vault_id']! as String),
        name: root['name']! as String,
        pattern: RecurrencePattern.parse(root['rrule']! as String),
        timezone: root['timezone']! as String,
        startsOn: startsOn,
        endsOn: root['ends_on'] == null
            ? null
            : LocalDate.parse(root['ends_on']! as String),
        enabled: (root['enabled']! as int) == 1,
        nextOccurrence: root['next_occurrence'] == null
            ? null
            : LocalDate.parse(root['next_occurrence']! as String),
        revision: root['revision']! as int,
        createdAt: UtcInstant.fromEpochMicroseconds(root['created_at']! as int),
        updatedAt: UtcInstant.fromEpochMicroseconds(root['updated_at']! as int),
        deletedAt: root['deleted_at'] == null
            ? null
            : UtcInstant.fromEpochMicroseconds(root['deleted_at']! as int),
      ),
      template: RecurringTemplate(
        transactionType: LedgerTransactionType.fromStorage(
          template['transaction_type']! as String,
        ),
        title: template['title'] as String?,
        notes: template['notes'] as String?,
        movements: movements
            .asMap()
            .entries
            .map(
              (entry) => LedgerMovement(
                id: EntityId.parse(entry.value['id']! as String),
                pocket: LedgerPocket(
                  id: EntityId.parse(
                    entry.value['account_pocket_id']! as String,
                  ),
                  currency: CurrencyCode(
                    entry.value['currency_code']! as String,
                  ),
                  nature: AccountNature.values.byName(
                    entry.value['nature']! as String,
                  ),
                ),
                amountMinor: entry.value['amount_minor']! as int,
                sortOrder: entry.key,
              ),
            )
            .toList(growable: false),
        splits: splits
            .asMap()
            .entries
            .map(
              (entry) => LedgerSplit(
                id: EntityId.parse(entry.value['id']! as String),
                categoryId: EntityId.parse(
                  entry.value['category_id']! as String,
                ),
                money: Money(
                  currency: CurrencyCode(
                    entry.value['currency_code']! as String,
                  ),
                  minorUnits: entry.value['amount_minor']! as int,
                ),
                sortOrder: entry.key,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<Map<String, LedgerTransaction>> materializedOccurrences({
    required Set<EntityId> ruleIds,
    required LocalDate from,
    required LocalDate through,
  }) async {
    if (ruleIds.isEmpty) return const {};
    final placeholders = List.filled(ruleIds.length, '?').join(',');
    final roots = await database
        .customSelect(
          'SELECT id, recurring_rule_id, recurrence_date FROM transactions '
          'WHERE recurring_rule_id IN ($placeholders) '
          'AND recurrence_date >= ? AND recurrence_date <= ?',
          variables: _variables([
            ...ruleIds.map((id) => id.value),
            from.toString(),
            through.toString(),
          ]),
          readsFrom: {database.transactions},
        )
        .get();
    final result = <String, LedgerTransaction>{};
    for (final root in roots) {
      final transaction = await ledger.find(
        EntityId.parse(root.read<String>('id')),
      );
      if (transaction != null) {
        result[occurrenceKey(
              EntityId.parse(root.read<String>('recurring_rule_id')),
              LocalDate.parse(root.read<String>('recurrence_date')),
            )] =
            transaction;
      }
    }
    return result;
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
    values.map(Variable<Object>.new).toList(growable: false);
