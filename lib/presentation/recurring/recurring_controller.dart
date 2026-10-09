import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/recurring_transaction_service.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/ledger/ledger_engine.dart';
import '../../domain/recurring/recurrence_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class RecurringState {
  const RecurringState({
    this.rules = const [],
    this.upcoming = const [],
    this.loading = false,
    this.error,
  });

  final List<RecurringSchedule> rules;
  final List<ScheduledOccurrence> upcoming;
  final bool loading;
  final Object? error;
}

final class RecurringController extends StateNotifier<RecurringState> {
  RecurringController({
    required RecurringTransactionService? service,
    required EntityId? vaultId,
  }) : this._(service, vaultId);

  RecurringController._(this._service, this._vaultId)
    : super(const RecurringState());

  final RecurringTransactionService? _service;
  final EntityId? _vaultId;

  Future<void> reload() async {
    final service = _service;
    final vaultId = _vaultId;
    if (service == null || vaultId == null) return;
    state = RecurringState(
      rules: state.rules,
      upcoming: state.upcoming,
      loading: true,
    );
    try {
      final today = _today();
      state = RecurringState(
        rules: await service.listRules(vaultId),
        upcoming: await service.upcoming(
          vaultId: vaultId,
          from: today,
          through: today.addDays(90),
        ),
      );
    } catch (error) {
      state = RecurringState(
        rules: state.rules,
        upcoming: state.upcoming,
        error: error,
      );
    }
  }

  Future<void> create({
    required String name,
    required LedgerTransactionType type,
    required LedgerPocket source,
    required String amountText,
    required LocalDate startsOn,
    required RecurrencePattern pattern,
    required String timezone,
    EntityId? categoryId,
    LedgerPocket? destination,
    LocalDate? endsOn,
    String? title,
    String? notes,
  }) => _mutate(
    () => _requiredService.createEverydaySchedule(
      vaultId: _requiredVault,
      name: name,
      type: type,
      source: source,
      amount: _money(amountText, source.currency),
      startsOn: startsOn,
      pattern: pattern,
      timezone: timezone,
      now: UtcInstant.now(),
      categoryId: categoryId,
      destination: destination,
      endsOn: endsOn,
      title: title,
      notes: notes,
    ),
  );

  Future<void> confirm(ScheduledOccurrence occurrence) => _mutate(
    () => _requiredService.confirm(occurrence, now: UtcInstant.now()),
  );

  Future<void> skip(ScheduledOccurrence occurrence) =>
      _mutate(() => _requiredService.skip(occurrence, now: UtcInstant.now()));

  Future<void> reschedule(ScheduledOccurrence occurrence, LocalDate date) =>
      _mutate(
        () => _requiredService.reschedule(
          occurrence,
          newDate: date,
          now: UtcInstant.now(),
        ),
      );

  Future<void> modifyOne(
    ScheduledOccurrence occurrence, {
    required String amountText,
    required String title,
  }) {
    final replacement = _replacement(
      occurrence.template,
      amountText: amountText,
      title: title,
    );
    return _mutate(
      () => _requiredService.modifyOne(
        occurrence,
        replacement: replacement,
        now: UtcInstant.now(),
      ),
    );
  }

  Future<void> modifyFuture(
    ScheduledOccurrence occurrence, {
    required String amountText,
    required String title,
    required RecurrencePattern pattern,
  }) {
    final replacement = _replacement(
      occurrence.schedule.template,
      amountText: amountText,
      title: title,
    );
    return _mutate(
      () => _requiredService.modifyFuture(
        occurrence.schedule,
        effectiveFrom: occurrence.recurrenceDate,
        pattern: pattern,
        template: replacement,
        now: UtcInstant.now(),
      ),
    );
  }

  Future<void> end(RecurringSchedule schedule, LocalDate lastDate) => _mutate(
    () => _requiredService.end(
      schedule,
      lastDate: lastDate,
      now: UtcInstant.now(),
    ),
  );

  Future<void> delete(RecurringSchedule schedule) =>
      _mutate(() => _requiredService.delete(schedule, now: UtcInstant.now()));

