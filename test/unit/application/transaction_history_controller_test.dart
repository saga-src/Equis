import 'dart:async';
import 'package:equis/application/ports/transaction_history_repository.dart';
import 'package:equis/domain/ledger/transaction_search.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/presentation/history/transaction_history_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a report filter supersedes the initial history request', () async {
    final repository = _DelayedHistory();
    final vault = EntityId.generate();
    final controller = TransactionHistoryController(
      repository: repository,
      vaultId: vault,
    );
    addTearDown(controller.dispose);
    final initial = controller.loadInitial();
    final filtered = controller.apply(
      TransactionSearchFilter(
        vaultId: vault,
        withoutTags: true,
        reportingExpensesOnly: true,
      ),
    );
    repository.requests[1].complete(
      const TransactionSearchPage(items: [], hasMore: false),
    );
    await filtered;
    repository.requests[0].complete(
      const TransactionSearchPage(items: [], hasMore: true),
    );
    await initial;
    expect(controller.state.filter!.withoutTags, isTrue);
    expect(controller.state.filter!.reportingExpensesOnly, isTrue);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.loading, isFalse);
    final refresh = controller.refresh();
    repository.requests[2].complete(
      const TransactionSearchPage(items: [], hasMore: false),
    );
    await refresh;
    expect(controller.state.filter!.withoutTags, isTrue);
    expect(controller.state.filter!.reportingExpensesOnly, isTrue);
  });
}

class _DelayedHistory implements TransactionHistoryRepository {
  final requests = <Completer<TransactionSearchPage>>[];
  @override
  Future<TransactionSearchPage> search(TransactionSearchFilter filter) {
    final request = Completer<TransactionSearchPage>();
    requests.add(request);
    return request.future;
  }
}
