import '../../domain/ledger/transaction_search.dart';

abstract interface class TransactionHistoryRepository {
  Future<TransactionSearchPage> search(TransactionSearchFilter filter);
}