  Future<bool> edit(
    RecurringSchedule schedule, {
    required String name,
    required LedgerPocket source,
    LedgerPocket? destination,
    required String amountText,
    EntityId? categoryId,
    required LocalDate effectiveFrom,
    required RecurrencePattern pattern,
    LocalDate? endsOn,
    String? title,
    String? notes,
  }) => _mutate(() {
    final now = UtcInstant.now();
    final amount = _money(amountText, source.currency);
    final type = schedule.template.transactionType;
    final engine = LedgerEngine();
    final prototype = switch (type) {
      LedgerTransactionType.expense => engine.expense(
        vaultId: _requiredVault,
        pocket: source,
        amount: amount,
        categoryId: categoryId!,
        date: effectiveFrom,
        now: now,
      ),
      LedgerTransactionType.income => engine.income(
        vaultId: _requiredVault,
        pocket: source,
        amount: amount,
        categoryId: categoryId!,
        date: effectiveFrom,
        now: now,
      ),
      LedgerTransactionType.transfer => engine.transfer(
        vaultId: _requiredVault,
        source: source,
        destination: destination!,
        amount: amount,
        date: effectiveFrom,
        now: now,
      ),
      _ => throw StateError('Unsupported recurrence type.'),
    };
    return _requiredService.modifyFuture(
      schedule,
      effectiveFrom: effectiveFrom,
      name: name,
      pattern: pattern,
      endsOn: endsOn,
      clearEndsOn: endsOn == null,
      now: now,
      template: RecurringTemplate(
        transactionType: type,
        movements: prototype.movements,
        splits: prototype.splits,
        title: title,
        notes: notes,
      ),
    );
  });

  RecurringTemplate _replacement(
    RecurringTemplate current, {
    required String amountText,
    required String title,
  }) {
    final currency = current.movements.first.pocket.currency;
    final amount = _money(amountText, currency).minorUnits;
    return RecurringTemplate(
      transactionType: current.transactionType,
      title: title.trim().isEmpty ? null : title.trim(),
      notes: current.notes,
      movements: current.movements
          .map(
            (movement) => LedgerMovement(
              id: EntityId.generate(),
              pocket: movement.pocket,
              amountMinor: movement.amountMinor < 0 ? -amount : amount,
              sortOrder: movement.sortOrder,
              statementId: movement.statementId,
            ),
          )
          .toList(growable: false),
      splits: current.splits
          .map(
            (split) => LedgerSplit(
              id: EntityId.generate(),
              categoryId: split.categoryId,
              money: Money(
                currency: split.money.currency,
                minorUnits: split.money.minorUnits < 0 ? -amount : amount,
              ),
              sortOrder: split.sortOrder,
              memo: split.memo,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<bool> _mutate(Future<Object?> Function() action) async {
    if (state.loading) return false;
    state = RecurringState(
      rules: state.rules,
      upcoming: state.upcoming,
      loading: true,
    );
    try {
      await action();
      await reload();
      return state.error == null;
    } catch (error) {
      state = RecurringState(
        rules: state.rules,
        upcoming: state.upcoming,
        error: error,
      );
      return false;
    }
  }

  RecurringTransactionService get _requiredService =>
      _service ?? (throw StateError('Recurring services are unavailable.'));

  EntityId get _requiredVault =>
      _vaultId ?? (throw StateError('A local vault is required.'));

  Money _money(String input, CurrencyCode currency) {
    var normalized = input.trim().replaceAll(RegExp(r'\s'), '');
    final comma = normalized.lastIndexOf(',');
    final dot = normalized.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      normalized = comma > dot
          ? normalized.replaceAll('.', '').replaceAll(',', '.')
          : normalized.replaceAll(',', '');
    } else if (comma >= 0) {
      normalized = normalized.replaceAll(',', '.');
    }
    final major = DecimalValue.parse(normalized);
    if (major <= Decimal.zero) throw ArgumentError('Amount must be positive.');
    return Money.fromMajor(
      currency: CurrencyDefinition(code: currency, minorUnits: 2),
      majorUnits: major,
    );
  }
}

LocalDate _today() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}
