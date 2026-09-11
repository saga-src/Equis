import '../../application/ports/transaction_history_repository.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/ledger/transaction_search.dart';
import '../../domain/shared/uuid_v7.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class TransactionHistoryState {
  const TransactionHistoryState({
    this.items = const [],
    this.filter,
    this.nextCursor,
    this.hasMore = false,
    this.loading = false,
    this.error,
  });

  final List<LedgerTransaction> items;
  final TransactionSearchFilter? filter;
  final TransactionSearchCursor? nextCursor;
  final bool hasMore;
  final bool loading;
  final Object? error;

  TransactionHistoryState copyWith({
    List<LedgerTransaction>? items,
    TransactionSearchFilter? filter,
    TransactionSearchCursor? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) => TransactionHistoryState(
    items: items ?? this.items,
    filter: filter ?? this.filter,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
  );
}

final class TransactionHistoryController
    extends StateNotifier<TransactionHistoryState> {
  TransactionHistoryController({
    required TransactionHistoryRepository? repository,
    required EntityId? vaultId,
  }) : this._(repository, vaultId);

  TransactionHistoryController._(this._repository, this._vaultId)
    : super(const TransactionHistoryState());

  final TransactionHistoryRepository? _repository;
  final EntityId? _vaultId;
  int _generation = 0;

  Future<void> refresh() async {
    final filter = state.filter;
    if (filter != null) await apply(filter);
  }

  Future<void> loadInitial() async {
    final vaultId = _vaultId;
    if (_repository == null || vaultId == null) return;
    await apply(TransactionSearchFilter(vaultId: vaultId));
  }

  Future<void> apply(TransactionSearchFilter filter) async {
    if (_repository == null) return;
    final generation = ++_generation;
    state = state.copyWith(
      filter: filter,
      items: const [],
      hasMore: false,
      loading: true,
      clearCursor: true,
      clearError: true,
    );
    try {
      final page = await _repository.search(filter);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        loading: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(error: error, loading: false);
    }
  }

  Future<void> loadMore() async {
    final filter = state.filter;
    final cursor = state.nextCursor;
    if (_repository == null ||
        filter == null ||
        cursor == null ||
        state.loading ||
        !state.hasMore) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repository.search(filter.nextPage(cursor));
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        loading: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(error: error, loading: false);
    }
  }
}
