final class UtcInstant implements Comparable<UtcInstant> {
  const UtcInstant.fromEpochMicroseconds(this.epochMicroseconds);

  factory UtcInstant.fromDateTime(DateTime value) =>
      UtcInstant.fromEpochMicroseconds(value.toUtc().microsecondsSinceEpoch);

  factory UtcInstant.now() => UtcInstant.fromDateTime(DateTime.now());

  final int epochMicroseconds;

  DateTime toDateTime() =>
      DateTime.fromMicrosecondsSinceEpoch(epochMicroseconds, isUtc: true);

  @override
  int compareTo(UtcInstant other) =>
      epochMicroseconds.compareTo(other.epochMicroseconds);

  @override
  bool operator ==(Object other) =>
      other is UtcInstant && other.epochMicroseconds == epochMicroseconds;

  @override
  int get hashCode => epochMicroseconds.hashCode;
}
