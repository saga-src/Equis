import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../application/services/local_finance_session_service.dart';

final class TransactionDetailKey {
  const TransactionDetailKey({
    required this.vaultId,
    required this.transactionId,
  });

  final EntityId vaultId;
  final EntityId transactionId;

  @override
  bool operator ==(Object other) =>
      other is TransactionDetailKey &&
      other.vaultId == vaultId &&
      other.transactionId == transactionId;

  @override
  int get hashCode => Object.hash(vaultId, transactionId);
}

enum TransactionDetailStatus { loading, missing, error, ready }

final class TransactionDetailState {
  const TransactionDetailState._(this.status, {this.data, this.error});

  const TransactionDetailState.loading()
    : this._(TransactionDetailStatus.loading);

  const TransactionDetailState.missing()
    : this._(TransactionDetailStatus.missing);

  TransactionDetailState.error(Object error)
    : this._(TransactionDetailStatus.error, error: error);

  TransactionDetailState.ready(TransactionDetailData data)
    : this._(TransactionDetailStatus.ready, data: data);

  final TransactionDetailStatus status;
  final TransactionDetailData? data;
  LedgerTransaction? get transaction => data?.transaction;
  final Object? error;
}

final class TransactionDetailController
    extends StateNotifier<TransactionDetailState> {
  TransactionDetailController(this._load)
    : super(const TransactionDetailState.loading());

  final Future<TransactionDetailData?> Function() _load;
  int _generation = 0;

  Future<void> reload() async {
    if (!mounted) return;
    final generation = ++_generation;
    state = const TransactionDetailState.loading();
    try {
      final data = await _load();
      if (!mounted || generation != _generation) return;
      state = data == null
          ? const TransactionDetailState.missing()
          : TransactionDetailState.ready(data);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = TransactionDetailState.error(error);
    }
  }
}
