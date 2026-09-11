sealed class AppFailure {
  const AppFailure({required this.code});

  final String code;
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure({required super.code, this.field});

  final String? field;
}

final class PersistenceFailure extends AppFailure {
  const PersistenceFailure({required super.code, this.retryable = false});

  final bool retryable;
}

final class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure({required super.code});
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure({required super.code});
}
