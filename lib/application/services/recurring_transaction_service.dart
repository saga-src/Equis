import '../ports/ledger_repository.dart';
import '../ports/local_unit_of_work.dart';
import '../ports/recurring_repository.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/ledger/ledger_engine.dart';
import '../../domain/shared/money.dart';
import '../../domain/recurring/recurrence_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class RecurringTransactionService {
  const RecurringTransactionService({
    required this.repository,
    required this.ledger,
    required this.unitOfWork,
  });

  final RecurringRepository repository;
  final LedgerRepository ledger;
  final LocalUnitOfWork unitOfWork;

  Future<RecurringSchedule> createEverydaySchedule({
    required EntityId vaultId,
    required String name,
    required LedgerTransactionType type,
    required LedgerPocket source,
    required Money amount,
    required LocalDate startsOn,
    required RecurrencePattern pattern,
    required String timezone,
    required UtcInstant now,
    EntityId? categoryId,
    LedgerPocket? destination,
    LocalDate? endsOn,
    String? title,
    String? notes,
  }) async {
    final engine = LedgerEngine();
    final prototype = switch (type) {
      LedgerTransactionType.expense => engine.expense(
        vaultId: vaultId,
        pocket: source,
        amount: amount,
        categoryId:
            categoryId ?? (throw ArgumentError('An expense needs a category.')),
        date: startsOn,
        now: now,
      ),
      LedgerTransactionType.income => engine.income(
        vaultId: vaultId,
        pocket: source,
        amount: amount,
        categoryId:
            categoryId ?? (throw ArgumentError('Income needs a category.')),
        date: startsOn,
        now: now,
      ),
      LedgerTransactionType.transfer => engine.transfer(
        vaultId: vaultId,
        source: source,
        destination:
            destination ??
            (throw ArgumentError('A transfer needs a destination.')),
        amount: amount,
        date: startsOn,
        now: now,
      ),
      _ => throw ArgumentError('Unsupported everyday recurring type: $type'),
    };
    final schedule = RecurringSchedule(
      rule: RecurringRule(
        id: EntityId.generate(),
        vaultId: vaultId,
        name: name,
        pattern: pattern,
        timezone: timezone,
        startsOn: startsOn,
        endsOn: endsOn,
        nextOccurrence: startsOn,
        createdAt: now,
        updatedAt: now,
      ),
      template: RecurringTemplate(
        transactionType: type,
        movements: prototype.movements,
        splits: prototype.splits,
        title: title,
        notes: notes,
      ),
    );
    await create(schedule);
    return schedule;
  }

  Future<void> create(RecurringSchedule schedule) async {
    _validateTemplate(schedule);
    await repository.save(schedule);
  }

  Future<List<RecurringSchedule>> listRules(EntityId vaultId) =>
      repository.listForVault(vaultId);

  Future<List<ScheduledOccurrence>> upcoming({
    required EntityId vaultId,
    required LocalDate from,
    required LocalDate through,
    int limit = 100,
  }) async {
    final days = through.toUtcDate().difference(from.toUtcDate()).inDays;
    if (days < 0 || days > 366) {
      throw RangeError.range(days, 0, 366, 'scheduled window days');
    }
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    final schedules = (await repository.listForVault(
      vaultId,
    )).where((schedule) => schedule.rule.enabled).toList(growable: false);
    final materialized = await repository.materializedOccurrences(
      ruleIds: schedules.map((schedule) => schedule.rule.id).toSet(),
      from: from,
      through: through,
    );
    final result = <ScheduledOccurrence>[];
    for (final schedule in schedules) {
      final rule = schedule.rule;
      final effectiveThrough =
          rule.endsOn != null && rule.endsOn!.compareTo(through) < 0
          ? rule.endsOn!
          : through;
      if (effectiveThrough.compareTo(rule.startsOn) < 0) continue;
      final occurrences = rule.pattern.between(
        anchor: rule.startsOn,
        from: from.compareTo(rule.startsOn) < 0 ? rule.startsOn : from,
        through: effectiveThrough,
        limit: limit,
      );
      for (final recurrenceDate in occurrences) {
        final transaction =
            materialized[occurrenceKey(rule.id, recurrenceDate)];
        result.add(
          ScheduledOccurrence(
            schedule: schedule,
            recurrenceDate: recurrenceDate,
            scheduledDate: transaction?.financialDate ?? recurrenceDate,
            state: _state(transaction),
            transaction: transaction,
          ),
        );
      }
    }
    result.sort((left, right) {
      final byDate = left.scheduledDate.compareTo(right.scheduledDate);
      if (byDate != 0) return byDate;
      return left.schedule.rule.id.value.compareTo(
        right.schedule.rule.id.value,
      );
    });
    return result.take(limit).toList(growable: false);
  }

  Future<LedgerTransaction> confirm(
    ScheduledOccurrence occurrence, {
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final existing = await _existing(occurrence);
    late final LedgerTransaction confirmed;
    if (existing == null) {
      confirmed = _materialize(
        occurrence.schedule,
        recurrenceDate: occurrence.recurrenceDate,
        financialDate: occurrence.scheduledDate,
        status: LedgerTransactionStatus.cleared,
        now: now,
      );
    } else if (existing.status == LedgerTransactionStatus.pending) {
      confirmed = existing.transitionTo(
        LedgerTransactionStatus.cleared,
        at: now,
      );
    } else if (existing.status == LedgerTransactionStatus.cleared ||
        existing.status == LedgerTransactionStatus.reconciled) {
      return existing;
    } else {
      throw StateError('A skipped occurrence cannot be confirmed.');
    }
    await ledger.save(confirmed);
    await _advance(occurrence.schedule, occurrence.recurrenceDate, now);
    return confirmed;
  });

  Future<LedgerTransaction> skip(
    ScheduledOccurrence occurrence, {
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final existing = await _existing(occurrence);
    late final LedgerTransaction skipped;
    if (existing == null) {
      skipped = _materialize(
        occurrence.schedule,
        recurrenceDate: occurrence.recurrenceDate,
        financialDate: occurrence.scheduledDate,
        status: LedgerTransactionStatus.cancelled,
        now: now,
      );
    } else if (existing.status == LedgerTransactionStatus.pending) {
      skipped = existing.transitionTo(
        LedgerTransactionStatus.cancelled,
        at: now,
      );
    } else if (existing.status == LedgerTransactionStatus.cancelled ||
        existing.deletedAt != null) {
      return existing;
    } else {
      throw StateError('A confirmed occurrence cannot be skipped.');
    }
    await ledger.save(skipped);
    await _advance(occurrence.schedule, occurrence.recurrenceDate, now);
    return skipped;
  });

  Future<LedgerTransaction> reschedule(
    ScheduledOccurrence occurrence, {
    required LocalDate newDate,
    required UtcInstant now,
  }) async {
    final existing = await _existing(occurrence);
    late final LedgerTransaction pending;
    if (existing == null) {
      pending = _materialize(
        occurrence.schedule,
        recurrenceDate: occurrence.recurrenceDate,
        financialDate: newDate,
        status: LedgerTransactionStatus.pending,
        now: now,
      );
    } else if (existing.status == LedgerTransactionStatus.pending) {
      pending = existing.revise(
        movements: existing.movements,
        splits: existing.splits,
        financialDate: newDate,
        title: existing.title,
        notes: existing.notes,
        tagIds: existing.tagIds,
        at: now,
      );
    } else {
      throw StateError('Only an unconfirmed occurrence can be rescheduled.');
    }
    await ledger.save(pending);
    return pending;
  }

  Future<LedgerTransaction> modifyOne(
    ScheduledOccurrence occurrence, {
    required RecurringTemplate replacement,
    required UtcInstant now,
  }) async {
    final candidateSchedule = RecurringSchedule(
      rule: occurrence.schedule.rule,
      template: replacement,
    );
    _validateTemplate(candidateSchedule);
    final existing = await _existing(occurrence);
    final candidate = _materialize(
      candidateSchedule,
      recurrenceDate: occurrence.recurrenceDate,
      financialDate: occurrence.scheduledDate,
      status: LedgerTransactionStatus.pending,
      now: now,
    );
    final modified = existing == null
        ? candidate
        : existing.status != LedgerTransactionStatus.pending
        ? (throw StateError('Only an unconfirmed occurrence can be modified.'))
        : existing.type != candidate.type
        ? (throw StateError('One occurrence cannot change transaction type.'))
        : existing.revise(
            movements: candidate.movements,
            splits: candidate.splits,
            financialDate: candidate.financialDate,
            title: candidate.title,
            notes: candidate.notes,
            at: now,
          );
    await ledger.save(modified);
    return modified;
  }

  Future<RecurringSchedule> modifyFuture(
    RecurringSchedule current, {
    required LocalDate effectiveFrom,
    RecurrencePattern? pattern,
    RecurringTemplate? template,
    String? name,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    if (effectiveFrom.compareTo(current.rule.startsOn) < 0) {
      throw ArgumentError(
        'Future modification cannot precede the series start.',
      );
    }
    if (effectiveFrom == current.rule.startsOn) {
      final replacement = RecurringSchedule(
        rule: current.rule.revise(
          name: name,
          pattern: pattern,
          nextOccurrence: effectiveFrom,
          at: now,
        ),
        template: _cloneTemplate(template ?? current.template),
      );
      _validateTemplate(replacement);
      await repository.save(replacement);
      return replacement;
    }
    final clearPredecessorNext =
        current.rule.nextOccurrence != null &&
        current.rule.nextOccurrence!.compareTo(effectiveFrom) >= 0;
    final predecessor = current.rule.revise(
      endsOn: effectiveFrom.addDays(-1),
      nextOccurrence: current.rule.nextOccurrence,
      clearNextOccurrence: clearPredecessorNext,
      at: now,
    );
    await repository.save(
      RecurringSchedule(rule: predecessor, template: current.template),
    );
    final successorTemplate = _cloneTemplate(template ?? current.template);
    final successor = RecurringSchedule(
      rule: RecurringRule(
        id: EntityId.generate(),
        vaultId: current.rule.vaultId,
        name: name ?? current.rule.name,
        pattern: pattern ?? current.rule.pattern,
        timezone: current.rule.timezone,
        startsOn: effectiveFrom,
        endsOn: current.rule.endsOn,
        nextOccurrence: effectiveFrom,
        createdAt: now,
        updatedAt: now,
      ),
      template: successorTemplate,
    );
    _validateTemplate(successor);
    await repository.save(successor);
    return successor;
  });

  Future<void> end(
    RecurringSchedule schedule, {
    required LocalDate lastDate,
    required UtcInstant now,
  }) async {
    if (lastDate.compareTo(schedule.rule.startsOn) < 0) {
      throw ArgumentError('End date cannot precede the series start.');
    }
    await repository.save(
      RecurringSchedule(
        rule: schedule.rule.revise(
          endsOn: lastDate,
          enabled: false,
          clearNextOccurrence: true,
          at: now,
        ),
        template: schedule.template,
      ),
    );
  }

  LedgerTransaction _materialize(
    RecurringSchedule schedule, {
    required LocalDate recurrenceDate,
    required LocalDate financialDate,
    required LedgerTransactionStatus status,
    required UtcInstant now,
  }) {
    final template = schedule.template;
    return LedgerTransaction(
      id: EntityId.generate(),
      vaultId: schedule.rule.vaultId,
      type: template.transactionType,
      status: status,
      financialDate: financialDate,
      movements: template.movements
          .map(
            (movement) => LedgerMovement(
              id: EntityId.generate(),
              pocket: movement.pocket,
              amountMinor: movement.amountMinor,
              sortOrder: movement.sortOrder,
              statementId: movement.statementId,
            ),
          )
          .toList(growable: false),
      splits: template.splits
          .map(
            (split) => LedgerSplit(
              id: EntityId.generate(),
              categoryId: split.categoryId,
              money: split.money,
              sortOrder: split.sortOrder,
              memo: split.memo,
            ),
          )
          .toList(growable: false),
      title: template.title,
      notes: template.notes,
      timezone: schedule.rule.timezone,
      recurringRuleId: schedule.rule.id,
      recurrenceDate: recurrenceDate,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _advance(
    RecurringSchedule schedule,
    LocalDate occurrence,
    UtcInstant now,
  ) async {
    final candidates = schedule.rule.pattern.between(
      anchor: schedule.rule.startsOn,
      from: occurrence.addDays(1),
      through: schedule.rule.endsOn ?? LocalDate(9999, 12, 31),
      limit: 1,
    );
    await repository.save(
      RecurringSchedule(
        rule: schedule.rule.revise(
          nextOccurrence: candidates.isEmpty ? null : candidates.single,
          clearNextOccurrence: candidates.isEmpty,
          at: now,
        ),
        template: schedule.template,
      ),
    );
  }

  Future<LedgerTransaction?> _existing(ScheduledOccurrence occurrence) async {
    if (occurrence.transaction != null) return occurrence.transaction;
    final rows = await repository.materializedOccurrences(
      ruleIds: {occurrence.schedule.rule.id},
      from: occurrence.recurrenceDate,
      through: occurrence.recurrenceDate,
    );
    return rows[occurrenceKey(
      occurrence.schedule.rule.id,
      occurrence.recurrenceDate,
    )];
  }

  void _validateTemplate(RecurringSchedule schedule) {
    _materialize(
      schedule,
      recurrenceDate: schedule.rule.startsOn,
      financialDate: schedule.rule.startsOn,
      status: LedgerTransactionStatus.pending,
      now: schedule.rule.createdAt,
    ).validate();
  }

  RecurringTemplate _cloneTemplate(RecurringTemplate template) =>
      RecurringTemplate(
        transactionType: template.transactionType,
        title: template.title,
        notes: template.notes,
        movements: template.movements
            .map(
              (movement) => LedgerMovement(
                id: EntityId.generate(),
                pocket: movement.pocket,
                amountMinor: movement.amountMinor,
                sortOrder: movement.sortOrder,
              ),
            )
            .toList(growable: false),
        splits: template.splits
            .map(
              (split) => LedgerSplit(
                id: EntityId.generate(),
                categoryId: split.categoryId,
                money: split.money,
                sortOrder: split.sortOrder,
                memo: split.memo,
              ),
            )
            .toList(growable: false),
      );
}

ScheduledOccurrenceState _state(LedgerTransaction? transaction) {
  if (transaction == null) return ScheduledOccurrenceState.scheduled;
  if (transaction.deletedAt != null ||
      transaction.status == LedgerTransactionStatus.cancelled) {
    return ScheduledOccurrenceState.skipped;
  }
  if (transaction.status == LedgerTransactionStatus.pending) {
    return ScheduledOccurrenceState.pending;
  }
  return ScheduledOccurrenceState.confirmed;
}
