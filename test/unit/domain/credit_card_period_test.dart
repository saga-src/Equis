import 'package:equis/domain/credit_cards/credit_card_models.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calculator = StatementPeriodCalculator();
  final profile = CreditCardProfile(
    accountId: EntityId.generate(),
    defaultClosingDay: 20,
    defaultDueDay: 5,
  );
  final vault = EntityId.generate();
  final pocket = EntityId.generate();
  const now = UtcInstant.fromEpochMicroseconds(1);

  test('purchase on closing day stays in current statement', () {
    final statement = calculator.periodFor(
      vaultId: vault,
      pocketId: pocket,
      profile: profile,
      purchaseDate: LocalDate(2026, 8, 20),
      now: now,
    );
    expect(statement.periodStart, LocalDate(2026, 7, 21));
    expect(statement.closingDate, LocalDate(2026, 8, 20));
    expect(statement.dueDate, LocalDate(2026, 9, 5));
  });

  test('purchase after closing day moves to next statement', () {
    final statement = calculator.periodFor(
      vaultId: vault,
      pocketId: pocket,
      profile: profile,
      purchaseDate: LocalDate(2026, 8, 21),
      now: now,
    );
    expect(statement.periodStart, LocalDate(2026, 8, 21));
    expect(statement.closingDate, LocalDate(2026, 9, 20));
    expect(statement.dueDate, LocalDate(2026, 10, 5));
  });

  test('closing and due days clamp deterministically at month end', () {
    final edge = calculator.periodFor(
      vaultId: vault,
      pocketId: pocket,
      profile: CreditCardProfile(
        accountId: profile.accountId,
        defaultClosingDay: 31,
        defaultDueDay: 2,
      ),
      purchaseDate: LocalDate(2027, 2, 28),
      now: now,
    );
    expect(edge.closingDate, LocalDate(2027, 2, 28));
    expect(edge.dueDate, LocalDate(2027, 3, 2));
  });

  test('installment split preserves every minor unit', () {
    final values = splitInstallmentTotal(10000, 12);
    expect(values, hasLength(12));
    expect(values.fold(0, (sum, value) => sum + value), 10000);
    expect(values.take(4), everyElement(834));
    expect(values.skip(4), everyElement(833));
  });
}
