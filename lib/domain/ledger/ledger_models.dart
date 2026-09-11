import '../entities/account_profile.dart';
import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/money.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum LedgerTransactionType {
  openingBalance('opening_balance'),
  expense,
  income,
  transfer,
  currencyExchange('currency_exchange'),
  creditCardPurchase('credit_card_purchase'),
  creditCardPayment('credit_card_payment'),
  refund,
  loanPayment('loan_payment'),
  investmentBuy('investment_buy'),
  investmentSell('investment_sell'),
  dividend,
  interest,
  fee,
  adjustment;

  const LedgerTransactionType([String? storageValue])
    : storageValue = storageValue ?? '';

  final String storageValue;
  String get stored => storageValue.isEmpty ? name : storageValue;

  static LedgerTransactionType fromStorage(String value) =>
      values.singleWhere((type) => type.stored == value);
}

enum LedgerTransactionStatus { pending, cleared, reconciled, cancelled }

final class LedgerPocket {
  const LedgerPocket({
    required this.id,
    required this.currency,
    required this.nature,
  });

  final EntityId id;
  final CurrencyCode currency;
  final AccountNature nature;
}

final class LedgerMovement {
  const LedgerMovement({
    required this.id,
    required this.pocket,
    required this.amountMinor,
    required this.sortOrder,
    this.statementId,
  });

  final EntityId id;
  final LedgerPocket pocket;
  final int amountMinor;
  final int sortOrder;
  final EntityId? statementId;

  int get netWorthEffectMinor =>
      pocket.nature == AccountNature.asset ? amountMinor : -amountMinor;

  LedgerMovement reversed(EntityId newId) => LedgerMovement(
    id: newId,
    pocket: pocket,
    amountMinor: -amountMinor,
    sortOrder: sortOrder,
    statementId: statementId,
  );
}

final class LedgerSplit {
  const LedgerSplit({
    required this.id,
    required this.categoryId,
    required this.money,
    required this.sortOrder,
    this.memo,
  });

  final EntityId id;
  final EntityId categoryId;
  final Money money;
  final int sortOrder;
  final String? memo;

  LedgerSplit reversed(EntityId newId) => LedgerSplit(
    id: newId,
    categoryId: categoryId,
    money: -money,
    sortOrder: sortOrder,
    memo: memo,
  );
}

final class LedgerFxConversion {
  LedgerFxConversion({
    required this.id,
    required this.fromMovementId,
    required this.toMovementId,
    required String exchangeRate,
    required this.rateSource,
    this.rateDate,
    this.provider,
  }) : exchangeRate = DecimalValue.canonical(DecimalValue.parse(exchangeRate)) {
    if (DecimalValue.parse(this.exchangeRate).sign <= 0) {
      throw ArgumentError.value(
        exchangeRate,
        'exchangeRate',
        'must be positive',
      );
    }
  }

  final EntityId id;
  final EntityId fromMovementId;
  final EntityId toMovementId;
  final String exchangeRate;
  final String rateSource;
  final LocalDate? rateDate;
  final String? provider;
}

final class LedgerInvestmentEvent {
  LedgerInvestmentEvent({
    required this.id,
    required this.instrumentId,
    required this.eventType,
    String? quantity,
    String? unitPrice,
    this.priceCurrency,
    this.grossMinor,
    this.feesMinor,
    this.taxesMinor,
  }) : quantity = quantity == null
           ? null
           : DecimalValue.canonical(DecimalValue.parse(quantity)),
       unitPrice = unitPrice == null
           ? null
           : DecimalValue.canonical(DecimalValue.parse(unitPrice));

  final EntityId id;
  final EntityId instrumentId;
  final String eventType;
  final String? quantity;
  final String? unitPrice;
  final CurrencyCode? priceCurrency;
  final int? grossMinor;
  final int? feesMinor;
  final int? taxesMinor;
}

final class LedgerTransaction {
  LedgerTransaction({
    required this.id,
    required this.vaultId,
    required this.type,
    required this.status,
    required this.financialDate,
    required this.movements,
    required this.splits,
    required this.createdAt,
    required this.updatedAt,
    this.fxConversion,
    this.investmentEvents = const [],
    this.title,
    this.notes,
    this.occurredAt,
    this.timezone,
    this.reversalOfId,
    this.recurringRuleId,
    this.recurrenceDate,
    this.tagIds = const [],
    this.deletedAt,
    this.revision = 1,
  }) {
    if (revision < 1) throw RangeError.value(revision, 'revision');
    validate();
  }

  final EntityId id;
  final EntityId vaultId;
  final LedgerTransactionType type;
  final LedgerTransactionStatus status;
  final LocalDate financialDate;
  final List<LedgerMovement> movements;
  final List<LedgerSplit> splits;
  final LedgerFxConversion? fxConversion;
  final List<LedgerInvestmentEvent> investmentEvents;
  final String? title;
  final String? notes;
  final UtcInstant? occurredAt;
  final String? timezone;
  final EntityId? reversalOfId;
  final EntityId? recurringRuleId;
  final LocalDate? recurrenceDate;
  final List<EntityId> tagIds;
  final UtcInstant? deletedAt;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;

