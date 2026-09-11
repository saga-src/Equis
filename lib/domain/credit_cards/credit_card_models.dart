import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

final class CreditCardContext {
  const CreditCardContext({
    required this.vaultId,
    required this.accountId,
    required this.pocketId,
    required this.currency,
  });

  final EntityId vaultId;
  final EntityId accountId;
  final EntityId pocketId;
  final CurrencyCode currency;
}

final class CreditCardProfile {
  CreditCardProfile({
    required this.accountId,
    required this.defaultClosingDay,
    required this.defaultDueDay,
  }) {
    _validateDay(defaultClosingDay, 'defaultClosingDay');
    _validateDay(defaultDueDay, 'defaultDueDay');
  }

  final EntityId accountId;
  final int defaultClosingDay;
  final int defaultDueDay;
}

final class CreditCardLimit {
  CreditCardLimit({required this.accountPocketId, required this.limitMinor}) {
    if (limitMinor <= 0) {
      throw RangeError.value(limitMinor, 'limitMinor', 'must be positive');
    }
  }

  final EntityId accountPocketId;
  final int limitMinor;
}

enum CreditCardStatementStatus { future, open, closed, paid, overdue }

final class CreditCardStatement {
  CreditCardStatement({
    required this.id,
    required this.vaultId,
    required this.accountPocketId,
    required this.periodStart,
    required this.periodEnd,
    required this.closingDate,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 1,
    this.deletedAt,
  }) {
    if (periodEnd.compareTo(periodStart) < 0 ||
        closingDate != periodEnd ||
        dueDate.compareTo(closingDate) <= 0) {
      throw ArgumentError('Invalid credit-card statement period.');
    }
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final EntityId accountPocketId;
  final LocalDate periodStart;
  final LocalDate periodEnd;
  final LocalDate closingDate;
  final LocalDate dueDate;
  final CreditCardStatementStatus status;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;

  CreditCardStatement withStatus(
    CreditCardStatementStatus value, {
    required UtcInstant at,
  }) => CreditCardStatement(
    id: id,
    vaultId: vaultId,
    accountPocketId: accountPocketId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    closingDate: closingDate,
    dueDate: dueDate,
    status: value,
    revision: revision + 1,
    createdAt: createdAt,
    updatedAt: at,
    deletedAt: deletedAt,
  );
}

final class CreditCardStatementAmounts {
  const CreditCardStatementAmounts({
    required this.chargesMinor,
    required this.refundsMinor,
    required this.paymentsMinor,
  });

  final int chargesMinor;
  final int refundsMinor;
  final int paymentsMinor;

  int get dueMinor => chargesMinor - refundsMinor - paymentsMinor;
}

final class CreditCardStatementView {
  const CreditCardStatementView({
    required this.statement,
    required this.amounts,
  });

  final CreditCardStatement statement;
  final CreditCardStatementAmounts amounts;
}

final class CreditCardOverview {
  const CreditCardOverview({
    required this.profile,
    required this.limit,
    required this.availableCreditMinor,
    required this.statements,
    required this.installmentPlans,
  });

  final CreditCardProfile? profile;
  final CreditCardLimit? limit;
  final int? availableCreditMinor;
  final List<CreditCardStatementView> statements;
  final List<InstallmentPlanView> installmentPlans;
}

enum InstallmentPlanStatus { active, completed, cancelled }

enum InstallmentStatus { scheduled, posted, paid, cancelled, refunded }

final class InstallmentPlan {
  InstallmentPlan({
    required this.id,
    required this.vaultId,
    required this.accountPocketId,
    required this.currency,
    required this.totalMinor,
    required this.installmentCount,
    required this.firstInstallmentDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.counterpartyId,
    this.categoryId,
    this.description,
    String? interestRate,
    this.recognitionMode = 'installment_date',
    this.revision = 1,
    this.deletedAt,
  }) : interestRate = interestRate == null
           ? null
           : DecimalValue.canonical(DecimalValue.parse(interestRate)) {
    if (totalMinor <= 0) {
      throw RangeError.value(totalMinor, 'totalMinor', 'must be positive');
    }
    if (installmentCount < 2 || installmentCount > 120) {
      throw RangeError.range(installmentCount, 2, 120, 'installmentCount');
    }
    if (this.interestRate != null &&
        DecimalValue.parse(this.interestRate!).sign < 0) {
      throw ArgumentError.value(interestRate, 'interestRate');
    }
    if (recognitionMode != 'installment_date') {
      throw ArgumentError.value(recognitionMode, 'recognitionMode');
    }
    if (revision < 1) throw RangeError.value(revision, 'revision');
  }

