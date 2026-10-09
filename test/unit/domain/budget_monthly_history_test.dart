import 'package:equis/domain/budgeting/budget_models.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BudgetMonthlyConfiguration config(
    int amount, [
    BudgetLimitMethod method = BudgetLimitMethod.fixed,
  ]) => BudgetMonthlyConfiguration(
    amountMinor: amount,
    limitMethod: method,
    warningThresholdBps: 8000,
    scope: BudgetScope(),
  );

  test(
    'daily limits use complete calendar months and weekdays without holidays',
    () {
      final daily = config(1000, BudgetLimitMethod.calendarDay);
      expect(daily.limitFor(BudgetMonth(2026, 1)), 31000);
      expect(daily.limitFor(BudgetMonth(2026, 2)), 28000);
      expect(daily.limitFor(BudgetMonth(2024, 2)), 29000);
      expect(
        config(1000, BudgetLimitMethod.weekday).limitFor(BudgetMonth(2024, 2)),
        21000,
      );
    },
  );
  test(
    'exact override wins over latest applicable standard regardless of order',
    () {
      final id = EntityId.generate();
      BudgetMonthlyEntry entry(
        int month,
        BudgetMonthlyEntryKind kind,
        int amount,
      ) => BudgetMonthlyEntry(
        id: EntityId.generate(),
        budgetId: id,
        month: BudgetMonth(2026, month),
        kind: kind,
        configuration: config(amount),
      );
      final history = BudgetMonthlyHistory([
        entry(8, BudgetMonthlyEntryKind.standard, 120000),
        entry(9, BudgetMonthlyEntryKind.override, 150000),
        entry(7, BudgetMonthlyEntryKind.standard, 100000),
      ]);
      expect(history.resolve(BudgetMonth(2026, 6)), isNull);
      expect(history.resolve(BudgetMonth(2026, 7))!.amountMinor, 100000);
      expect(history.resolve(BudgetMonth(2026, 8))!.amountMinor, 120000);
      expect(history.resolve(BudgetMonth(2026, 9))!.amountMinor, 150000);
      expect(history.resolve(BudgetMonth(2026, 10))!.amountMinor, 120000);
    },
  );
  test(
    'rejects malformed month, invalid amounts and multiplication overflow',
    () {
      expect(() => BudgetMonth.parse('2026-02-02'), throwsFormatException);
      expect(() => BudgetMonth.parse('2026-02-30'), throwsArgumentError);
      expect(() => config(0), throwsRangeError);
      expect(
        () => config(
          9223372036854775807,
          BudgetLimitMethod.calendarDay,
        ).limitFor(BudgetMonth(2026, 1)),
        throwsRangeError,
      );
    },
  );
}
