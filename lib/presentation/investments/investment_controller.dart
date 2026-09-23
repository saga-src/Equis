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
    this.lastRefresh,
  });
  final PortfolioReport? report;
  final List<MarketPriceState> prices;
  final bool loading;
  final Object? error;
  final MarketRefreshSummary? lastRefresh;
}

final class MarketRefreshSummary {
  const MarketRefreshSummary({required this.updated, required this.failed});
  final int updated;
  final int failed;
}

final class InvestmentController extends StateNotifier<InvestmentState> {
  InvestmentController({
    required InvestmentService? service,
    required MarketDataService? market,
    required EntityId? vaultId,
    required CurrencyCode? reportingCurrency,
    Future<void> Function()? onChanged,
  }) : this._(service, market, vaultId, reportingCurrency, onChanged);
  InvestmentController._(
    this._service,
    this._market,
    this._vaultId,
    this._currency,
    this._onChanged,
  ) : super(const InvestmentState());
  final InvestmentService? _service;
  final MarketDataService? _market;
  final EntityId? _vaultId;
  final CurrencyCode? _currency;
  final Future<void> Function()? _onChanged;

  Future<void> reload() async {
    if (_service == null || _vaultId == null || _currency == null) return;
    state = InvestmentState(
      report: state.report,
      prices: state.prices,
      loading: true,
      lastRefresh: state.lastRefresh,
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
        lastRefresh: state.lastRefresh,
      );
    } catch (error) {
      state = InvestmentState(
        report: state.report,
        prices: state.prices,
        error: error,
        lastRefresh: state.lastRefresh,
      );
    }
  }

  Future<void> createInstrument({
    required String name,
    required String symbol,
    required String exchange,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    MarketInstrumentCandidate? candidate,
    MarketQuotePreview? preview,
    InitialPositionMode? initialMode,
    LedgerPocket? initialPocket,
    String quantity = '',
    String unitPrice = '',
    String fees = '',
    String taxes = '',
    LocalDate? date,
  }) => _mutate(() async {
    final selected = candidate;
    final initial = initialMode == null
        ? null
        : InitialPositionDraft(
            mode: initialMode,
            cashPocket:
                initialPocket ??
                (throw ArgumentError('An investment account is required.')),
            quantity: _decimal(quantity),
            unitPrice: _decimal(unitPrice),
            date: date ?? _today(),
            feesMinor: fees.trim().isEmpty
                ? 0
                : _minor(fees, selected?.currency ?? currency),
            taxesMinor: taxes.trim().isEmpty
                ? 0
                : _minor(taxes, selected?.currency ?? currency),
          );
    final instrument = await _required.createInstrumentWithInitialPosition(
      vaultId: _requiredVault,
      name: selected?.name ?? name,
      symbol: selected?.symbol ?? symbol,
      exchange: selected?.exchange ?? exchange,
      assetClass: selected?.assetClass ?? assetClass,
      currency: selected?.currency ?? currency,
      providerSymbol: selected?.providerSymbol,
      providerName: selected?.provider.name,
      customInstrument: selected == null,
      initialPosition: initial,
      now: UtcInstant.now(),
    );
    if (preview != null && _market != null) {
      try {
        await _market.savePreview(instrument, preview);
      } on Exception {
        // The financial aggregate is already committed; a later refresh can rebuild this cache.
      }
    }
  });

  Future<List<MarketInstrumentCandidate>> searchInstruments({
    required String query,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
  }) => (_market ?? (throw StateError('Market service unavailable.'))).search(
    query: query,
    assetClass: assetClass,
    currency: currency,
  );

  Future<MarketQuotePreview?> quoteCandidate(
    MarketInstrumentCandidate candidate,
  ) => (_market ?? (throw StateError('Market service unavailable.')))
      .quoteCandidate(candidate);

  Future<void> linkMarketCandidate({
    required InvestmentInstrument instrument,
    required MarketInstrumentCandidate candidate,
    MarketQuotePreview? preview,
  }) => _mutate(() async {
    final linked = await _required.linkMarketCandidate(
      instrument: instrument,
      candidate: candidate,
      now: UtcInstant.now(),
    );
    if (preview != null && _market != null) {
      await _market.savePreview(linked, preview);
    }
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
      lastRefresh: state.lastRefresh,
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
      state = InvestmentState(
        report: report,
        prices: prices,
        lastRefresh: MarketRefreshSummary(
          updated: prices.where((item) => item.refreshed).length,
          failed: prices.where((item) => item.refreshFailed).length,
        ),
      );
    } catch (error, stackTrace) {
      state = InvestmentState(
        report: state.report,
        prices: state.prices,
        error: error,
        lastRefresh: state.lastRefresh,
      );
      Error.throwWithStackTrace(error, stackTrace);
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
      lastRefresh: state.lastRefresh,
    );
    try {
      await action();
      await _onChanged?.call();
      await reload();
    } catch (error, stackTrace) {
      state = InvestmentState(
        report: state.report,
        prices: state.prices,
        error: error,
        lastRefresh: state.lastRefresh,
      );
      Error.throwWithStackTrace(error, stackTrace);
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
