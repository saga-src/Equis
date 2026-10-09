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
    hide RecurringRule, RecurringTemplate, RecurringRuleVersion;
import '../../application/sync/sync_models.dart';
import '../sync/drift_sync_mutation_recorder.dart';
import 'recurring_template_codec.dart';

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
    if (rule.scheduleHistoryEdited != schedule.versions.isNotEmpty ||
        (schedule.versions.isNotEmpty &&
            schedule.versions.first.effectiveFrom != rule.startsOn)) {
      throw StateError('Recurring history must retain its base configuration.');
    }
    LocalDate? previous;
    final currency = schedule.template.movements.first.pocket.currency;
    for (final version in schedule.versions) {
      if ((previous != null &&
              version.effectiveFrom.compareTo(previous) <= 0) ||
          version.anchorOn.compareTo(version.effectiveFrom) > 0 ||
          version.name.trim().isEmpty ||
          (version.endsOn != null &&
              version.endsOn!.compareTo(version.effectiveFrom) < 0) ||
          version.template.transactionType !=
              schedule.template.transactionType ||
          version.template.movements.any(
            (movement) => movement.pocket.currency != currency,
          )) {
        throw StateError('Invalid recurring history configuration.');
      }
      LedgerTransaction(
        id: EntityId.generate(),
        vaultId: rule.vaultId,
        type: version.template.transactionType,
        status: LedgerTransactionStatus.pending,
        financialDate: version.effectiveFrom,
        movements: version.template.movements,
        splits: version.template.splits,
        createdAt: rule.createdAt,
        updatedAt: rule.updatedAt,
      ).validate();
      previous = version.effectiveFrom;
    }
    if (rule.enabled && rule.deletedAt == null) {
      final configurations = schedule.configurations;
      for (final movement in configurations.last.template.movements) {
        final active = await database
            .customSelect(
              'SELECT pocket.id FROM account_pockets AS pocket '
              'JOIN accounts AS account ON account.id = pocket.account_id '
              'WHERE pocket.id = ? AND account.vault_id = ? '
              'AND account.archived = 0 AND account.deleted_at IS NULL '
              'AND pocket.archived = 0',
              variables: [
                Variable<String>(movement.pocket.id.value),
                Variable<String>(rule.vaultId.value),
              ],
              readsFrom: {database.accountPockets, database.accounts},
            )
            .getSingleOrNull();
        if (active == null) {
          throw StateError('Account pocket is inactive.');
        }
      }
    }
    final rows = await database
        .customSelect(
          'SELECT * FROM recurring_rules WHERE id = ?',
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
      final stored = rows.single;
      if (stored.readNullable<int>('deleted_at') != null ||
          stored.read<String>('vault_id') != rule.vaultId.value ||
          stored.read<String>('starts_on') != rule.startsOn.toString() ||
          stored.read<String>('timezone') != rule.timezone ||
          (stored.read<int>('schedule_history_edited') == 1 &&
              !rule.scheduleHistoryEdited)) {
        throw RecurringRevisionConflict(rule.id);
      }
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
    await database.customStatement(
      'UPDATE recurring_rules SET schedule_history_edited = ? WHERE id = ?',
      [rule.scheduleHistoryEdited ? 1 : 0, rule.id.value],
    );
    await database.customStatement(
      'DELETE FROM recurring_rule_versions WHERE recurring_rule_id = ?',
      [rule.id.value],
    );
    for (final version in schedule.versions) {
      for (final movement in version.template.movements) {
        final owner = await database
            .customSelect(
              'SELECT p.id FROM account_pockets p JOIN accounts a ON a.id = p.account_id '
              'WHERE p.id = ? AND a.vault_id = ? AND p.currency_code = ? AND a.nature = ?',
              variables: _variables([
                movement.pocket.id.value,
                rule.vaultId.value,
                movement.pocket.currency.value,
                movement.pocket.nature.name,
              ]),
            )
            .getSingleOrNull();
        if (owner == null) {
          throw StateError('A template pocket must belong to the vault.');
        }
      }
      for (final split in version.template.splits) {
        final category = await database
            .customSelect(
              'SELECT id FROM categories WHERE id = ? AND vault_id = ? AND category_type = ?',
              variables: _variables([
                split.categoryId.value,
                rule.vaultId.value,
                version.template.transactionType.stored,
              ]),
            )
            .getSingleOrNull();
        if (category == null) {
          throw StateError('Category is incompatible with recurrence.');
        }
      }
      await database.customStatement(
        'INSERT INTO recurring_rule_versions '
        '(recurring_rule_id, effective_from, anchor_on, name, rrule, ends_on, template_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          rule.id.value,
          version.effectiveFrom.toString(),
          version.anchorOn.toString(),
          version.name,
          version.pattern.serialize(version.anchorOn),
          version.endsOn?.toString(),
          encodeRecurringTemplate(version.template),
        ],
      );
    }
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
    final versions = <RecurringRuleVersion>[];
    for (final row in await _rows(
      'SELECT * FROM recurring_rule_versions WHERE recurring_rule_id = ? ORDER BY effective_from',
      [id],
      readsFrom: {database.recurringRuleVersions},
    )) {
      final decoded = await decodeRecurringTemplate(
        row['template_json'] as String,
        (pocketId) async {
          final pocket = (await _rows(
            'SELECT pocket.currency_code, account.nature FROM account_pockets pocket '
            'JOIN accounts account ON account.id = pocket.account_id WHERE pocket.id = ? AND account.vault_id = ?',
            [pocketId.value, root['vault_id']],
          )).single;
          return LedgerPocket(
            id: pocketId,
            currency: CurrencyCode(pocket['currency_code'] as String),
            nature: AccountNature.values.byName(pocket['nature'] as String),
          );
        },
      );
      versions.add(
        RecurringRuleVersion(
          effectiveFrom: LocalDate.parse(row['effective_from'] as String),
          anchorOn: LocalDate.parse(row['anchor_on'] as String),
          name: row['name'] as String,
          pattern: RecurrencePattern.parse(row['rrule'] as String),
          endsOn: row['ends_on'] == null
              ? null
              : LocalDate.parse(row['ends_on'] as String),
          template: decoded,
        ),
      );
    }
    return RecurringSchedule(
      versions: versions,
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
        scheduleHistoryEdited: root['schedule_history_edited'] == 1,
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
          'AND ((recurrence_date >= ? AND recurrence_date <= ?) OR (financial_date >= ? AND financial_date <= ?))',
          variables: _variables([
            ...ruleIds.map((id) => id.value),
            from.toString(),
            through.toString(),
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
