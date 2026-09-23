import 'package:decimal/decimal.dart';

import '../../domain/investments/investment_models.dart';
import '../../domain/ledger/ledger_engine.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/decimal_value.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/money.dart';
import '../../domain/shared/utc_instant.dart';
import '../../domain/shared/uuid_v7.dart';
import '../ports/dashboard_repository.dart';
import '../ports/investment_repository.dart';
import '../ports/local_unit_of_work.dart';

enum InitialPositionMode { historicalBuy, openingPosition }

final class InitialPositionDraft {
  const InitialPositionDraft({
    required this.mode,
    required this.cashPocket,
    required this.quantity,
    required this.unitPrice,
    required this.date,
    this.feesMinor = 0,
    this.taxesMinor = 0,
  });

  final InitialPositionMode mode;
  final LedgerPocket cashPocket;
  final Decimal quantity;
  final Decimal unitPrice;
  final LocalDate date;
  final int feesMinor;
  final int taxesMinor;
}

final class InvestmentService {
  InvestmentService({
    required this.repository,
    required this.reporting,
    this.unitOfWork,
    LedgerEngine? ledgerEngine,
  }) : ledgerEngine = ledgerEngine ?? LedgerEngine();
  final InvestmentRepository repository;
  final DashboardRepository reporting;
  final LocalUnitOfWork? unitOfWork;
  final LedgerEngine ledgerEngine;

