import '../entities/account_profile.dart';
import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/uuid_v7.dart';

enum ReportClassification { income, expense }

enum DashboardRangePreset {
  thisMonth,
  lastMonth,
  lastThreeMonths,
  thisYear,
  custom,
}

enum CashFlowMode { daily, cumulative }

final class DashboardDateRange {
  DashboardDateRange({required this.from, required this.through}) {
    if (from.year < 1 || through.year > 9999 || from.compareTo(through) > 0) {
      throw ArgumentError('Invalid reporting range.');
    }
  }
  final LocalDate from;
  final LocalDate through;
  void validateAsOf(LocalDate asOf) {
    if (through.compareTo(asOf) > 0) {
      throw ArgumentError('A reporting range cannot end in the future.');
    }
  }
}

final class DashboardSelection {
  const DashboardSelection({
    this.preset = DashboardRangePreset.thisMonth,
    this.customRange,
    this.mode = CashFlowMode.daily,
  });
  final DashboardRangePreset preset;
  final DashboardDateRange? customRange;
  final CashFlowMode mode;
  DashboardDateRange resolve(LocalDate today) {
    final range = switch (preset) {
      DashboardRangePreset.thisMonth => DashboardDateRange(
        from: LocalDate(today.year, today.month, 1),
        through: today,
      ),
      DashboardRangePreset.lastMonth => DashboardDateRange(
        from: LocalDate(
          today.month == 1 ? today.year - 1 : today.year,
          today.month == 1 ? 12 : today.month - 1,
          1,
        ),
        through: LocalDate(today.year, today.month, 1).addDays(-1),
      ),
      DashboardRangePreset.lastThreeMonths => DashboardDateRange(
        from: LocalDate(
          DateTime.utc(today.year, today.month - 2).year,
          DateTime.utc(today.year, today.month - 2).month,
          1,
        ),
        through: today,
      ),
      DashboardRangePreset.thisYear => DashboardDateRange(
        from: LocalDate(today.year, 1, 1),
        through: today,
      ),
      DashboardRangePreset.custom =>
        customRange ?? (throw ArgumentError('A custom interval is required.')),
    };
    range.validateAsOf(today);
    return range;
  }

  DashboardSelection withMode(CashFlowMode value) =>
      DashboardSelection(preset: preset, customRange: customRange, mode: value);
}

List<CashFlowPoint> cashFlowSeries(
  List<CashFlowPoint> daily,
  CashFlowMode mode,
) {
  if (mode == CashFlowMode.daily) return List.unmodifiable(daily);
  var income = 0, expense = 0;
  return List.unmodifiable([
    for (final point in daily)
      CashFlowPoint(
        date: point.date,
        incomeMinor: income += point.incomeMinor,
        expenseMinor: expense += point.expenseMinor,
      ),
  ]);
}

final class ReportingSplitRow {
  const ReportingSplitRow({
    required this.categoryId,
    required this.currency,
    required this.amountMinor,
    required this.date,
    required this.classification,
    this.tagIds = const [],
  });

  final EntityId categoryId;
  final CurrencyCode currency;
  final int amountMinor;
  final LocalDate date;
  final ReportClassification classification;
  final List<EntityId> tagIds;
}

final class ReportingAccountRow {
  const ReportingAccountRow({
    required this.accountId,
    required this.pocketId,
    required this.accountName,
    required this.type,
    required this.nature,
    required this.currency,
    required this.balanceMinor,
  });

  final EntityId accountId;
  final EntityId pocketId;
  final String accountName;
  final AccountType type;
  final AccountNature nature;
  final CurrencyCode currency;
  final int balanceMinor;
}

final class ReportingConversion {
  const ReportingConversion({required this.minorUnits, this.estimated = false});

  final int minorUnits;
  final bool estimated;
}

final class CategorySpending {
  const CategorySpending({required this.categoryId, required this.amountMinor});

  final EntityId categoryId;
  final int amountMinor;
}

final class TagSpending {
  const TagSpending({required this.tagId, required this.amountMinor});
  final EntityId? tagId;
  final int amountMinor;
}

final class CashFlowPoint {
  const CashFlowPoint({
    required this.date,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final LocalDate date;
  final int incomeMinor;
  final int expenseMinor;
  int get netMinor => incomeMinor - expenseMinor;
}

final class AccountReportBalance {
  const AccountReportBalance({
    required this.accountId,
    required this.pocketId,
    required this.accountName,
    required this.type,
    required this.nature,
    required this.currency,
    required this.originalMinor,
    required this.reportingMinor,
  });

  final EntityId accountId;
  final EntityId pocketId;
  final String accountName;
  final AccountType type;
  final AccountNature nature;
  final CurrencyCode currency;
  final int originalMinor;
  final int? reportingMinor;
}

final class DashboardSnapshot {
  DashboardSnapshot({
    required this.reportingCurrency,
    required this.periodStart,
    required this.periodEnd,
    required this.availableMoneyMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required List<CategorySpending> spendingByCategory,
    List<CategorySpending> incomeByCategory = const [],
    List<TagSpending> spendingByTag = const [],
    required List<CashFlowPoint> cashFlow,
    required List<AccountReportBalance> accountBalances,
    required Set<CurrencyCode> missingRates,
    required this.usesEstimatedRates,
    required this.upcomingCount,
    this.hasIncompleteAccounts = false,
  }) : spendingByTag = List.unmodifiable(spendingByTag),
       spendingByCategory = List.unmodifiable(spendingByCategory),
       incomeByCategory = List.unmodifiable(incomeByCategory),
       cashFlow = List.unmodifiable(cashFlow),
       accountBalances = List.unmodifiable(accountBalances),
       missingRates = Set.unmodifiable(missingRates);

  final CurrencyCode reportingCurrency;
  final LocalDate periodStart;
  final LocalDate periodEnd;
  final int availableMoneyMinor;
  final int incomeMinor;
  final int expenseMinor;
  final List<CategorySpending> spendingByCategory;
  final List<CategorySpending> incomeByCategory;
  final List<TagSpending> spendingByTag;
  final List<CashFlowPoint> cashFlow;
  final List<AccountReportBalance> accountBalances;
  final Set<CurrencyCode> missingRates;
  final bool usesEstimatedRates;
  final int upcomingCount;
  final bool hasIncompleteAccounts;

  int get netCashFlowMinor => incomeMinor - expenseMinor;
  bool get isComplete => missingRates.isEmpty && !hasIncompleteAccounts;
}

bool isLiquidAccount(AccountType type) => const {
  AccountType.checking,
  AccountType.savings,
  AccountType.cash,
  AccountType.digitalWallet,
}.contains(type);
