import '../entities/account_profile.dart';
import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/uuid_v7.dart';

enum ReportClassification { income, expense }

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
    List<TagSpending> spendingByTag = const [],
    required List<CashFlowPoint> cashFlow,
    required List<AccountReportBalance> accountBalances,
    required Set<CurrencyCode> missingRates,
    required this.usesEstimatedRates,
    required this.upcomingCount,
  }) : spendingByTag = List.unmodifiable(spendingByTag),
       spendingByCategory = List.unmodifiable(spendingByCategory),
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
  final List<TagSpending> spendingByTag;
  final List<CashFlowPoint> cashFlow;
  final List<AccountReportBalance> accountBalances;
  final Set<CurrencyCode> missingRates;
  final bool usesEstimatedRates;
  final int upcomingCount;

  int get netCashFlowMinor => incomeMinor - expenseMinor;
  bool get isComplete => missingRates.isEmpty;
}

bool isLiquidAccount(AccountType type) => const {
  AccountType.checking,
  AccountType.savings,
  AccountType.cash,
  AccountType.digitalWallet,
}.contains(type);