  Future<InvestmentInstrument> createInstrument({
    required EntityId vaultId,
    required String name,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    required UtcInstant now,
    String? symbol,
    String? exchange,
    String? isin,
    String? providerSymbol,
    String? providerName,
    bool customInstrument = false,
  }) async {
    final value = InvestmentInstrument(
      id: EntityId.generate(),
      vaultId: vaultId,
      symbol: _optional(symbol)?.toUpperCase(),
      name: name.trim(),
      assetClass: assetClass,
      exchange: _optional(exchange),
      currency: currency,
      isin: _optional(isin),
      providerSymbol: _optional(providerSymbol),
      providerName: _optional(providerName),
      customInstrument: customInstrument,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveInstrument(value);
    return value;
  }

  Future<InvestmentInstrument> createInstrumentWithInitialPosition({
    required EntityId vaultId,
    required String name,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    required UtcInstant now,
    String? symbol,
    String? exchange,
    String? isin,
    String? providerSymbol,
    String? providerName,
    bool customInstrument = false,
    InitialPositionDraft? initialPosition,
  }) => _atomic(() async {
    final instrument = await createInstrument(
      vaultId: vaultId,
      name: name,
      assetClass: assetClass,
      currency: currency,
      now: now,
      symbol: symbol,
      exchange: exchange,
      isin: isin,
      providerSymbol: providerSymbol,
      providerName: providerName,
      customInstrument: customInstrument,
    );
    final initial = initialPosition;
    if (initial != null) {
      if (initial.mode == InitialPositionMode.historicalBuy) {
        await buy(
          instrument: instrument,
          cashPocket: initial.cashPocket,
          quantity: initial.quantity,
          unitPrice: initial.unitPrice,
          date: initial.date,
          now: now,
          feesMinor: initial.feesMinor,
          taxesMinor: initial.taxesMinor,
        );
      } else {
        await importOpeningPosition(
          instrument: instrument,
          cashPocket: initial.cashPocket,
          quantity: initial.quantity,
          unitPrice: initial.unitPrice,
          date: initial.date,
          now: now,
          feesMinor: initial.feesMinor,
          taxesMinor: initial.taxesMinor,
        );
      }
    }
    return instrument;
  });

  Future<InvestmentInstrument> linkMarketCandidate({
    required InvestmentInstrument instrument,
    required MarketInstrumentCandidate candidate,
    required UtcInstant now,
  }) async {
    if (candidate.currency != instrument.currency) {
      throw InvestmentCurrencyMismatch(
        expected: instrument.currency,
        actual: candidate.currency,
      );
    }
    final revised = instrument.revise(
      symbol: candidate.symbol,
      exchange: candidate.exchange,
      providerSymbol: candidate.providerSymbol,
      providerName: candidate.provider.name,
      customInstrument: false,
      at: now,
    );
    await repository.saveInstrument(revised);
    return revised;
  }

  Future<void> deleteInstrument(
    InvestmentInstrument value,
    UtcInstant now,
  ) async {
    if (await repository.hasProtectedHistory(value.id)) {
      throw InvestmentAssetInUse(value.id);
    }
    await repository.saveInstrument(value.revise(deletedAt: now, at: now));
  }

  Future<LedgerTransaction> buy({
    required InvestmentInstrument instrument,
    required LedgerPocket cashPocket,
    required Decimal quantity,
    required Decimal unitPrice,
    required LocalDate date,
    required UtcInstant now,
    int feesMinor = 0,
    int taxesMinor = 0,
  }) async {
    _matchingCurrency(cashPocket, instrument.currency);
    _positive(quantity, 'quantity');
    _positive(unitPrice, 'unitPrice');
    _nonNegative(feesMinor, 'feesMinor');
    _nonNegative(taxesMinor, 'taxesMinor');
    final gross = await _priceMinor(quantity, unitPrice, instrument.currency);
    final event = LedgerInvestmentEvent(
      id: EntityId.generate(),
      instrumentId: instrument.id,
      eventType: 'buy',
      quantity: quantity.toString(),
      unitPrice: unitPrice.toString(),
      priceCurrency: instrument.currency,
      grossMinor: gross,
      feesMinor: feesMinor,
      taxesMinor: taxesMinor,
    );
    final transaction = ledgerEngine.investmentBuy(
      vaultId: instrument.vaultId,
      cashPocket: cashPocket,
      totalCash: Money(
        currency: instrument.currency,
        minorUnits: gross + feesMinor + taxesMinor,
      ),
      event: event,
      date: date,
      now: now,
    );
    final lot = InvestmentLot(
      id: EntityId.generate(),
      acquisitionEventId: event.id,
      instrumentId: instrument.id,
      acquiredOn: date,
      originalQuantity: quantity,
      costBasisMinor: gross + feesMinor + taxesMinor,
      costCurrency: instrument.currency,
    );
    await repository.saveBuy(transaction, lot);
    return transaction;
  }

  Future<LedgerTransaction> importOpeningPosition({
    required InvestmentInstrument instrument,
    required LedgerPocket cashPocket,
    required Decimal quantity,
    required Decimal unitPrice,
    required LocalDate date,
    required UtcInstant now,
    int feesMinor = 0,
    int taxesMinor = 0,
  }) async {
    _matchingCurrency(cashPocket, instrument.currency);
    _positive(quantity, 'quantity');
    _positive(unitPrice, 'unitPrice');
    _nonNegative(feesMinor, 'feesMinor');
    _nonNegative(taxesMinor, 'taxesMinor');
    final gross = await _priceMinor(quantity, unitPrice, instrument.currency);
    final event = LedgerInvestmentEvent(
      id: EntityId.generate(),
      instrumentId: instrument.id,
      eventType: 'buy',
      quantity: quantity.toString(),
      unitPrice: unitPrice.toString(),
      priceCurrency: instrument.currency,
      grossMinor: gross,
      feesMinor: feesMinor,
      taxesMinor: taxesMinor,
    );
    final total = gross + feesMinor + taxesMinor;
    final transaction = ledgerEngine.investmentOpeningPosition(
      vaultId: instrument.vaultId,
      cashPocket: cashPocket,
      totalCost: Money(currency: instrument.currency, minorUnits: total),
      event: event,
      date: date,
      now: now,
    );
    final lot = InvestmentLot(
      id: EntityId.generate(),
      acquisitionEventId: event.id,
      instrumentId: instrument.id,
      acquiredOn: date,
      originalQuantity: quantity,
      costBasisMinor: total,
      costCurrency: instrument.currency,
    );
    await repository.saveBuy(transaction, lot);
    return transaction;
  }

  Future<LedgerTransaction> sell({
    required InvestmentInstrument instrument,
    required LedgerPocket cashPocket,
    required Decimal quantity,
    required Decimal unitPrice,
    required LocalDate date,
    required UtcInstant now,
    int feesMinor = 0,
    int taxesMinor = 0,
  }) async {
    _matchingCurrency(cashPocket, instrument.currency);
    _positive(quantity, 'quantity');
    _positive(unitPrice, 'unitPrice');
    final positions = await repository.lotPositions(instrument.id, asOf: date);
    var needed = quantity;
    final allocations = <(LotPosition, Decimal, int)>[];
    for (final position in positions.where(
      (item) => item.remainingQuantity > Decimal.zero,
    )) {
      if (needed <= Decimal.zero) break;
      final take = needed < position.remainingQuantity
          ? needed
          : position.remainingQuantity;
      final allocated = take == position.remainingQuantity
          ? position.remainingCostMinor
          : DecimalValue.round(
              (Decimal.fromInt(position.remainingCostMinor) *
                      take /
                      position.remainingQuantity)
                  .toDecimal(scaleOnInfinitePrecision: 24),
              scale: 0,
            ).toBigInt().toInt();
      allocations.add((position, take, allocated));
      needed -= take;
    }
    if (needed > Decimal.zero) throw InsufficientLotQuantity(instrument.id);
    final gross = await _priceMinor(quantity, unitPrice, instrument.currency);
    final net = gross - feesMinor - taxesMinor;
    if (net <= 0) throw ArgumentError('Sale proceeds must remain positive.');
    final event = LedgerInvestmentEvent(
      id: EntityId.generate(),
      instrumentId: instrument.id,
      eventType: 'sell',
      quantity: quantity.toString(),
      unitPrice: unitPrice.toString(),
      priceCurrency: instrument.currency,
      grossMinor: gross,
      feesMinor: feesMinor,
      taxesMinor: taxesMinor,
    );
    final transaction = ledgerEngine.investmentSell(
      vaultId: instrument.vaultId,
      cashPocket: cashPocket,
      netCash: Money(currency: instrument.currency, minorUnits: net),
      event: event,
      date: date,
      now: now,
    );
    await repository.saveSale(transaction, [
      for (final item in allocations)
        LotDisposal(
          id: EntityId.generate(),
          disposalEventId: event.id,
          lotId: item.$1.lot.id,
          quantity: item.$2,
          allocatedCostMinor: item.$3,
        ),
    ]);
    return transaction;
  }

  Future<LedgerTransaction> income({
    required InvestmentInstrument instrument,
    required LedgerPocket cashPocket,
    required EntityId categoryId,
    required int amountMinor,
    required LocalDate date,
    required UtcInstant now,
    required bool interest,
  }) async {
    _matchingCurrency(cashPocket, instrument.currency);
    final event = LedgerInvestmentEvent(
      id: EntityId.generate(),
      instrumentId: instrument.id,
      eventType: interest ? 'interest' : 'dividend',
      priceCurrency: instrument.currency,
      grossMinor: amountMinor,
      feesMinor: 0,
      taxesMinor: 0,
    );
    final money = Money(currency: instrument.currency, minorUnits: amountMinor);
    final transaction = interest
        ? ledgerEngine.interest(
            vaultId: instrument.vaultId,
            cashPocket: cashPocket,
            amount: money,
            categoryId: categoryId,
            event: event,
            date: date,
            now: now,
          )
        : ledgerEngine.dividend(
            vaultId: instrument.vaultId,
            cashPocket: cashPocket,
            amount: money,
            categoryId: categoryId,
            event: event,
            date: date,
            now: now,
          );
    await repository.saveLedgerTransaction(transaction);
    return transaction;
  }

  Future<LedgerTransaction> fee({
    required EntityId vaultId,
    required LedgerPocket cashPocket,
    required EntityId categoryId,
    required int amountMinor,
    required LocalDate date,
    required UtcInstant now,
  }) async {
    final transaction = ledgerEngine.fee(
      vaultId: vaultId,
      pocket: cashPocket,
      amount: Money(currency: cashPocket.currency, minorUnits: amountMinor),
      categoryId: categoryId,
      date: date,
      now: now,
    );
    await repository.saveLedgerTransaction(transaction);
    return transaction;
  }

  Future<LedgerTransaction> transferCash({
    required EntityId vaultId,
    required LedgerPocket regularCash,
    required LedgerPocket investmentCash,
    required int amountMinor,
    required LocalDate date,
    required UtcInstant now,
    required bool deposit,
  }) async {
    _matchingCurrency(investmentCash, regularCash.currency);
    final money = Money(
      currency: regularCash.currency,
      minorUnits: amountMinor,
    );
    final transaction = deposit
        ? ledgerEngine.investmentContribution(
            vaultId: vaultId,
            cashPocket: regularCash,
            investmentCashPocket: investmentCash,
            amount: money,
            date: date,
            now: now,
          )
        : ledgerEngine.investmentWithdrawal(
            vaultId: vaultId,
            investmentCashPocket: investmentCash,
            cashPocket: regularCash,
            amount: money,
            date: date,
            now: now,
          );
    await repository.saveLedgerTransaction(transaction);
    return transaction;
  }

  void _matchingCurrency(LedgerPocket pocket, CurrencyCode expected) {
    if (pocket.currency != expected) {
      throw InvestmentCurrencyMismatch(
        expected: expected,
        actual: pocket.currency,
      );
    }
  }

  Future<PortfolioReport> report({
    required EntityId vaultId,
    required CurrencyCode currency,
    required LocalDate asOf,
  }) async {
    reporting.beginRead();
    final drafts =
        <
          (
            InvestmentInstrument,
            List<LotPosition>,
            InvestmentPerformanceSource,
            InvestmentPrice?,
            int?,
            int?,
            bool,
            bool,
          )
        >[];
    for (final instrument in await repository.listInstruments(vaultId)) {
      final lots = await repository.lotPositions(instrument.id, asOf: asOf);
      final quantity = lots.fold(
        Decimal.zero,
        (sum, item) => sum + item.remainingQuantity,
      );
      final performance = await repository.performance(
        instrument.id,
        asOf: asOf,
      );
      final price = await repository.latestPrice(
        vaultId,
        instrument.id,
        instrument.currency,
        asOf: asOf,
      );
      int? marketOriginal;
      int? marketReporting;
      var missing = false;
      var estimated = false;
      if (price != null && quantity > Decimal.zero) {
        marketOriginal = await _priceMinor(
          quantity,
          price.price,
          price.currency,
        );
        final converted = await reporting.convertMinor(
          vaultId: vaultId,
          source: price.currency,
          target: currency,
          date: asOf,
          amountMinor: marketOriginal,
        );
        if (converted == null) {
          missing = true;
        } else {
          marketReporting = converted.minorUnits;
          estimated = converted.estimated;
        }
      }
      drafts.add((
        instrument,
        lots,
        performance,
        price,
        marketOriginal,
        marketReporting,
        missing,
        estimated,
      ));
    }
    final totalMarket = drafts.fold(0, (sum, item) => sum + (item.$6 ?? 0));
    final holdings = <HoldingReport>[];
    var totalCost = 0, totalUnrealized = 0, totalRealized = 0, totalIncome = 0;
    for (final item in drafts) {
      final quantity = item.$2.fold(
        Decimal.zero,
        (sum, lot) => sum + lot.remainingQuantity,
      );
      final cost = item.$2.fold(0, (sum, lot) => sum + lot.remainingCostMinor);
      final scale = await repository.currencyMinorUnits(item.$1.currency);
      final average = quantity == Decimal.zero
          ? Decimal.zero
          : (Decimal.fromInt(cost).shift(-scale) / quantity).toDecimal(
              scaleOnInfinitePrecision: 18,
            );
      int? marketInInstrument;
      if (item.$5 != null) {
        final conversion = await reporting.convertMinor(
          vaultId: vaultId,
          source: item.$4!.currency,
          target: item.$1.currency,
          date: asOf,
          amountMinor: item.$5!,
        );
        marketInInstrument = conversion?.minorUnits;
      }
      final unrealized = marketInInstrument == null
          ? null
          : marketInInstrument - cost;
      final allocation = totalMarket <= 0 || item.$6 == null
          ? 0
          : ((BigInt.from(item.$6!) * BigInt.from(10000)) ~/
                    BigInt.from(totalMarket))
                .toInt();
      holdings.add(
        HoldingReport(
          instrument: item.$1,
          quantity: quantity,
          costBasisMinor: cost,
          averageCost: average,
          marketValueMinor: marketInInstrument,
          reportingMarketValueMinor: item.$6,
          unrealizedMinor: unrealized,
          realizedMinor: item.$3.realizedMinor,
          incomeMinor: item.$3.incomeMinor,
          allocationBps: allocation,
          price: item.$4,
          lots: item.$2,
          missingFx: item.$7,
          estimatedFx: item.$8,
        ),
      );
      final costReporting = await reporting.convertMinor(
        vaultId: vaultId,
        source: item.$1.currency,
        target: currency,
        date: asOf,
        amountMinor: cost,
      );
      final realizedReporting = await reporting.convertMinor(
        vaultId: vaultId,
        source: item.$1.currency,
        target: currency,
        date: asOf,
        amountMinor: item.$3.realizedMinor,
      );
      final incomeReporting = await reporting.convertMinor(
        vaultId: vaultId,
        source: item.$1.currency,
        target: currency,
        date: asOf,
        amountMinor: item.$3.incomeMinor,
      );
      totalCost += costReporting?.minorUnits ?? 0;
      if (item.$6 != null && costReporting != null) {
        totalUnrealized += item.$6! - costReporting.minorUnits;
      }
      totalRealized += realizedReporting?.minorUnits ?? 0;
      totalIncome += incomeReporting?.minorUnits ?? 0;
    }
    holdings.sort(
      (a, b) => (b.reportingMarketValueMinor ?? 0).compareTo(
        a.reportingMarketValueMinor ?? 0,
      ),
    );
    return PortfolioReport(
      currency: currency,
      holdings: holdings,
      marketValueMinor: totalMarket,
      costBasisMinor: totalCost,
      unrealizedMinor: totalUnrealized,
      realizedMinor: totalRealized,
      incomeMinor: totalIncome,
    );
  }

  Future<T> _atomic<T>(Future<T> Function() action) =>
      unitOfWork?.run(action) ?? action();

  Future<int> _priceMinor(
    Decimal quantity,
    Decimal price,
    CurrencyCode currency,
  ) async {
    final scale = await repository.currencyMinorUnits(currency);
    return DecimalValue.round(
      (quantity * price).shift(scale),
      scale: 0,
    ).toBigInt().toInt();
  }
}

void _positive(Decimal value, String name) {
  if (value <= Decimal.zero) throw ArgumentError.value(value, name);
}

void _nonNegative(int value, String name) {
  if (value < 0) throw RangeError.value(value, name);
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
