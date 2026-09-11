import '../entities/account_profile.dart';
import '../shared/local_date.dart';
import '../shared/money.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';
import 'ledger_models.dart';

typedef EntityIdFactory = EntityId Function();

final class LedgerEngine {
  LedgerEngine({EntityIdFactory? idFactory})
    : _nextId = idFactory ?? EntityId.generate;

  final EntityIdFactory _nextId;

  LedgerTransaction income({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    LedgerTransactionStatus status = LedgerTransactionStatus.cleared,
  }) => _classified(
    vaultId: vaultId,
    type: LedgerTransactionType.income,
    pocket: pocket,
    amount: amount,
    categoryId: categoryId,
    economicIncrease: true,
    date: date,
    now: now,
    status: status,
  );

  LedgerTransaction expense({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    LedgerTransactionStatus status = LedgerTransactionStatus.cleared,
  }) => _classified(
    vaultId: vaultId,
    type: LedgerTransactionType.expense,
    pocket: pocket,
    amount: amount,
    categoryId: categoryId,
    economicIncrease: false,
    date: date,
    now: now,
    status: status,
  );

  LedgerTransaction creditCardPurchase({
    required EntityId vaultId,
    required LedgerPocket cardPocket,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    EntityId? statementId,
    LedgerTransactionStatus status = LedgerTransactionStatus.cleared,
  }) {
    _requireNature(cardPocket, AccountNature.liability, 'cardPocket');
    return _classified(
      vaultId: vaultId,
      type: LedgerTransactionType.creditCardPurchase,
      pocket: cardPocket,
      amount: amount,
      categoryId: categoryId,
      economicIncrease: false,
      date: date,
      now: now,
      status: status,
      statementId: statementId,
    );
  }

  LedgerTransaction fee({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId categoryId,
    required LocalDate date,
    required UtcInstant now,
    EntityId? statementId,
  }) => _classified(
    vaultId: vaultId,
    type: LedgerTransactionType.fee,
    pocket: pocket,
    amount: amount,
    categoryId: categoryId,
    economicIncrease: false,
    date: date,
    now: now,
    status: LedgerTransactionStatus.cleared,
    statementId: statementId,
  );

  LedgerTransaction refund({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId originalCategoryId,
    required LocalDate date,
    required UtcInstant now,
    EntityId? statementId,
    EntityId? originalTransactionId,
  }) {
    _requirePositive(amount, pocket);
    final effect = _nominalForEconomicEffect(pocket, amount.minorUnits);
    return LedgerTransaction(
      id: _nextId(),
      vaultId: vaultId,
      type: LedgerTransactionType.refund,
      status: LedgerTransactionStatus.cleared,
      financialDate: date,
      movements: [_movement(pocket, effect, 0, statementId: statementId)],
      splits: [
        LedgerSplit(
          id: _nextId(),
          categoryId: originalCategoryId,
          money: Money(
            currency: amount.currency,
            minorUnits: -amount.minorUnits,
          ),
          sortOrder: 0,
        ),
      ],
      reversalOfId: originalTransactionId,
      createdAt: now,
      updatedAt: now,
    );
  }

  LedgerTransaction transfer({
    required EntityId vaultId,
    required LedgerPocket source,
    required LedgerPocket destination,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
  }) {
    _requirePositive(amount, source);
    _requireCurrency(amount, destination);
    if (source.id == destination.id) {
      throw ArgumentError('Transfer pockets must differ.');
    }
    return _twoMovementTransaction(
      vaultId: vaultId,
      type: LedgerTransactionType.transfer,
      first: _movement(source, -amount.minorUnits, 0),
      second: _movement(destination, amount.minorUnits, 1),
      date: date,
      now: now,
    );
  }

  LedgerTransaction assetPurchase({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required LedgerPocket assetPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
  }) {
    _requireNature(cashPocket, AccountNature.asset, 'cashPocket');
    _requireNature(assetPocket, AccountNature.asset, 'assetPocket');
    return transfer(
      vaultId: vaultId,
      source: cashPocket,
      destination: assetPocket,
      amount: amount,
      date: date,
      now: now,
    );
  }

