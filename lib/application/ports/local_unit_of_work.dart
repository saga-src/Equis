abstract interface class LocalUnitOfWork {
  Future<T> run<T>(Future<T> Function() action);
}
