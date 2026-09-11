import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/credit_card_service.dart';
import '../../domain/credit_cards/credit_card_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class CreditCardState {
  const CreditCardState({
    this.card,
    this.overview,
    this.loading = false,
    this.error,
  });

  final CreditCardContext? card;
  final CreditCardOverview? overview;
  final bool loading;
  final Object? error;
}

final class CreditCardController extends StateNotifier<CreditCardState> {
  CreditCardController({
    required CreditCardService? service,
    required CreditCardContext? initialCard,
    Future<void> Function()? onLedgerChanged,
  }) : this._(service, initialCard, onLedgerChanged);

  CreditCardController._(
    this._service,
    CreditCardContext? initialCard,
    this._onLedgerChanged,
  ) : super(CreditCardState(card: initialCard));

  final CreditCardService? _service;
  final Future<void> Function()? _onLedgerChanged;

  Future<void> select(CreditCardContext card) async {
    state = CreditCardState(card: card);
    await reload();
  }

  Future<void> reload() async {
    final service = _service;
    final card = state.card;
    if (service == null || card == null) return;
    state = CreditCardState(
      card: card,
      overview: state.overview,
      loading: true,
    );
    try {
      state = CreditCardState(
        card: card,
        overview: await service.overview(
          card: card,
          asOf: _today(),
          now: UtcInstant.now(),
        ),
      );
    } catch (error) {
      state = CreditCardState(
        card: card,
        overview: state.overview,
        error: error,
      );
    }
  }

  Future<void> configure({
    required int closingDay,
    required int dueDay,
    required String limitText,
  }) => _mutate(
    () => _requiredService.configure(
      card: _requiredCard,
      closingDay: closingDay,
      dueDay: dueDay,
      limitMinor: _money(limitText, _requiredCard.currency).minorUnits,
    ),
    ledgerChanged: false,
  );

  Future<void> purchase({
    required String amountText,
    required EntityId categoryId,
    required LocalDate date,
    String? title,
  }) => _mutate(
    () => _requiredService.purchase(
      card: _requiredCard,
      amount: _money(amountText, _requiredCard.currency),
      categoryId: categoryId,
      date: date,
      now: UtcInstant.now(),
      title: title,
    ),
  );

  Future<void> refund({
    required LedgerTransaction original,
    required String amountText,
    required LocalDate date,
  }) => _mutate(
    () => _requiredService.refund(
      card: _requiredCard,
      original: original,
      amount: _money(amountText, _requiredCard.currency),
      date: date,
      now: UtcInstant.now(),
    ),
  );

  Future<void> pay({
    required CreditCardStatement statement,
    required LedgerPocket bankPocket,
    required String amountText,
    required LocalDate date,
  }) => _mutate(
    () => _requiredService.payStatement(
      card: _requiredCard,
      statement: statement,
      bankPocket: bankPocket,
      amount: _money(amountText, _requiredCard.currency),
      date: date,
      now: UtcInstant.now(),
    ),
  );

  Future<void> charge({
    required String amountText,
    required EntityId categoryId,
    required LocalDate date,
    required String title,
  }) => _mutate(
    () => _requiredService.chargeFeeOrInterest(
      card: _requiredCard,
      amount: _money(amountText, _requiredCard.currency),
      categoryId: categoryId,
      date: date,
      now: UtcInstant.now(),
      title: title,
    ),
  );

  Future<void> installment({
    required String originalText,
    required String financedText,
    required int count,
    required EntityId categoryId,
    required LocalDate firstDate,
    required String description,
    String? interestRate,
  }) => _mutate(
    () => _requiredService.createInstallmentPlan(
      card: _requiredCard,
      originalAmount: _money(originalText, _requiredCard.currency),
      financedAmount: _money(financedText, _requiredCard.currency),
      installmentCount: count,
      categoryId: categoryId,
      firstInstallmentDate: firstDate,
      asOf: _today(),
      now: UtcInstant.now(),
      description: description,
      interestRate: interestRate?.trim().isEmpty ?? true
          ? null
          : _normalizeDecimal(interestRate!),
    ),
  );

  Future<void> cancelPlan(InstallmentPlanView plan) => _mutate(
    () => _requiredService.cancelInstallmentPlan(
      card: _requiredCard,
      value: plan,
      refundDate: _today(),
      now: UtcInstant.now(),
    ),
  );

  Future<void> _mutate(
    Future<Object?> Function() action, {
    bool ledgerChanged = true,
  }) async {
    if (state.loading) return;
    state = CreditCardState(
      card: state.card,
      overview: state.overview,
      loading: true,
    );
    try {
      await action();
      if (ledgerChanged) await _onLedgerChanged?.call();
      await reload();
    } catch (error) {
      state = CreditCardState(
        card: state.card,
        overview: state.overview,
        error: error,
      );
    }
  }

  CreditCardService get _requiredService =>
      _service ?? (throw StateError('Credit-card services are unavailable.'));

  CreditCardContext get _requiredCard =>
      state.card ?? (throw StateError('Select a credit card first.'));

  Money _money(String input, CurrencyCode currency) {
    final major = DecimalValue.parse(_normalizeDecimal(input));
    if (major <= Decimal.zero) throw ArgumentError('Amount must be positive.');
    return Money.fromMajor(
      currency: CurrencyDefinition(code: currency, minorUnits: 2),
      majorUnits: major,
    );
  }

  String _normalizeDecimal(String input) {
    var value = input.trim().replaceAll(RegExp(r'\s'), '');
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      value = comma > dot
          ? value.replaceAll('.', '').replaceAll(',', '.')
          : value.replaceAll(',', '');
    } else if (comma >= 0) {
      value = value.replaceAll(',', '.');
    }
    return value;
  }
}

LocalDate _today() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}