  LedgerTransaction assetSale({
    required EntityId vaultId,
    required LedgerPocket assetPocket,
    required LedgerPocket cashPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
  }) => assetPurchase(
    vaultId: vaultId,
    cashPocket: assetPocket,
    assetPocket: cashPocket,
    amount: amount,
    date: date,
    now: now,
  );

  LedgerTransaction investmentContribution({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required LedgerPocket investmentCashPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
  }) => assetPurchase(
    vaultId: vaultId,
    cashPocket: cashPocket,
    assetPocket: investmentCashPocket,
    amount: amount,
    date: date,
    now: now,
  );

  LedgerTransaction investmentWithdrawal({
    required EntityId vaultId,
    required LedgerPocket investmentCashPocket,
    required LedgerPocket cashPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
  }) => assetSale(
    vaultId: vaultId,
    assetPocket: investmentCashPocket,
    cashPocket: cashPocket,
    amount: amount,
    date: date,
    now: now,
  );

  LedgerTransaction currencyExchange({
    required EntityId vaultId,
    required LedgerPocket source,
    required Money sourceAmount,
    required LedgerPocket destination,
    required Money destinationAmount,
    required String exchangeRate,
    required String rateSource,
    required LocalDate date,
    required UtcInstant now,
    LocalDate? rateDate,
    String? provider,
  }) {
    _requirePositive(sourceAmount, source);
    _requirePositive(destinationAmount, destination);
    if (source.currency == destination.currency) {
      throw ArgumentError(
        'Currency exchange pockets must use different currencies.',
      );
    }
    final from = _movement(source, -sourceAmount.minorUnits, 0);
    final to = _movement(destination, destinationAmount.minorUnits, 1);
    return LedgerTransaction(
      id: _nextId(),
      vaultId: vaultId,
      type: LedgerTransactionType.currencyExchange,
      status: LedgerTransactionStatus.cleared,
      financialDate: date,
      movements: [from, to],
      splits: const [],
      fxConversion: LedgerFxConversion(
        id: _nextId(),
        fromMovementId: from.id,
        toMovementId: to.id,
        exchangeRate: exchangeRate,
        rateSource: rateSource,
        rateDate: rateDate,
        provider: provider,
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  LedgerTransaction creditCardPayment({
    required EntityId vaultId,
    required LedgerPocket bankPocket,
    required LedgerPocket cardPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? statementId,
  }) => _debtPayment(
    vaultId: vaultId,
    type: LedgerTransactionType.creditCardPayment,
    bankPocket: bankPocket,
    liabilityPocket: cardPocket,
    amount: amount,
    date: date,
    now: now,
    liabilityStatementId: statementId,
  );

  LedgerTransaction loanPayment({
    required EntityId vaultId,
    required LedgerPocket bankPocket,
    required LedgerPocket loanPocket,
    required Money principal,
    required LocalDate date,
    required UtcInstant now,
  }) => _debtPayment(
    vaultId: vaultId,
    type: LedgerTransactionType.loanPayment,
    bankPocket: bankPocket,
    liabilityPocket: loanPocket,
    amount: principal,
    date: date,
    now: now,
  );

  LedgerTransaction investmentBuy({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required Money totalCash,
    required LedgerInvestmentEvent event,
    required LocalDate date,
    required UtcInstant now,
  }) => _investment(
    vaultId: vaultId,
    type: LedgerTransactionType.investmentBuy,
    cashPocket: cashPocket,
    cash: totalCash,
    event: event,
    cashSign: -1,
    date: date,
    now: now,
  );

  LedgerTransaction investmentSell({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required Money netCash,
    required LedgerInvestmentEvent event,
    required LocalDate date,
    required UtcInstant now,
  }) => _investment(
    vaultId: vaultId,
    type: LedgerTransactionType.investmentSell,
    cashPocket: cashPocket,
    cash: netCash,
    event: event,
    cashSign: 1,
    date: date,
    now: now,
  );

  LedgerTransaction dividend({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required Money amount,
    required EntityId categoryId,
    required LedgerInvestmentEvent event,
    required LocalDate date,
    required UtcInstant now,
  }) => _investmentIncome(
    vaultId: vaultId,
    type: LedgerTransactionType.dividend,
    cashPocket: cashPocket,
    amount: amount,
    categoryId: categoryId,
    event: event,
    date: date,
    now: now,
  );

  LedgerTransaction interest({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required Money amount,
    required EntityId categoryId,
    required LedgerInvestmentEvent event,
    required LocalDate date,
    required UtcInstant now,
  }) => _investmentIncome(
    vaultId: vaultId,
    type: LedgerTransactionType.interest,
    cashPocket: cashPocket,
    amount: amount,
    categoryId: categoryId,
    event: event,
    date: date,
    now: now,
  );

  LedgerTransaction openingBalance({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money signedAmount,
    required LocalDate date,
    required UtcInstant now,
  }) {
    _requireCurrency(signedAmount, pocket);
    if (signedAmount.minorUnits == 0) {
      throw ArgumentError('Opening balance cannot be zero.');
    }
    return _singleUnclassified(
      vaultId: vaultId,
      type: LedgerTransactionType.openingBalance,
      pocket: pocket,
      signedAmountMinor: signedAmount.minorUnits,
      date: date,
      now: now,
    );
  }

  LedgerTransaction adjustment({
    required EntityId vaultId,
    required LedgerPocket pocket,
    required Money signedAmount,
    required LocalDate date,
    required UtcInstant now,
  }) {
    _requireCurrency(signedAmount, pocket);
    if (signedAmount.minorUnits == 0) {
      throw ArgumentError('Adjustment cannot be zero.');
    }
    return _singleUnclassified(
      vaultId: vaultId,
      type: LedgerTransactionType.adjustment,
      pocket: pocket,
      signedAmountMinor: signedAmount.minorUnits,
      date: date,
      now: now,
    );
  }

  LedgerTransaction _classified({
    required EntityId vaultId,
    required LedgerTransactionType type,
    required LedgerPocket pocket,
    required Money amount,
    required EntityId categoryId,
    required bool economicIncrease,
    required LocalDate date,
    required UtcInstant now,
    required LedgerTransactionStatus status,
    EntityId? statementId,
  }) {
    _requirePositive(amount, pocket);
    final economicEffect = economicIncrease
        ? amount.minorUnits
        : -amount.minorUnits;
    return LedgerTransaction(
      id: _nextId(),
      vaultId: vaultId,
      type: type,
      status: status,
      financialDate: date,
      movements: [
        _movement(
          pocket,
          _nominalForEconomicEffect(pocket, economicEffect),
          0,
          statementId: statementId,
        ),
      ],
      splits: [
        LedgerSplit(
          id: _nextId(),
          categoryId: categoryId,
          money: amount,
          sortOrder: 0,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  LedgerTransaction _debtPayment({
    required EntityId vaultId,
    required LedgerTransactionType type,
    required LedgerPocket bankPocket,
    required LedgerPocket liabilityPocket,
    required Money amount,
    required LocalDate date,
    required UtcInstant now,
    EntityId? liabilityStatementId,
  }) {
    _requireNature(bankPocket, AccountNature.asset, 'bankPocket');
    _requireNature(liabilityPocket, AccountNature.liability, 'liabilityPocket');
    _requirePositive(amount, bankPocket);
    _requireCurrency(amount, liabilityPocket);
    return _twoMovementTransaction(
      vaultId: vaultId,
      type: type,
      first: _movement(bankPocket, -amount.minorUnits, 0),
      second: _movement(
        liabilityPocket,
        -amount.minorUnits,
        1,
        statementId: liabilityStatementId,
      ),
      date: date,
      now: now,
    );
  }

  LedgerTransaction _investment({
    required EntityId vaultId,
    required LedgerTransactionType type,
    required LedgerPocket cashPocket,
    required Money cash,
    required LedgerInvestmentEvent event,
    required int cashSign,
    required LocalDate date,
    required UtcInstant now,
  }) {
    _requireNature(cashPocket, AccountNature.asset, 'cashPocket');
    _requirePositive(cash, cashPocket);
    return LedgerTransaction(
      id: _nextId(),
      vaultId: vaultId,
      type: type,
      status: LedgerTransactionStatus.cleared,
      financialDate: date,
      movements: [_movement(cashPocket, cashSign * cash.minorUnits, 0)],
      splits: const [],
      investmentEvents: [event],
      createdAt: now,
      updatedAt: now,
    );
  }

  LedgerTransaction _investmentIncome({
    required EntityId vaultId,
    required LedgerTransactionType type,
    required LedgerPocket cashPocket,
    required Money amount,
    required EntityId categoryId,
    required LedgerInvestmentEvent event,
    required LocalDate date,
    required UtcInstant now,
  }) {
    final transaction = _classified(
      vaultId: vaultId,
      type: type,
      pocket: cashPocket,
      amount: amount,
      categoryId: categoryId,
      economicIncrease: true,
      date: date,
      now: now,
      status: LedgerTransactionStatus.cleared,
    );
    return LedgerTransaction(
      id: transaction.id,
      vaultId: transaction.vaultId,
      type: transaction.type,
      status: transaction.status,
      financialDate: transaction.financialDate,
      movements: transaction.movements,
      splits: transaction.splits,
      investmentEvents: [event],
      createdAt: transaction.createdAt,
      updatedAt: transaction.updatedAt,
    );
  }

  LedgerTransaction _twoMovementTransaction({
    required EntityId vaultId,
    required LedgerTransactionType type,
    required LedgerMovement first,
    required LedgerMovement second,
    required LocalDate date,
    required UtcInstant now,
  }) => LedgerTransaction(
    id: _nextId(),
    vaultId: vaultId,
    type: type,
    status: LedgerTransactionStatus.cleared,
    financialDate: date,
    movements: [first, second],
    splits: const [],
    createdAt: now,
    updatedAt: now,
  );

  LedgerTransaction _singleUnclassified({
    required EntityId vaultId,
    required LedgerTransactionType type,
    required LedgerPocket pocket,
    required int signedAmountMinor,
    required LocalDate date,
    required UtcInstant now,
  }) => LedgerTransaction(
    id: _nextId(),
    vaultId: vaultId,
    type: type,
    status: LedgerTransactionStatus.cleared,
    financialDate: date,
    movements: [_movement(pocket, signedAmountMinor, 0)],
    splits: const [],
    createdAt: now,
    updatedAt: now,
  );

  LedgerMovement _movement(
    LedgerPocket pocket,
    int amountMinor,
    int order, {
    EntityId? statementId,
  }) => LedgerMovement(
    id: _nextId(),
    pocket: pocket,
    amountMinor: amountMinor,
    sortOrder: order,
    statementId: statementId,
  );

  int _nominalForEconomicEffect(LedgerPocket pocket, int effect) =>
      pocket.nature == AccountNature.asset ? effect : -effect;

  void _requirePositive(Money amount, LedgerPocket pocket) {
    _requireCurrency(amount, pocket);
    if (amount.minorUnits <= 0) {
      throw ArgumentError.value(
        amount.minorUnits,
        'amount',
        'must be positive',
      );
    }
  }

  void _requireCurrency(Money amount, LedgerPocket pocket) {
    if (amount.currency != pocket.currency) {
      throw ArgumentError('Money currency must match the account pocket.');
    }
  }

  void _requireNature(
    LedgerPocket pocket,
    AccountNature nature,
    String argument,
  ) {
    if (pocket.nature != nature) {
      throw ArgumentError.value(pocket.nature, argument, 'must be $nature');
    }
  }
}
