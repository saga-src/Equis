final class PrivacySafeLogEvent {
  const PrivacySafeLogEvent({
    required this.component,
    required this.event,
    this.attributes = const {},
  });

  final String component;
  final String event;
  final Map<String, Object?> attributes;
}