  bool get affectsBalances =>
      status != LedgerTransactionStatus.cancelled &&
      !(status == LedgerTransactionStatus.pending && recurringRuleId != null) &&
      deletedAt == null;

  int get netWorthEffectMinor =>
      movements.fold(0, (sum, movement) => sum + movement.netWorthEffectMinor);

  void validate() {
    if ((recurringRuleId == null) != (recurrenceDate == null)) {
      throw StateError(
        'Recurring rule and recurrence date must be present together.',
      );
    }
    if (movements.isEmpty) {
      throw StateError('A ledger transaction needs movements.');
    }
    if (movements.any((movement) => movement.amountMinor == 0)) {
      throw StateError('Zero-value movements are not allowed.');
    }
    if (_hasDuplicates(movements.map((movement) => movement.id.value)) ||
        _hasDuplicates(splits.map((split) => split.id.value)) ||
        _hasDuplicates(tagIds.map((tag) => tag.value))) {
      throw StateError('Child identifiers must be unique inside an aggregate.');
    }
    switch (type) {
      case LedgerTransactionType.expense ||
          LedgerTransactionType.creditCardPurchase ||
          LedgerTransactionType.fee:
        _requireClassifiedDecrease();
      case LedgerTransactionType.income ||
          LedgerTransactionType.dividend ||
          LedgerTransactionType.interest:
        _requireClassifiedIncrease();
      case LedgerTransactionType.refund:
        _requireRefund();
      case LedgerTransactionType.transfer:
        _requireTransfer();
      case LedgerTransactionType.currencyExchange:
        _requireCurrencyExchange();
      case LedgerTransactionType.creditCardPayment:
        _requireDebtPayment();
      case LedgerTransactionType.loanPayment:
        _requireDebtPayment();
      case LedgerTransactionType.investmentBuy:
        if (movements.length != 1 ||
            movements.single.amountMinor >= 0 ||
            investmentEvents.isEmpty) {
          throw StateError(
            'Investment buy requires one negative cash movement and an event.',
          );
        }
        _requireNoSplits();
      case LedgerTransactionType.investmentSell:
        if (movements.length != 1 ||
            movements.single.amountMinor <= 0 ||
            investmentEvents.isEmpty) {
          throw StateError(
            'Investment sell requires one positive cash movement and an event.',
          );
        }
        _requireNoSplits();
      case LedgerTransactionType.openingBalance ||
          LedgerTransactionType.adjustment:
        break;
    }
  }

  LedgerTransaction transitionTo(
    LedgerTransactionStatus next, {
    required UtcInstant at,
  }) {
    const transitions = {
      LedgerTransactionStatus.pending: {
        LedgerTransactionStatus.cleared,
        LedgerTransactionStatus.cancelled,
      },
      LedgerTransactionStatus.cleared: {
        LedgerTransactionStatus.reconciled,
        LedgerTransactionStatus.cancelled,
      },
      LedgerTransactionStatus.reconciled: <LedgerTransactionStatus>{},
      LedgerTransactionStatus.cancelled: <LedgerTransactionStatus>{},
    };
    if (!transitions[status]!.contains(next)) {
      throw StateError('Invalid transaction transition: $status -> $next.');
    }
    return _copy(status: next, updatedAt: at, revision: revision + 1);
  }

  LedgerTransaction revise({
    required List<LedgerMovement> movements,
    required List<LedgerSplit> splits,
    required UtcInstant at,
    LocalDate? financialDate,
    String? title,
    String? notes,
    List<EntityId>? tagIds,
  }) {
    if (deletedAt != null ||
        status == LedgerTransactionStatus.cancelled ||
        status == LedgerTransactionStatus.reconciled) {
      throw StateError(
        'Cancelled or reconciled transactions cannot be edited.',
      );
    }
    return _copy(
      movements: movements,
      splits: splits,
      financialDate: financialDate,
      updatedAt: at,
      revision: revision + 1,
      title: title,
      notes: notes,
      tagIds: tagIds,
      replaceTitle: true,
      replaceNotes: true,
    );
  }

  LedgerTransaction tagged(List<EntityId> values) => _copy(tagIds: values);

  LedgerTransaction withDetails({String? title, String? notes}) =>
      _copy(title: title, notes: notes, replaceTitle: true, replaceNotes: true);

  LedgerTransaction softDelete({required UtcInstant at}) {
    if (deletedAt != null) return this;
    return _copy(deletedAt: at, updatedAt: at, revision: revision + 1);
  }

