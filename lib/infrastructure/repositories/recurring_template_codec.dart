import 'dart:convert';

import '../../domain/ledger/ledger_models.dart';
import '../../domain/recurring/recurrence_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/uuid_v7.dart';
import '../security/canonical_json.dart';

String encodeRecurringTemplate(RecurringTemplate template) =>
    CanonicalJson.encode({
      'transaction_type': template.transactionType.stored,
      'title': template.title,
      'notes': template.notes,
      'movements': [
        for (final movement in template.movements)
          {
            'pocket_id': movement.pocket.id.value,
            'amount_minor': movement.amountMinor,
            'sort_order': movement.sortOrder,
            'statement_id': movement.statementId?.value,
          },
      ],
      'splits': [
        for (final split in template.splits)
          {
            'category_id': split.categoryId.value,
            'currency_code': split.money.currency.value,
            'amount_minor': split.money.minorUnits,
            'sort_order': split.sortOrder,
            'memo': split.memo,
          },
      ],
    });

Future<RecurringTemplate> decodeRecurringTemplate(
  String json,
  Future<LedgerPocket> Function(EntityId) resolvePocket,
) async {
  final data = Map<String, Object?>.from(jsonDecode(json) as Map);
  _requireKeys(data, const {
    'transaction_type',
    'title',
    'notes',
    'movements',
    'splits',
  });
  final movements = <LedgerMovement>[];
  for (final raw in data['movements']! as List) {
    final row = raw as Map;
    _requireKeys(row, const {
      'pocket_id',
      'amount_minor',
      'sort_order',
      'statement_id',
    });
    movements.add(
      LedgerMovement(
        id: EntityId.generate(),
        pocket: await resolvePocket(EntityId.parse(row['pocket_id'] as String)),
        amountMinor: row['amount_minor'] as int,
        sortOrder: row['sort_order'] as int,
        statementId: row['statement_id'] == null
            ? null
            : EntityId.parse(row['statement_id'] as String),
      ),
    );
  }
  for (final raw in data['splits']! as List) {
    _requireKeys(raw as Map, const {
      'category_id',
      'currency_code',
      'amount_minor',
      'sort_order',
      'memo',
    });
  }
  return RecurringTemplate(
    transactionType: LedgerTransactionType.fromStorage(
      data['transaction_type'] as String,
    ),
    title: data['title'] as String?,
    notes: data['notes'] as String?,
    movements: List.unmodifiable(movements),
    splits: List.unmodifiable([
      for (final raw in data['splits']! as List)
        LedgerSplit(
          id: EntityId.generate(),
          categoryId: EntityId.parse((raw as Map)['category_id'] as String),
          money: Money(
            currency: CurrencyCode(raw['currency_code'] as String),
            minorUnits: raw['amount_minor'] as int,
          ),
          sortOrder: raw['sort_order'] as int,
          memo: raw['memo'] as String?,
        ),
    ]),
  );
}

void _requireKeys(Map data, Set<String> keys) {
  if (data.length != keys.length || !keys.every(data.containsKey)) {
    throw const FormatException('Unexpected recurring template fields.');
  }
}