  final EntityId id;
  final EntityId vaultId;
  final EntityId accountPocketId;
  final EntityId? counterpartyId;
  final EntityId? categoryId;
  final String? description;
  final CurrencyCode currency;
  final int totalMinor;
  final int installmentCount;
  final LocalDate firstInstallmentDate;
  final String? interestRate;
  final String recognitionMode;
  final InstallmentPlanStatus status;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;
}

final class CardInstallment {
  CardInstallment({
    required this.id,
    required this.installmentPlanId,
    required this.installmentNumber,
    required this.amountMinor,
    required this.expectedDate,
    required this.status,
    this.transactionId,
    this.statementId,
  }) {
    if (installmentNumber < 1 || amountMinor <= 0) {
      throw ArgumentError('Invalid installment.');
    }
  }

  final EntityId id;
  final EntityId installmentPlanId;
  final int installmentNumber;
  final int amountMinor;
  final LocalDate expectedDate;
  final EntityId? transactionId;
  final EntityId? statementId;
  final InstallmentStatus status;

  CardInstallment withStatus(InstallmentStatus value) => CardInstallment(
    id: id,
    installmentPlanId: installmentPlanId,
    installmentNumber: installmentNumber,
    amountMinor: amountMinor,
    expectedDate: expectedDate,
    transactionId: transactionId,
    statementId: statementId,
    status: value,
  );
}

final class InstallmentPlanView {
  InstallmentPlanView({
    required this.plan,
    required List<CardInstallment> items,
  }) : items = List.unmodifiable(items) {
    if (items.length != plan.installmentCount ||
        items.any((item) => item.installmentPlanId != plan.id)) {
      throw StateError('Installment rows must completely belong to the plan.');
    }
  }

  final InstallmentPlan plan;
  final List<CardInstallment> items;

  int get financedTotalMinor =>
      items.fold(0, (sum, item) => sum + item.amountMinor);
  int get currentInstallment => items
      .where(
        (item) =>
            item.status == InstallmentStatus.posted ||
            item.status == InstallmentStatus.paid ||
            item.status == InstallmentStatus.refunded,
      )
      .length;
  int get remainingMinor => items
      .where(
        (item) =>
            item.status == InstallmentStatus.scheduled ||
            item.status == InstallmentStatus.posted,
      )
      .fold(0, (sum, item) => sum + item.amountMinor);
}

final class StatementPeriodCalculator {
  const StatementPeriodCalculator();

  CreditCardStatement periodFor({
    required EntityId vaultId,
    required EntityId pocketId,
    required CreditCardProfile profile,
    required LocalDate purchaseDate,
    required UtcInstant now,
    EntityId? id,
  }) {
    var closing = _dateClamped(
      purchaseDate.year,
      purchaseDate.month,
      profile.defaultClosingDay,
    );
    if (purchaseDate.compareTo(closing) > 0) {
      closing = _monthWithDay(closing, 1, profile.defaultClosingDay);
    }
    final previousClosing = _monthWithDay(
      closing,
      -1,
      profile.defaultClosingDay,
    );
    var due = _dateClamped(closing.year, closing.month, profile.defaultDueDay);
    if (due.compareTo(closing) <= 0) {
      due = _monthWithDay(closing, 1, profile.defaultDueDay);
    }
    return CreditCardStatement(
      id: id ?? EntityId.generate(),
      vaultId: vaultId,
      accountPocketId: pocketId,
      periodStart: previousClosing.addDays(1),
      periodEnd: closing,
      closingDate: closing,
      dueDate: due,
      status: CreditCardStatementStatus.future,
      createdAt: now,
      updatedAt: now,
    );
  }

  LocalDate addMonthsAnchored(LocalDate anchor, int months) =>
      _monthWithDay(anchor, months, anchor.day);
}

List<int> splitInstallmentTotal(int totalMinor, int count) {
  if (totalMinor <= 0 || count < 2 || count > 120) {
    throw ArgumentError('Invalid installment total or count.');
  }
  final base = totalMinor ~/ count;
  final remainder = totalMinor.remainder(count);
  if (base == 0) {
    throw ArgumentError('Every installment must be at least one minor unit.');
  }
  return [
    for (var index = 0; index < count; index++)
      base + (index < remainder ? 1 : 0),
  ];
}

LocalDate _monthWithDay(LocalDate source, int offset, int day) {
  final monthStart = DateTime.utc(source.year, source.month + offset, 1);
  return _dateClamped(monthStart.year, monthStart.month, day);
}

LocalDate _dateClamped(int year, int month, int day) {
  final last = DateTime.utc(year, month + 1, 0).day;
  return LocalDate(year, month, day > last ? last : day);
}

void _validateDay(int value, String name) {
  if (value < 1 || value > 31) {
    throw RangeError.range(value, 1, 31, name);
  }
}
