import '../shared/currency.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';
import 'ledger_models.dart';

final class TransactionSearchCursor {
  const TransactionSearchCursor({
    required this.financialDate,
    required this.createdAt,
    required this.id,
  });

  final LocalDate financialDate;
  final UtcInstant createdAt;
  final EntityId id;
}

final class TransactionSearchFilter {
  TransactionSearchFilter({
    required this.vaultId,
    this.merchantQuery,
    this.notesQuery,
    this.minimumAmountMinor,
    this.maximumAmountMinor,
    this.fromDate,
    this.toDate,
    this.accountId,
    this.categoryId,
    this.includeDescendantCategories = false,
    this.tagId,
    this.withoutTags = false,
    this.reportingExpensesOnly = false,
    this.currency,
    this.types = const {},
    this.statuses = const {},
    this.cursor,
    this.pageSize = 50,
  }) {
    if (pageSize < 1 || pageSize > 100) {
      throw RangeError.range(pageSize, 1, 100, 'pageSize');
    }
    if (minimumAmountMinor != null && minimumAmountMinor! < 0) {
      throw RangeError.value(minimumAmountMinor!, 'minimumAmountMinor');
    }
    if (maximumAmountMinor != null && maximumAmountMinor! < 0) {
      throw RangeError.value(maximumAmountMinor!, 'maximumAmountMinor');
    }
    if (minimumAmountMinor != null &&
        maximumAmountMinor != null &&
        minimumAmountMinor! > maximumAmountMinor!) {
      throw ArgumentError('Minimum amount cannot exceed maximum amount.');
    }
    if (fromDate != null &&
        toDate != null &&
        fromDate!.compareTo(toDate!) > 0) {
      throw ArgumentError('Start date cannot be after end date.');
    }
  }

  final EntityId vaultId;
  final String? merchantQuery;
  final String? notesQuery;
  final int? minimumAmountMinor;
  final int? maximumAmountMinor;
  final LocalDate? fromDate;
  final LocalDate? toDate;
  final EntityId? accountId;
  final EntityId? categoryId;
  final bool includeDescendantCategories;
  final EntityId? tagId;
  final bool withoutTags;
  final bool reportingExpensesOnly;
  final CurrencyCode? currency;
  final Set<LedgerTransactionType> types;
  final Set<LedgerTransactionStatus> statuses;
  final TransactionSearchCursor? cursor;
  final int pageSize;

  TransactionSearchFilter nextPage(TransactionSearchCursor value) =>
      TransactionSearchFilter(
        vaultId: vaultId,
        merchantQuery: merchantQuery,
        notesQuery: notesQuery,
        minimumAmountMinor: minimumAmountMinor,
        maximumAmountMinor: maximumAmountMinor,
        fromDate: fromDate,
        toDate: toDate,
        accountId: accountId,
        categoryId: categoryId,
        includeDescendantCategories: includeDescendantCategories,
        tagId: tagId,
        withoutTags: withoutTags,
        reportingExpensesOnly: reportingExpensesOnly,
        currency: currency,
        types: types,
        statuses: statuses,
        cursor: value,
        pageSize: pageSize,
      );
}

final class TransactionSearchPage {
  const TransactionSearchPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<LedgerTransaction> items;
  final bool hasMore;
  final TransactionSearchCursor? nextCursor;
}