  LedgerTransaction reversed({
    required EntityId id,
    required EntityId Function() nextId,
    required UtcInstant at,
  }) => LedgerTransaction(
    id: id,
    vaultId: vaultId,
    type: LedgerTransactionType.adjustment,
    status: LedgerTransactionStatus.cleared,
    financialDate: financialDate,
    movements: movements
        .map((movement) => movement.reversed(nextId()))
        .toList(),
    splits: splits.map((split) => split.reversed(nextId())).toList(),
    title: title == null ? 'Reversal' : 'Reversal: $title',
    notes: notes,
    occurredAt: at,
    timezone: timezone,
    reversalOfId: this.id,
    tagIds: tagIds,
    createdAt: at,
    updatedAt: at,
  );

  LedgerTransaction _copy({
    LedgerTransactionStatus? status,
    LocalDate? financialDate,
    List<LedgerMovement>? movements,
    List<LedgerSplit>? splits,
    UtcInstant? updatedAt,
    int? revision,
    String? title,
    String? notes,
    bool replaceTitle = false,
    bool replaceNotes = false,
    List<EntityId>? tagIds,
    UtcInstant? deletedAt,
  }) => LedgerTransaction(
    id: id,
    vaultId: vaultId,
    type: type,
    status: status ?? this.status,
    financialDate: financialDate ?? this.financialDate,
    movements: movements ?? this.movements,
    splits: splits ?? this.splits,
    fxConversion: fxConversion,
    investmentEvents: investmentEvents,
    title: replaceTitle ? title : this.title,
    notes: replaceNotes ? notes : this.notes,
    occurredAt: occurredAt,
    timezone: timezone,
    reversalOfId: reversalOfId,
    recurringRuleId: recurringRuleId,
    recurrenceDate: recurrenceDate,
    tagIds: tagIds ?? this.tagIds,
    deletedAt: deletedAt ?? this.deletedAt,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  void _requireClassifiedDecrease() {
    if (netWorthEffectMinor >= 0) {
      throw StateError('$type must reduce net worth.');
    }
    final total = splits.fold(0, (sum, split) => sum + split.money.minorUnits);
    if (splits.isEmpty || total != -netWorthEffectMinor) {
      throw StateError('$type splits must classify the full positive expense.');
    }
  }

  void _requireClassifiedIncrease() {
    if (netWorthEffectMinor <= 0) {
      throw StateError('$type must increase net worth.');
    }
    if (splits.isNotEmpty) {
      final total = splits.fold(
        0,
        (sum, split) => sum + split.money.minorUnits,
      );
      if (total != netWorthEffectMinor) {
        throw StateError(
          '$type splits must classify the full positive income.',
        );
      }
    }
  }

  void _requireRefund() {
    if (netWorthEffectMinor <= 0) {
      throw StateError('A refund must increase net worth.');
    }
    final total = splits.fold(0, (sum, split) => sum + split.money.minorUnits);
    if (splits.isEmpty || total != -netWorthEffectMinor) {
      throw StateError(
        'Refund splits must negatively offset the original expense.',
      );
    }
  }

  void _requireTransfer() {
    if (movements.length != 2 ||
        movements[0].pocket.currency != movements[1].pocket.currency ||
        movements[0].pocket.nature != movements[1].pocket.nature) {
      throw StateError(
        'A transfer requires two same-nature pockets in the same currency.',
      );
    }
    if (movements[0].amountMinor + movements[1].amountMinor != 0) {
      throw StateError('Transfer movements must be equal and opposite.');
    }
    _requireNoSplits();
  }

  void _requireCurrencyExchange() {
    if (movements.length != 2 ||
        movements[0].amountMinor >= 0 ||
        movements[1].amountMinor <= 0) {
      throw StateError(
        'Currency exchange requires a negative source and positive destination.',
      );
    }
    if (movements[0].pocket.currency == movements[1].pocket.currency ||
        fxConversion == null) {
      throw StateError(
        'Currency exchange requires different currencies and FX metadata.',
      );
    }
    if (fxConversion!.fromMovementId != movements[0].id ||
        fxConversion!.toMovementId != movements[1].id) {
      throw StateError('FX metadata must reference both exchange movements.');
    }
    _requireNoSplits();
  }

  void _requireDebtPayment() {
    if (movements.length != 2 ||
        movements[0].pocket.nature != AccountNature.asset ||
        movements[1].pocket.nature != AccountNature.liability ||
        movements[0].amountMinor >= 0 ||
        movements[1].amountMinor >= 0) {
      throw StateError(
        '$type requires negative asset and liability movements.',
      );
    }
    if (movements[0].pocket.currency != movements[1].pocket.currency ||
        movements[0].amountMinor != movements[1].amountMinor) {
      throw StateError('$type principal movements must match.');
    }
    _requireNoSplits();
  }

  void _requireNoSplits() {
    if (splits.isNotEmpty) {
      throw StateError('$type must not create income or expense splits.');
    }
  }
}

bool _hasDuplicates(Iterable<String> values) {
  final seen = <String>{};
  return values.any((value) => !seen.add(value));
}
