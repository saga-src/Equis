import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import '../../domain/shared/zoned_recurrence.dart';
import 'package:drift/drift.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/recurring/recurrence_models.dart' as recurrence;
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';
import '../repositories/recurring_template_codec.dart';
import 'drift_sync_aggregate_store.dart';

final class RecurringSyncHistory {
  const RecurringSyncHistory(this.database);
  final EquisDatabase database;

  static String today(String timezone) {
    ZonedRecurrenceClock.initialize();
    final date = tz.TZDateTime.from(
      DateTime.now().toUtc(),
      tz.getLocation(timezone),
    );
    return LocalDate(date.year, date.month, date.day).toString();
  }

  Future<void> validateStored(String vaultId) async {
    final roots = await database
        .customSelect(
          'SELECT * FROM recurring_rules WHERE vault_id = ?',
          variables: [Variable(vaultId)],
        )
        .get();
    for (final root in roots) {
      final versions = await database
          .customSelect(
            'SELECT * FROM recurring_rule_versions WHERE recurring_rule_id = ?',
            variables: [Variable(root.read<String>('id'))],
          )
          .get();
      if (root.read<int>('schedule_history_edited') == 0) {
        if (versions.isNotEmpty) throw const SyncAggregateFormatException();
        continue;
      }
      final templates = await database
          .customSelect(
            'SELECT * FROM recurring_templates WHERE recurring_rule_id = ?',
            variables: [Variable(root.read<String>('id'))],
          )
          .get();
      await validate({
        'format_version': 2,
        'root': root.data,
        'children': {
          'recurring_templates': [for (final row in templates) row.data],
          'recurring_rule_versions': [for (final row in versions) row.data],
        },
      });
    }
  }

  Future<bool> protected(String id, Map<String, Object?> payload) async {
    final local = await database
        .customSelect(
          'SELECT schedule_history_edited, deleted_at FROM recurring_rules WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();
    if (local == null) return false;
    final root = payload['root'] as Map;
    return (local.readNullable<int>('deleted_at') != null &&
            root['deleted_at'] == null) ||
        (local.read<int>('schedule_history_edited') == 1 &&
            (payload['format_version'] != 2 ||
                root['schedule_history_edited'] != 1));
  }

  Future<void> validate(Map<String, Object?> payload) async {
    try {
      final root = payload['root'] as Map;
      final children = payload['children'] as Map;
      final rows = (children['recurring_rule_versions'] as List?) ?? const [];
      if (payload['format_version'] == 1) {
        if (root.containsKey('schedule_history_edited')) {
          throw const SyncAggregateFormatException();
        }
        return;
      }
      if (root['schedule_history_edited'] != 1 || rows.isEmpty) {
        throw const SyncAggregateFormatException();
      }
      final start = LocalDate.parse(root['starts_on'] as String);
      final seen = <String>{};
      var hasBase = false;
      final baseType =
          ((children['recurring_templates'] as List).single
              as Map)['transaction_type'];
      CurrencyCode? currency;
      for (final raw in rows) {
        final row = raw as Map;
        final effective = LocalDate.parse(row['effective_from'] as String);
        final anchor = LocalDate.parse(row['anchor_on'] as String);
        if (row.length != 7 ||
            row['recurring_rule_id'] != root['id'] ||
            !seen.add(effective.toString()) ||
            effective.compareTo(start) < 0 ||
            anchor.compareTo(effective) > 0 ||
            row['name'] is! String ||
            (row['name'] as String).trim().isEmpty ||
            (row['ends_on'] != null &&
                LocalDate.parse(row['ends_on'] as String).compareTo(effective) <
                    0)) {
          throw const SyncAggregateFormatException();
        }
        hasBase |= effective == start;
        recurrence.RecurrencePattern.parse(row['rrule'] as String);
        final json = row['template_json'] as String;
        final encoded = jsonDecode(json) as Map;
        if (encoded.length != 5) throw const SyncAggregateFormatException();
        final template = await decodeRecurringTemplate(json, (id) async {
          final pocket = await database
              .customSelect(
                'SELECT p.currency_code, a.nature FROM account_pockets p '
                'JOIN accounts a ON a.id = p.account_id WHERE p.id = ? AND a.vault_id = ?',
                variables: [
                  Variable(id.value),
                  Variable(root['vault_id'] as String),
                ],
              )
              .getSingleOrNull();
          if (pocket == null) throw const SyncAggregateFormatException();
          return LedgerPocket(
            id: id,
            currency: CurrencyCode(pocket.read<String>('currency_code')),
            nature: AccountNature.values.byName(pocket.read<String>('nature')),
          );
        });
        if (template.transactionType.stored != baseType ||
            template.movements.isEmpty) {
          throw const SyncAggregateFormatException();
        }
        currency ??= template.movements.first.pocket.currency;
        if (template.movements.any(
          (movement) => movement.pocket.currency != currency,
        )) {
          throw const SyncAggregateFormatException();
        }
        for (final split in template.splits) {
          final category = await database
              .customSelect(
                'SELECT id FROM categories WHERE id = ? AND vault_id = ? AND category_type = ?',
                variables: [
                  Variable(split.categoryId.value),
                  Variable(root['vault_id'] as String),
                  Variable(template.transactionType.stored),
                ],
              )
              .getSingleOrNull();
          if (category == null) throw const SyncAggregateFormatException();
        }
        LedgerTransaction(
          id: EntityId.generate(),
          vaultId: EntityId.parse(root['vault_id'] as String),
          type: template.transactionType,
          status: LedgerTransactionStatus.pending,
          financialDate: effective,
          movements: template.movements,
          splits: template.splits,
          createdAt: const UtcInstant.fromEpochMicroseconds(1),
          updatedAt: const UtcInstant.fromEpochMicroseconds(1),
        ).validate();
      }
      if (!hasBase) throw const SyncAggregateFormatException();
    } on SyncAggregateFormatException {
      rethrow;
    } catch (_) {
      throw const SyncAggregateFormatException();
    }
  }
}
