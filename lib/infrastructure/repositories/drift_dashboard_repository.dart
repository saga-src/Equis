import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../application/ports/dashboard_repository.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/uuid_v7.dart';
import '../persistence/database/equis_database.dart';

final class DriftDashboardRepository implements DashboardRepository {
  DriftDashboardRepository(this.database);

  final EquisDatabase database;
  final Map<String, int> _minorUnits = {};
  final Map<String, _ResolvedRate?> _rates = {};

  @override
  void beginRead() => _rates.clear();

  @override
  Future<List<ReportingSplitRow>> loadSplits({
    required EntityId vaultId,
    required LocalDate from,
    required LocalDate through,
    required LocalDate asOf,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT split.category_id, split.currency_code, '
          'SUM(split.amount_minor) AS amount_minor, parent.financial_date, '
          '(SELECT json_group_array(tt.tag_id) FROM transaction_tags tt '
          'WHERE tt.transaction_id = parent.id) AS tag_ids, '
          "CASE WHEN parent.transaction_type IN ('income', 'dividend', 'interest') "
          "THEN 'income' ELSE 'expense' END AS classification "
          'FROM transaction_splits AS split '
          'CROSS JOIN transactions AS parent ON parent.id = split.transaction_id '
          'WHERE parent.vault_id = ? AND parent.financial_date >= ? '
          'AND parent.financial_date <= ? AND parent.financial_date <= ? '
          "AND parent.status != 'cancelled' AND parent.deleted_at IS NULL "
          "AND NOT (parent.status = 'pending' AND parent.recurring_rule_id IS NOT NULL) "
          "AND parent.transaction_type IN ('expense', 'credit_card_purchase', "
          "'fee', 'refund', 'income', 'dividend', 'interest') "
          'GROUP BY parent.id, split.category_id, split.currency_code, '
          'parent.financial_date, classification '
          'ORDER BY parent.financial_date, split.category_id',
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(from.toString()),
            Variable<String>(through.toString()),
            Variable<String>(asOf.toString()),
          ],
          readsFrom: {
            database.transactionSplits,
            database.transactions,
            database.transactionTags,
          },
        )
        .get();
    return [
      for (final row in rows)
        ReportingSplitRow(
          categoryId: EntityId.parse(row.read<String>('category_id')),
          tagIds: (jsonDecode(row.read<String>('tag_ids')) as List)
              .cast<String>()
              .map(EntityId.parse)
              .toList(),
          currency: CurrencyCode(row.read<String>('currency_code')),
          amountMinor: row.read<int>('amount_minor'),
          date: LocalDate.parse(row.read<String>('financial_date')),
          classification: row.read<String>('classification') == 'income'
              ? ReportClassification.income
              : ReportClassification.expense,
        ),
    ];
  }

  @override
  Future<List<ReportingAccountRow>> loadAccountBalances({
    required EntityId vaultId,
    required LocalDate asOf,
  }) async {
    final rows = await database
        .customSelect(
          'SELECT account.id AS account_id, pocket.id AS pocket_id, '
          'account.name AS account_name, account.account_type, account.nature, '
          'pocket.currency_code, '
          'COALESCE(SUM(CASE WHEN parent.id IS NOT NULL '
          "AND parent.status != 'cancelled' AND parent.deleted_at IS NULL "
          'AND parent.financial_date <= ? '
          "AND NOT (parent.status = 'pending' AND parent.recurring_rule_id IS NOT NULL) "
          'THEN movement.amount_minor ELSE 0 END), 0) AS balance_minor '
          'FROM accounts AS account '
          'INNER JOIN account_pockets AS pocket ON pocket.account_id = account.id '
          'LEFT JOIN account_movements AS movement '
          'ON movement.account_pocket_id = pocket.id '
          'LEFT JOIN transactions AS parent ON parent.id = movement.transaction_id '
          'WHERE account.vault_id = ? AND account.deleted_at IS NULL '
          'AND account.archived = 0 AND pocket.archived = 0 '
          'GROUP BY account.id, pocket.id '
          'ORDER BY account.sort_order, account.name, pocket.currency_code',
          variables: [
            Variable<String>(asOf.toString()),
            Variable<String>(vaultId.value),
          ],
          readsFrom: {
            database.accounts,
            database.accountPockets,
            database.accountMovements,
            database.transactions,
          },
        )
        .get();
    return [
      for (final row in rows)
        ReportingAccountRow(
          accountId: EntityId.parse(row.read<String>('account_id')),
          pocketId: EntityId.parse(row.read<String>('pocket_id')),
          accountName: row.read<String>('account_name'),
          type: AccountType.fromStorage(row.read<String>('account_type')),
          nature: AccountNature.values.byName(row.read<String>('nature')),
          currency: CurrencyCode(row.read<String>('currency_code')),
          balanceMinor: row.read<int>('balance_minor'),
        ),
    ];
  }

  @override
  Future<ReportingConversion?> convertMinor({
    required EntityId vaultId,
    required CurrencyCode source,
    required CurrencyCode target,
    required LocalDate date,
    required int amountMinor,
  }) async {
    if (source == target) {
      return ReportingConversion(minorUnits: amountMinor);
    }
    final rate = await _resolveRate(
      vaultId: vaultId,
      source: source,
      target: target,
      date: date,
    );
    if (rate == null) return null;
    final sourceScale = await _currencyMinorUnits(source);
    final targetScale = await _currencyMinorUnits(target);
    final sourceMajor = Decimal.fromInt(amountMinor).shift(-sourceScale);
    final targetMinor = DecimalValue.round(
      (sourceMajor * rate.value).shift(targetScale),
      scale: 0,
    ).toBigInt();
    if (targetMinor < BigInt.from(Money.minInt64) ||
        targetMinor > BigInt.from(Money.maxInt64)) {
      throw RangeError('Converted report value does not fit signed int64.');
    }
    return ReportingConversion(
      minorUnits: targetMinor.toInt(),
      estimated: rate.estimated,
    );
  }

  @override
  Future<int> countUpcomingInstallments({
    required EntityId vaultId,
    required LocalDate after,
    required LocalDate through,
  }) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS total FROM installments AS item '
          'INNER JOIN installment_plans AS plan '
          'ON plan.id = item.installment_plan_id '
          'WHERE plan.vault_id = ? AND plan.deleted_at IS NULL '
          "AND plan.status = 'active' AND item.status = 'scheduled' "
          'AND item.expected_date > ? AND item.expected_date <= ?',
          variables: [
            Variable<String>(vaultId.value),
            Variable<String>(after.toString()),
            Variable<String>(through.toString()),
          ],
          readsFrom: {database.installments, database.installmentPlans},
        )
        .getSingle();
    return row.read<int>('total');
  }

  Future<int> _currencyMinorUnits(CurrencyCode code) async {
    final cached = _minorUnits[code.value];
    if (cached != null) return cached;
    final row = await database
        .customSelect(
          'SELECT minor_units FROM currencies WHERE code = ?',
          variables: [Variable<String>(code.value)],
          readsFrom: {database.currencies},
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Currency is missing from local catalog.');
    }
    final value = row.read<int>('minor_units');
    _minorUnits[code.value] = value;
    return value;
  }

  Future<_ResolvedRate?> _resolveRate({
    required EntityId vaultId,
    required CurrencyCode source,
    required CurrencyCode target,
    required LocalDate date,
  }) async {
    final key = '${vaultId.value}|${source.value}|${target.value}|$date';
    if (_rates.containsKey(key)) return _rates[key];
    final manual = await _rateRows(
      table: 'manual_fx_rates',
      source: source,
      target: target,
      date: date,
      vaultId: vaultId,
      manual: true,
    );
    final cached =
        manual ??
        await _rateRows(
          table: 'fx_rate_cache',
          source: source,
          target: target,
          date: date,
          manual: false,
        );
    _rates[key] = cached;
    return cached;
  }

  Future<_ResolvedRate?> _rateRows({
    required String table,
    required CurrencyCode source,
    required CurrencyCode target,
    required LocalDate date,
    required bool manual,
    EntityId? vaultId,
  }) async {
    for (final inverse in [false, true]) {
      final base = inverse ? target : source;
      final quote = inverse ? source : target;
      final prefix = manual ? 'vault_id = ? AND deleted_at IS NULL AND ' : '';
      final datePredicate = manual ? 'rate_date = ?' : 'rate_date <= ?';
      final values = <Variable<Object>>[
        if (manual) Variable<String>(vaultId!.value),
        Variable<String>(base.value),
        Variable<String>(quote.value),
        Variable<String>(date.toString()),
      ];
      var rows = await database
          .customSelect(
            'SELECT rate, rate_date FROM $table WHERE $prefix'
            'base_currency = ? AND quote_currency = ? AND $datePredicate '
            'ORDER BY rate_date DESC LIMIT 1',
            variables: values,
            readsFrom: manual
                ? {database.manualFxRates}
                : {database.fxRateCache},
          )
          .get();
      if (rows.isEmpty && !manual) {
        rows = await database
            .customSelect(
              'SELECT rate, rate_date FROM $table '
              'WHERE base_currency = ? AND quote_currency = ? '
              'ORDER BY rate_date DESC LIMIT 1',
              variables: [
                Variable<String>(base.value),
                Variable<String>(quote.value),
              ],
              readsFrom: {database.fxRateCache},
            )
            .get();
      }
      if (rows.isEmpty) continue;
      final value = DecimalValue.parse(rows.single.read<String>('rate'));
      return _ResolvedRate(
        value: inverse
            ? (Decimal.one / value).toDecimal(scaleOnInfinitePrecision: 18)
            : value,
        estimated: rows.single.read<String>('rate_date') != date.toString(),
      );
    }
    return null;
  }
}

final class _ResolvedRate {
  const _ResolvedRate({required this.value, required this.estimated});
  final Decimal value;
  final bool estimated;
}
