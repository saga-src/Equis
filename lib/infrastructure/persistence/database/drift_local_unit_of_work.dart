import '../../../application/ports/local_unit_of_work.dart';
import 'equis_database.dart';

final class DriftLocalUnitOfWork implements LocalUnitOfWork {
  const DriftLocalUnitOfWork(this.database);
  final EquisDatabase database;

  @override
  Future<T> run<T>(Future<T> Function() action) => database.transaction(action);
}
