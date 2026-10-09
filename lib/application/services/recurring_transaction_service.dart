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
import '../../domain/shared/zoned_recurrence.dart';
import 'package:timezone/timezone.dart' as tz;

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
      final occurrences = schedule.datesBetween(from, through);
      for (final recurrenceDate in occurrences) {
        final transaction =
            materialized[occurrenceKey(rule.id, recurrenceDate)];
        if (transaction != null) continue;
        result.add(
          ScheduledOccurrence(
            schedule: schedule.at(recurrenceDate),
            recurrenceDate: recurrenceDate,
            scheduledDate: transaction?.financialDate ?? recurrenceDate,
            state: _state(transaction),
            transaction: transaction,
          ),
        );
      }
      for (final transaction in materialized.values.where(
        (tx) => tx.recurringRuleId == rule.id,
      )) {
        if (transaction.financialDate.compareTo(from) < 0 ||
            transaction.financialDate.compareTo(through) > 0) {
          continue;
        }
        result.add(
          ScheduledOccurrence(
            schedule: schedule.at(transaction.recurrenceDate!),
            recurrenceDate: transaction.recurrenceDate!,
            scheduledDate: transaction.financialDate,
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
    final current = await _active(occurrence.schedule);
    late final LedgerTransaction confirmed;
    if (existing == null) {
      _requireProposed(current, occurrence.recurrenceDate);
      confirmed = _materialize(
        current.at(occurrence.recurrenceDate),
        recurrenceDate: occurrence.recurrenceDate,
        financialDate: occurrence.scheduledDate,
        status: LedgerTransactionStatus.cleared,
        now: now,
      );
    } else if (existing.deletedAt != null) {
      throw StateError('A deleted occurrence cannot be confirmed.');
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
    await _advance(current, occurrence.recurrenceDate, now);
    return confirmed;
  });

  Future<LedgerTransaction> skip(
    ScheduledOccurrence occurrence, {
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final existing = await _existing(occurrence);
    final current = await _active(occurrence.schedule);
    late final LedgerTransaction skipped;
    if (existing == null) {
      _requireProposed(current, occurrence.recurrenceDate);
      skipped = _materialize(
        current.at(occurrence.recurrenceDate),
        recurrenceDate: occurrence.recurrenceDate,
        financialDate: occurrence.scheduledDate,
        status: LedgerTransactionStatus.cancelled,
        now: now,
      );
    } else if (existing.deletedAt != null) {
      return existing;
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
    await _advance(current, occurrence.recurrenceDate, now);
    return skipped;
  });

  Future<LedgerTransaction> reschedule(
    ScheduledOccurrence occurrence, {
    required LocalDate newDate,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final current = await _active(occurrence.schedule);
    final existing = await _existing(occurrence);
    late final LedgerTransaction pending;
    if (existing == null) {
      _requireProposed(current, occurrence.recurrenceDate);
      pending = _materialize(
        current.at(occurrence.recurrenceDate),
        recurrenceDate: occurrence.recurrenceDate,
        financialDate: newDate,
        status: LedgerTransactionStatus.pending,
        now: now,
      );
    } else if (existing.status == LedgerTransactionStatus.pending &&
        existing.deletedAt == null) {
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
  });

  Future<LedgerTransaction> modifyOne(
    ScheduledOccurrence occurrence, {
    required RecurringTemplate replacement,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final current = await _active(occurrence.schedule);
    final candidateSchedule = RecurringSchedule(
      rule: current.rule,
      template: replacement,
    );
    _validateTemplate(candidateSchedule);
    final existing = await _existing(occurrence);
    if (existing == null) {
      _requireProposed(current, occurrence.recurrenceDate);
    }
    final candidate = _materialize(
      candidateSchedule,
      recurrenceDate: occurrence.recurrenceDate,
      financialDate: occurrence.scheduledDate,
      status: LedgerTransactionStatus.pending,
      now: now,
    );
    final modified = existing == null
        ? candidate
        : existing.status != LedgerTransactionStatus.pending ||
              existing.deletedAt != null
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
  });

  Future<RecurringSchedule> modifyFuture(
    RecurringSchedule current, {
    required LocalDate effectiveFrom,
    RecurrencePattern? pattern,
    RecurringTemplate? template,
    String? name,
    LocalDate? endsOn,
    bool clearEndsOn = false,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final latest = await _active(current, expectedRevision: true);
    ZonedRecurrenceClock.initialize();
    final clock = tz.TZDateTime.from(
      now.toDateTime(),
      tz.getLocation(latest.rule.timezone),
    );
    final today = LocalDate(clock.year, clock.month, clock.day);
    if (effectiveFrom.compareTo(latest.rule.startsOn) < 0 ||
        effectiveFrom.compareTo(today) < 0) {
      throw ArgumentError(
        'Modification cannot precede today or the series start.',
      );
    }
    final previous = latest.configurationAt(effectiveFrom);
    final selectedPattern = pattern ?? previous.pattern;
    final selectedTemplate = _cloneTemplate(template ?? previous.template);
    final selectedEnd = clearEndsOn ? null : endsOn ?? previous.endsOn;
    if (selectedEnd != null && selectedEnd.compareTo(effectiveFrom) < 0) {
      throw ArgumentError('End must follow the effective date.');
    }
    if (selectedTemplate.transactionType != previous.template.transactionType ||
        selectedTemplate.movements.any(
          (movement) =>
              movement.pocket.currency !=
              previous.template.movements.first.pocket.currency,
        )) {
      throw ArgumentError(
        'The transaction type and currency must remain unchanged.',
      );
    }
    final versions = [
      ...latest.configurations.where(
        (version) => version.effectiveFrom.compareTo(effectiveFrom) < 0,
      ),
      RecurringRuleVersion(
        effectiveFrom: effectiveFrom,
        anchorOn:
            selectedPattern.frequency == previous.pattern.frequency &&
                selectedPattern.interval == previous.pattern.interval
            ? previous.anchorOn
            : effectiveFrom,
        name: name ?? previous.name,
        pattern: selectedPattern,
        endsOn: selectedEnd,
        template: selectedTemplate,
      ),
    ];
    if (versions.last.name.trim().isEmpty) {
      throw ArgumentError('A name is required.');
    }
    final revised = RecurringSchedule(
      rule: latest.rule.revise(scheduleHistoryEdited: true, at: now),
      template: latest.template,
      versions: versions,
    );
    _validateTemplate(revised.at(effectiveFrom));
    final next = await _next(revised, today);
    final saved = RecurringSchedule(
      rule: latest.rule.revise(
        scheduleHistoryEdited: true,
        nextOccurrence: next,
        clearNextOccurrence: next == null,
        at: now,
      ),
      template: latest.template,
      versions: versions,
    );
    await repository.save(saved);
    return saved;
  });

  Future<void> end(
    RecurringSchedule schedule, {
    required LocalDate lastDate,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final latest = await _active(schedule, expectedRevision: true);
    if (lastDate.compareTo(latest.rule.startsOn) < 0) {
      throw ArgumentError('End precedes start.');
    }
    await repository.save(
      RecurringSchedule(
        rule: latest.rule.revise(
          endsOn: lastDate,
          enabled: false,
          clearNextOccurrence: true,
          at: now,
        ),
        template: latest.template,
        versions: latest.versions,
      ),
    );
  });

  Future<void> delete(RecurringSchedule schedule, {required UtcInstant now}) =>
      unitOfWork.run(() async {
        final latest = await repository.find(schedule.rule.id);
        if (latest == null ||
            latest.rule.vaultId != schedule.rule.vaultId ||
            latest.rule.revision != schedule.rule.revision ||
            latest.rule.deletedAt != null) {
          throw RecurringRevisionConflict(schedule.rule.id);
        }
        await repository.save(
          RecurringSchedule(
            rule: latest.rule.revise(
              enabled: false,
              clearNextOccurrence: true,
              deletedAt: now,
              at: now,
            ),
            template: latest.template,
            versions: latest.versions,
          ),
        );
      });

  Future<RecurringSchedule> _active(
    RecurringSchedule expected, {
    bool expectedRevision = false,
  }) async {
    final current = await repository.find(expected.rule.id);
    if (current == null ||
        current.rule.vaultId != expected.rule.vaultId ||
        current.rule.deletedAt != null ||
        !current.rule.enabled ||
        (expectedRevision && current.rule.revision != expected.rule.revision)) {
      throw RecurringRevisionConflict(expected.rule.id);
    }
    return current;
  }

  Future<LocalDate?> _next(RecurringSchedule schedule, LocalDate from) async {
    // Scan bounded chunks: occupied nominal keys, including cancelled/deleted rows,
    // must never become new proposals.
    var cursor = from;
    while (cursor.year <= 9999) {
      final dates = schedule.datesBetween(
        cursor,
        LocalDate(9999, 12, 31),
        limit: 200,
      );
      if (dates.isEmpty) return null;
      final occupied = await repository.materializedOccurrences(
        ruleIds: {schedule.rule.id},
        from: dates.first,
        through: dates.last,
      );
      for (final date in dates) {
        if (!occupied.containsKey(occurrenceKey(schedule.rule.id, date))) {
          return date;
        }
      }
      if (dates.last == LocalDate(9999, 12, 31)) return null;
      cursor = dates.last.addDays(1);
    }
    return null;
  }

  void _requireProposed(RecurringSchedule current, LocalDate date) {
    if (!current.datesBetween(date, date).contains(date)) {
      throw StateError(
        'This occurrence no longer belongs to the current schedule.',
      );
    }
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
    final next = await _next(schedule, occurrence.addDays(1));
    await repository.save(
      RecurringSchedule(
        rule: schedule.rule.revise(
          nextOccurrence: next,
          clearNextOccurrence: next == null,
          at: now,
        ),
        template: schedule.template,
        versions: schedule.versions,
      ),
    );
  }

  Future<LedgerTransaction?> _existing(ScheduledOccurrence occurrence) async {
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
