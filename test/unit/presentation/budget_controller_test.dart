import 'dart:async';

import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/presentation/budgets/budget_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/budget_test_repository.dart';

void main() {
  test('late history success or error cannot replace a newer month', () async {
    for (final fail in [false, true]) {
      final repository = BudgetTestRepository();
      final pending = Completer<BudgetMonthlyHistory>();
      repository.delayedHistory = pending;
      final controller = BudgetController(
        service: repository.service,
        vaultId: repository.vault,
        clock: () => DateTime.utc(2026, 8, 17),
      );
      final old = controller.reload();
      await Future<void>.delayed(Duration.zero);
      await controller.selectMonth(BudgetMonth(2026, 9));
      expect(controller.state.selectedMonth, BudgetMonth(2026, 9));
      if (fail) {
        pending.completeError(StateError('late fixture'));
      } else {
        pending.complete(repository.history);
      }
      await old;
      expect(controller.state.selectedMonth, BudgetMonth(2026, 9));
      expect(
        controller.state.items.single.period.start,
        BudgetMonth(2026, 9).start,
      );
      expect(
        controller.state.currentItems.single.period.start,
        BudgetMonth(2026, 8).start,
      );
      expect(controller.state.error, isNull);
      expect(controller.state.loading, isFalse);
      controller.dispose();
    }
  });

  test('disposed controller ignores delayed load completion', () async {
    final repository = BudgetTestRepository();
    final pending = Completer<BudgetMonthlyHistory>();
    repository.delayedHistory = pending;
    final controller = BudgetController(
      service: repository.service,
      vaultId: repository.vault,
      clock: () => DateTime.utc(2026, 8, 17),
    );
    final load = controller.reload();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    pending.complete(repository.history);
    await expectLater(load, completes);
  });

  test('invalid amounts never reach persistence', () async {
    final repository = BudgetTestRepository();
    final controller = BudgetController(
      service: repository.service,
      vaultId: repository.vault,
      clock: () => DateTime.utc(2026, 8, 17),
    );
    addTearDown(controller.dispose);
    for (final amount in [
      '0',
      '-10',
      '0.004',
      '99999999999999999999999999',
      'invalid',
    ]) {
      expect(
        await controller.create(
          name: 'Invalid',
          currency: CurrencyCode.brl,
          limitText: amount,
          periodType: BudgetPeriodType.monthly,
          warningThresholdBps: 8000,
          scope: BudgetScope(),
          limitMethod: BudgetLimitMethod.calendarDay,
        ),
        isFalse,
      );
      expect(controller.state.error, isNotNull);
      expect(controller.state.saving, isFalse);
    }
    expect(repository.writes, 0);
  });
}
