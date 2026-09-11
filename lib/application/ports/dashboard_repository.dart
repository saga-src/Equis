import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class DashboardRepository {
  void beginRead();

  Future<List<ReportingSplitRow>> loadSplits({
    required EntityId vaultId,
    required LocalDate from,
    required LocalDate through,
    required LocalDate asOf,
  });

  Future<List<ReportingAccountRow>> loadAccountBalances({
    required EntityId vaultId,
    required LocalDate asOf,
  });

  Future<ReportingConversion?> convertMinor({
    required EntityId vaultId,
    required CurrencyCode source,
    required CurrencyCode target,
    required LocalDate date,
    required int amountMinor,
  });

  Future<int> countUpcomingInstallments({
    required EntityId vaultId,
    required LocalDate after,
    required LocalDate through,
  });
}
