import '../ledger/ledger_models.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum RecurrenceFrequency { daily, weekly, monthly, yearly }

final class RecurrencePattern {
  const RecurrencePattern({required this.frequency, this.interval = 1})
    : assert(interval > 0);

  final RecurrenceFrequency frequency;
  final int interval;

  factory RecurrencePattern.parse(String value) {
    final entries = <String, String>{};
    for (final component in value.split(';')) {
      final separator = component.indexOf('=');
      if (separator <= 0 || separator == component.length - 1) {
        throw FormatException('Invalid recurrence rule.', value);
      }
      entries[component.substring(0, separator).toUpperCase()] = component
          .substring(separator + 1)
          .toUpperCase();
    }
    final frequency = switch (entries['FREQ']) {
      'DAILY' => RecurrenceFrequency.daily,
      'WEEKLY' => RecurrenceFrequency.weekly,
      'MONTHLY' => RecurrenceFrequency.monthly,
      'YEARLY' => RecurrenceFrequency.yearly,
      _ => throw FormatException('Unsupported recurrence frequency.', value),
    };
    final interval = int.tryParse(entries['INTERVAL'] ?? '1');
    if (interval == null || interval < 1 || interval > 999) {
      throw FormatException('Invalid recurrence interval.', value);
    }
    return RecurrencePattern(frequency: frequency, interval: interval);
  }

  String serialize(LocalDate anchor) {
    final parts = <String>[
      'FREQ=${frequency.name.toUpperCase()}',
      if (interval != 1) 'INTERVAL=$interval',
      if (frequency == RecurrenceFrequency.monthly) 'BYMONTHDAY=${anchor.day}',
      if (frequency == RecurrenceFrequency.yearly) ...[
        'BYMONTH=${anchor.month}',
        'BYMONTHDAY=${anchor.day}',
      ],
    ];
    return parts.join(';');
  }

  LocalDate occurrenceAt(LocalDate anchor, int index) {
    if (index < 0) throw RangeError.value(index, 'index');
    return switch (frequency) {
      RecurrenceFrequency.daily => anchor.addDays(index * interval),
      RecurrenceFrequency.weekly => anchor.addDays(index * interval * 7),
      RecurrenceFrequency.monthly => _monthOccurrence(anchor, index * interval),
      RecurrenceFrequency.yearly => _yearOccurrence(anchor, index * interval),
    };
  }

  List<LocalDate> between({
    required LocalDate anchor,
    required LocalDate from,
    required LocalDate through,
    required int limit,
  }) {
    if (limit < 1 || limit > 1000) {
      throw RangeError.range(limit, 1, 1000, 'limit');
    }
    if (from.compareTo(through) > 0) return const [];
    var index = _estimatedIndex(anchor, from);
    final result = <LocalDate>[];
    while (result.length < limit) {
      final occurrence = occurrenceAt(anchor, index);
      if (occurrence.compareTo(through) > 0) break;
      if (occurrence.compareTo(from) >= 0) result.add(occurrence);
      index++;
    }
    return result;
  }

  int _estimatedIndex(LocalDate anchor, LocalDate from) {
    if (from.compareTo(anchor) <= 0) return 0;
    return switch (frequency) {
      RecurrenceFrequency.daily =>
        from.toUtcDate().difference(anchor.toUtcDate()).inDays ~/ interval,
      RecurrenceFrequency.weekly =>
        from.toUtcDate().difference(anchor.toUtcDate()).inDays ~/
            (7 * interval),
      RecurrenceFrequency.monthly =>
        (((from.year - anchor.year) * 12 + from.month - anchor.month) ~/
                interval)
            .clamp(0, 1 << 30),
      RecurrenceFrequency.yearly =>
        ((from.year - anchor.year) ~/ interval).clamp(0, 1 << 30),
    };
  }
}

final class RecurringRule {
  RecurringRule({
    required this.id,
    required this.vaultId,
    required this.name,
    required this.pattern,
    required this.timezone,
    required this.startsOn,
    required this.createdAt,
    required this.updatedAt,
    this.endsOn,
    this.enabled = true,
    this.nextOccurrence,
    this.revision = 1,
    this.deletedAt,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (timezone.trim().isEmpty) {
      throw ArgumentError.value(timezone, 'timezone');
    }
    if (endsOn != null && endsOn!.compareTo(startsOn) < 0) {
      throw ArgumentError('Recurrence end cannot precede its start.');
    }
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final String name;
  final RecurrencePattern pattern;
  final String timezone;
  final LocalDate startsOn;
  final LocalDate? endsOn;
  final bool enabled;
  final LocalDate? nextOccurrence;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  RecurringRule revise({
    String? name,
    RecurrencePattern? pattern,
    String? timezone,
    LocalDate? startsOn,
    LocalDate? endsOn,
    bool? enabled,
    LocalDate? nextOccurrence,
    bool clearNextOccurrence = false,
    required UtcInstant at,
  }) => RecurringRule(
    id: id,
    vaultId: vaultId,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    timezone: timezone ?? this.timezone,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn ?? this.endsOn,
    enabled: enabled ?? this.enabled,
    nextOccurrence: clearNextOccurrence
        ? null
        : nextOccurrence ?? this.nextOccurrence,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}

final class RecurringTemplate {
  const RecurringTemplate({
    required this.transactionType,
    required this.movements,
    required this.splits,
    this.title,
    this.notes,
  });

  final LedgerTransactionType transactionType;
  final List<LedgerMovement> movements;
  final List<LedgerSplit> splits;
  final String? title;
  final String? notes;
}

final class RecurringSchedule {
  const RecurringSchedule({required this.rule, required this.template});

  final RecurringRule rule;
  final RecurringTemplate template;
}

enum ScheduledOccurrenceState { scheduled, pending, confirmed, skipped }

final class ScheduledOccurrence {
  const ScheduledOccurrence({
    required this.schedule,
    required this.recurrenceDate,
    required this.scheduledDate,
    required this.state,
    this.transaction,
  });

  final RecurringSchedule schedule;
  final LocalDate recurrenceDate;
  final LocalDate scheduledDate;
  final ScheduledOccurrenceState state;
  final LedgerTransaction? transaction;
}

LocalDate _monthOccurrence(LocalDate anchor, int monthOffset) {
  final zeroBased = anchor.year * 12 + anchor.month - 1 + monthOffset;
  final year = zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  return LocalDate(year, month, anchor.day.clamp(1, _daysInMonth(year, month)));
}

LocalDate _yearOccurrence(LocalDate anchor, int yearOffset) {
  final year = anchor.year + yearOffset;
  return LocalDate(
    year,
    anchor.month,
    anchor.day.clamp(1, _daysInMonth(year, anchor.month)),
  );
}

int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;
