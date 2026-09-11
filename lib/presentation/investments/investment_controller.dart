import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/investment_service.dart';
import '../../application/services/market_data_service.dart';
import '../../domain/investments/investment_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';

final class InvestmentState {
  const InvestmentState({
    this.report,
    this.prices = const [],
    this.loading = false,
    this.error,
  });
  final PortfolioReport? report;
  final List<MarketPriceState> prices;
  final bool loading;
  final Object? error;
}

final class InvestmentController extends StateNotifier<InvestmentState> {
  InvestmentController({
    required InvestmentService? service,
    required MarketDataService? market,
    required EntityId? vaultId,
    required CurrencyCode? reportingCurrency,
  }) : this._(service, market, vaultId, reportingCurrency);
  InvestmentController._(
    this._service,
    this._market,
    this._vaultId,
    this._currency,
  ) : super(const InvestmentState());
  final InvestmentService? _service;
  final MarketDataService? _market;
  final EntityId? _vaultId;
  final CurrencyCode? _currency;

  Future<void> reload() async {
    if (_service == null || _vaultId == null || _currency == null) return;
    state = InvestmentState(
      report: state.report,
      prices: state.prices,
      loading: true,
    );
    try {
      final today = _today();
      final values = await Future.wait<Object>([
        _service.report(vaultId: _vaultId, currency: _currency, asOf: today),
        if (_market != null)
          _market.load(vaultId: _vaultId, asOf: today, now: UtcInstant.now())
        else
          Future.value(<MarketPriceState>[]),
      ]);
      state = InvestmentState(
        report: values[0] as PortfolioReport,
        prices: values[1] as List<MarketPriceState>,
      );
    } catch (error) {
      state = InvestmentState(
        report: state.report,
        prices: state.prices,
        error: error,
      );
    }
  }

  Future<void> createInstrument({
    required String name,
    required String symbol,
    required String exchange,
    required InvestmentAssetClass assetClass,
  }) => _mutate(() async {
    await _required.createInstrument(
      vaultId: _requiredVault,
      name: name,
      symbol: symbol,
      exchange: exchange,
      assetClass: assetClass,
      currency: _requiredCurrency,
      customInstrument: true,
      now: UtcInstant.now(),
    );
  });
  Future<void> trade({
    required InvestmentInstrument instrument,
    required LedgerPocket pocket,
    required String quantity,
    required String unitPrice,
    required String fees,
    required String taxes,
    required LocalDate date,
    required bool sell,
  }) => _mutate(() async {
    final q = _decimal(quantity), price = _decimal(unitPrice);
    final fee = fees.trim().isEmpty ? 0 : _minor(fees, instrument.currency);
    final tax = taxes.trim().isEmpty ? 0 : _minor(taxes, instrument.currency);
    if (sell) {
      await _required.sell(
        instrument: instrument,
        cashPocket: pocket,
        quantity: q,
        unitPrice: price,
        feesMinor: fee,
        taxesMinor: tax,
        date: date,
        now: UtcInstant.now(),
      );
    } else {
      await _required.buy(
        instrument: instrument,
        cashPocket: pocket,
        quantity: q,
        unitPrice: price,
        feesMinor: fee,
        taxesMinor: tax,
        date: date,
        now: UtcInstant.now(),
      );
    }
  });
  Future<void> income({
    required InvestmentInstrument instrument,
    required LedgerPocket pocket,
    required EntityId categoryId,
    required String amount,
    required LocalDate date,
    required bool interest,
  }) => _mutate(() async {
    await _required.income(
      instrument: instrument,
      cashPocket: pocket,
      categoryId: categoryId,
      amountMinor: _minor(amount, instrument.currency),
      date: date,
      now: UtcInstant.now(),
      interest: interest,
    );
  });
  Future<void> fee({
    required LedgerPocket pocket,
    required EntityId categoryId,
    required String amount,
    required LocalDate date,
  }) => _mutate(() async {
    await _required.fee(
      vaultId: _requiredVault,
      cashPocket: pocket,
      categoryId: categoryId,
      amountMinor: _minor(amount, pocket.currency),
      date: date,
      now: UtcInstant.now(),
    );
  });
  Future<void> transferCash({
    required LedgerPocket regular,
    required LedgerPocket investment,
    required String amount,
    required LocalDate date,
    required bool deposit,
  }) => _mutate(() async {
    await _required.transferCash(
      vaultId: _requiredVault,
      regularCash: regular,
      investmentCash: investment,
      amountMinor: _minor(amount, regular.currency),
      date: date,
      now: UtcInstant.now(),
      deposit: deposit,
    );
  });
  Future<void> delete(InvestmentInstrument value) =>
      _mutate(() async => _required.deleteInstrument(value, UtcInstant.now()));
  Future<void> refreshPrices() async {
    final market = _market;
    if (market == null) return;
    state = InvestmentState(
      report: state.report,
      prices: state.prices,
      loading: true,
    );
    try {
      final today = _today();
      final prices = await market.load(
        vaultId: _requiredVault,
        asOf: today,
        now: UtcInstant.now(),
        refresh: true,
      );
      final report = await _required.report(
        vaultId: _requiredVault,
        currency: _requiredCurrency,
        asOf: today,
      );
      state = InvestmentState(report: report, prices: prices);
    } catch (error) {
      state = InvestmentState(
        report: state.report,
        prices: state.prices,
        error: error,
      );
    }
  }

  Future<void> overridePrice(
    InvestmentInstrument instrument,
    String input,
    LocalDate date,
  ) => _mutate(() async {
    final market = _market ?? (throw StateError('Market service unavailable.'));
    await market.override(
      vaultId: _requiredVault,
      instrument: instrument,
      date: date,
      price: _decimal(input),
      now: UtcInstant.now(),
    );
  });
  Future<void> _mutate(Future<void> Function() action) async {
    if (state.loading) return;
    state = InvestmentState(
      report: state.report,
      prices: state.prices,
      loading: true,
    );
    try {
      await action();
      await reload();
    } catch (error) {
      state = InvestmentState(
        report: state.report,
        prices: state.prices,
        error: error,
      );
    }
  }

  InvestmentService get _required =>
      _service ?? (throw StateError('Investment services unavailable.'));
  EntityId get _requiredVault =>
      _vaultId ?? (throw StateError('A local vault is required.'));
  CurrencyCode get _requiredCurrency =>
      _currency ?? (throw StateError('A reporting currency is required.'));
  Decimal _decimal(String value) =>
      DecimalValue.parse(value.trim().replaceAll(',', '.'));
  int _minor(String value, CurrencyCode currency) => Money.fromMajor(
    currency: CurrencyDefinition(code: currency, minorUnits: 2),
    majorUnits: _decimal(value),
  ).minorUnits;
}

LocalDate _today() {
  final n = DateTime.now();
  return LocalDate(n.year, n.month, n.day);
}
