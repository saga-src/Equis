import '../ports/credit_card_repository.dart';
import '../ports/ledger_repository.dart';
import '../ports/local_unit_of_work.dart';
import '../../domain/credit_cards/credit_card_models.dart';
import '../../domain/entities/account_profile.dart';
import '../../domain/ledger/ledger_engine.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class CreditCardService {
  CreditCardService({
    required this.repository,
    required this.ledger,
    required this.unitOfWork,
    LedgerEngine? engine,
    StatementPeriodCalculator? periods,
  }) : _engine = engine ?? LedgerEngine(),
       _periods = periods ?? const StatementPeriodCalculator();

  final CreditCardRepository repository;
  final LedgerRepository ledger;
  final LocalUnitOfWork unitOfWork;
  final LedgerEngine _engine;
  final StatementPeriodCalculator _periods;

  Future<void> configure({
    required CreditCardContext card,
    required int closingDay,
    required int dueDay,
    required int limitMinor,
  }) => unitOfWork.run(() async {
    await repository.saveProfile(
      CreditCardProfile(
        accountId: card.accountId,
        defaultClosingDay: closingDay,
        defaultDueDay: dueDay,
      ),
    );
    await repository.saveLimit(
      CreditCardLimit(accountPocketId: card.pocketId, limitMinor: limitMinor),
    );
  });

  Future<int?> availableCredit(CreditCardContext card) async {
    final limit = await repository.findLimit(card.pocketId);
    if (limit == null) return null;
    return limit.limitMinor - await repository.outstandingMinor(card.pocketId);
  }

  Future<CreditCardOverview> overview({
    required CreditCardContext card,
    required LocalDate asOf,
    required UtcInstant now,
  }) async {
    final profile = await repository.findProfile(card.accountId);
    final limit = await repository.findLimit(card.pocketId);
    if (profile == null) {
      return CreditCardOverview(
        profile: null,
        limit: limit,
        availableCreditMinor: limit == null
            ? null
            : limit.limitMinor -
                  await repository.outstandingMinor(card.pocketId),
        statements: const [],
        installmentPlans: await repository.listInstallmentPlans(card.pocketId),
      );
    }
    return CreditCardOverview(
      profile: profile,
      limit: limit,
      availableCreditMinor: await availableCredit(card),
      statements: await statementsAround(
        card: card,
        around: asOf,
        now: now,
        future: 12,
      ),
      installmentPlans: await repository.listInstallmentPlans(card.pocketId),
    );
  }

  Future<List<CreditCardStatementView>> statementsAround({
    required CreditCardContext card,
    required LocalDate around,
    required UtcInstant now,
    int previous = 1,
    int future = 3,
  }) async {
    if (previous < 0 || future < 0 || previous + future > 24) {
      throw RangeError(
        'Statement projection must remain bounded to 24 months.',
      );
    }
    final profile = await _profile(card);
    final base = _periods.periodFor(
      vaultId: card.vaultId,
      pocketId: card.pocketId,
      profile: profile,
      purchaseDate: around,
      now: now,
    );
    for (var offset = -previous; offset <= future; offset++) {
      final targetClosing = _periods.addMonthsAnchored(
        base.closingDate,
        offset,
      );
      await _ensureStatement(
        card: card,
        profile: profile,
        date: targetClosing,
        now: now,
      );
    }
    await refreshLifecycle(card: card, asOf: around, now: now);
    final statements = await repository.listStatements(card.pocketId);
    return Future.wait([for (final statement in statements) _view(statement)]);
  }

  Future<LedgerTransaction> purchase({
    required CreditCardContext card,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    String? title,
    String? notes,
  }) => unitOfWork.run(() async {
    final statement = await _statementFor(card, date, now);
    final transaction = _engine
        .creditCardPurchase(
          vaultId: card.vaultId,
          cardPocket: _pocket(card),
          amount: amount,
          categoryId: categoryId,
          date: date,
          now: now,
          statementId: statement.id,
        )
        .withDetails(title: title, notes: notes);
    await ledger.save(transaction);
    return transaction;
  });

  Future<LedgerTransaction> refund({
    required CreditCardContext card,
    required LedgerTransaction original,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? categoryId,
    String? title,
  }) => unitOfWork.run(() async {
    if (original.type != LedgerTransactionType.creditCardPurchase &&
        original.type != LedgerTransactionType.fee) {
      throw ArgumentError('A card refund must reference a card charge.');
    }
    final originalAmount = original.movements
        .where((movement) => movement.pocket.id == card.pocketId)
        .fold(0, (sum, movement) => sum + movement.amountMinor);
    if (amount.currency != card.currency ||
        amount.minorUnits > originalAmount ||
        amount.minorUnits <= 0) {
      throw ArgumentError('Refund exceeds the original card charge.');
    }
    final statement = await _statementFor(card, date, now);
    final resolvedCategory =
        categoryId ??
        (original.splits.isEmpty
            ? throw StateError('Original charge has no category.')
            : original.splits.first.categoryId);
    final transaction = _engine
        .refund(
          vaultId: card.vaultId,
          pocket: _pocket(card),
          amount: amount,
          originalCategoryId: resolvedCategory,
          date: date,
          now: now,
          statementId: statement.id,
          originalTransactionId: original.id,
        )
        .withDetails(title: title, notes: null);
    await ledger.save(transaction);
    return transaction;
  });

  Future<LedgerTransaction> payStatement({
    required CreditCardContext card,
    required CreditCardStatement statement,
    required LedgerPocket bankPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    if (statement.accountPocketId != card.pocketId) {
      throw ArgumentError('Statement does not belong to this card pocket.');
    }
    final due = (await repository.statementAmounts(statement.id)).dueMinor;
    if (amount.minorUnits <= 0 || amount.minorUnits > due) {
      throw ArgumentError(
        'Payment must be positive and not exceed statement due.',
      );
    }
    final payment = _engine.creditCardPayment(
      vaultId: card.vaultId,
      bankPocket: bankPocket,
      cardPocket: _pocket(card),
      amount: amount,
      date: date,
      now: now,
      statementId: statement.id,
    );
    await ledger.save(payment);
    await _refreshStatement(statement, asOf: date, now: now);
    return payment;
  });

  Future<LedgerTransaction> chargeFeeOrInterest({
    required CreditCardContext card,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    required String title,
  }) => unitOfWork.run(() async {
    final statement = await _statementFor(card, date, now);
    final charge = _engine
        .fee(
          vaultId: card.vaultId,
          pocket: _pocket(card),
          amount: amount,
          categoryId: categoryId,
          date: date,
          now: now,
          statementId: statement.id,
        )
        .withDetails(title: title);
    await ledger.save(charge);
    return charge;
  });

  Future<InstallmentPlanView> createInstallmentPlan({
    required CreditCardContext card,
    required Money originalAmount,
    required Money financedAmount,
    required int installmentCount,
    required EntityId categoryId,
    required LocalDate firstInstallmentDate,
    required LocalDate asOf,
    required UtcInstant now,
    String? description,
    String? interestRate,
  }) => unitOfWork.run(() async {
    if (originalAmount.currency != card.currency ||
        financedAmount.currency != card.currency ||
        financedAmount.minorUnits < originalAmount.minorUnits ||
        (interestRate == null && financedAmount != originalAmount)) {
      throw ArgumentError('Invalid original/financed installment amounts.');
    }
    final plan = InstallmentPlan(
      id: EntityId.generate(),
      vaultId: card.vaultId,
      accountPocketId: card.pocketId,
      categoryId: categoryId,
      description: description,
      currency: card.currency,
      totalMinor: originalAmount.minorUnits,
      installmentCount: installmentCount,
      firstInstallmentDate: firstInstallmentDate,
      interestRate: interestRate,
      status: InstallmentPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    final amounts = splitInstallmentTotal(
      financedAmount.minorUnits,
      installmentCount,
    );
    final items = <CardInstallment>[];
    for (var index = 0; index < installmentCount; index++) {
      final expected = _periods.addMonthsAnchored(firstInstallmentDate, index);
      final statement = await _statementFor(card, expected, now);
      final status = expected.compareTo(asOf) <= 0
          ? LedgerTransactionStatus.cleared
          : LedgerTransactionStatus.pending;
      final transaction = _engine
          .creditCardPurchase(
            vaultId: card.vaultId,
            cardPocket: _pocket(card),
            amount: Money(currency: card.currency, minorUnits: amounts[index]),
            categoryId: categoryId,
            date: expected,
            now: now,
            statementId: statement.id,
            status: status,
          )
          .withDetails(
            title: description == null
                ? '${index + 1}/$installmentCount'
                : '$description ${index + 1}/$installmentCount',
          );
      await ledger.save(transaction);
      items.add(
        CardInstallment(
          id: EntityId.generate(),
          installmentPlanId: plan.id,
          installmentNumber: index + 1,
          amountMinor: amounts[index],
          expectedDate: expected,
          transactionId: transaction.id,
          statementId: statement.id,
          status: expected.compareTo(asOf) <= 0
              ? InstallmentStatus.posted
              : InstallmentStatus.scheduled,
        ),
      );
    }
    final view = InstallmentPlanView(plan: plan, items: items);
    await repository.saveInstallmentPlan(view);
    return view;
  });

  Future<void> cancelInstallmentPlan({
    required CreditCardContext card,
    required InstallmentPlanView value,
    required LocalDate refundDate,
    required UtcInstant now,
    bool refundPosted = true,
  }) => unitOfWork.run(() async {
    if (value.plan.status != InstallmentPlanStatus.active) return;
    for (final item in value.items) {
      final transactionId = item.transactionId;
      if (transactionId == null) continue;
      final transaction = await ledger.find(transactionId);
      if (transaction == null) continue;
      if (transaction.status == LedgerTransactionStatus.pending) {
        await ledger.save(
          transaction.transitionTo(LedgerTransactionStatus.cancelled, at: now),
        );
        await repository.saveInstallment(
          item.withStatus(InstallmentStatus.cancelled),
        );
      } else if (refundPosted &&
          transaction.status == LedgerTransactionStatus.cleared) {
        await refund(
          card: card,
          original: transaction,
          amount: Money(currency: card.currency, minorUnits: item.amountMinor),
          date: refundDate,
          now: now,
          categoryId: value.plan.categoryId,
        );
        await repository.saveInstallment(
          item.withStatus(InstallmentStatus.refunded),
        );
      }
    }
    await repository.updateInstallmentPlanStatus(
      value.plan,
      InstallmentPlanStatus.cancelled,
      at: now,
    );
  });

  Future<void> refreshLifecycle({
    required CreditCardContext card,
    required LocalDate asOf,
    required UtcInstant now,
  }) => unitOfWork.run(() async {
    final plans = await repository.listInstallmentPlans(card.pocketId);
    for (final plan in plans) {
      for (final item in plan.items) {
        if (item.status != InstallmentStatus.scheduled ||
            item.expectedDate.compareTo(asOf) > 0 ||
            item.transactionId == null) {
          continue;
        }
        final transaction = await ledger.find(item.transactionId!);
        if (transaction?.status == LedgerTransactionStatus.pending) {
          await ledger.save(
            transaction!.transitionTo(LedgerTransactionStatus.cleared, at: now),
          );
        }
        await repository.saveInstallment(
          item.withStatus(InstallmentStatus.posted),
        );
      }
    }
    for (final statement in await repository.listStatements(card.pocketId)) {
      await _refreshStatement(statement, asOf: asOf, now: now);
    }
  });

  Future<CreditCardProfile> _profile(CreditCardContext card) async =>
      await repository.findProfile(card.accountId) ??
      (throw StateError('Credit card must be configured first.'));

  Future<CreditCardStatement> _statementFor(
    CreditCardContext card,
    LocalDate date,
    UtcInstant now,
  ) async => _ensureStatement(
    card: card,
    profile: await _profile(card),
    date: date,
    now: now,
  );

  Future<CreditCardStatement> _ensureStatement({
    required CreditCardContext card,
    required CreditCardProfile profile,
    required LocalDate date,
    required UtcInstant now,
  }) async {
    final existing = await repository.findStatementForDate(card.pocketId, date);
    if (existing != null) return existing;
    final statement = _periods.periodFor(
      vaultId: card.vaultId,
      pocketId: card.pocketId,
      profile: profile,
      purchaseDate: date,
      now: now,
    );
    await repository.saveStatement(statement);
    return statement;
  }

  Future<CreditCardStatementView> _view(CreditCardStatement statement) async =>
      CreditCardStatementView(
        statement: statement,
        amounts: await repository.statementAmounts(statement.id),
      );

  Future<void> _refreshStatement(
    CreditCardStatement statement, {
    required LocalDate asOf,
    required UtcInstant now,
  }) async {
    final amounts = await repository.statementAmounts(statement.id);
    final next = amounts.chargesMinor > 0 && amounts.dueMinor <= 0
        ? CreditCardStatementStatus.paid
        : asOf.compareTo(statement.dueDate) > 0
        ? CreditCardStatementStatus.overdue
        : asOf.compareTo(statement.closingDate) > 0
        ? CreditCardStatementStatus.closed
        : asOf.compareTo(statement.periodStart) >= 0
        ? CreditCardStatementStatus.open
        : CreditCardStatementStatus.future;
    if (next != statement.status) {
      await repository.saveStatement(statement.withStatus(next, at: now));
    }
  }

  LedgerPocket _pocket(CreditCardContext card) => LedgerPocket(
    id: card.pocketId,
    currency: card.currency,
    nature: AccountNature.liability,
  );
}
