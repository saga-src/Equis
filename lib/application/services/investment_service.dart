import 'package:decimal/decimal.dart';

import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/investments/investment_models.dart';
import '../../domain/investments/fixed_income_valuation.dart';
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
import '../ports/account_sync_read_status.dart';
import '../ports/investment_repository.dart';
import '../../domain/investments/fixed_income_contract.dart';
import '../ports/local_unit_of_work.dart';
import 'economic_series_service.dart';

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
    this.contractTerms,
  });

  final InitialPositionMode mode;
  final LedgerPocket cashPocket;
  final Decimal quantity;
  final Decimal unitPrice;
  final LocalDate date;
  final int feesMinor;
  final int taxesMinor;
  final FixedIncomeTerms? contractTerms;
}

final class InvestmentService {
  InvestmentService({
    required this.repository,
    required this.reporting,
    this.unitOfWork,
    this.economicSeries,
    this.businessCalendar,
    LedgerEngine? ledgerEngine,
    FixedIncomeValuator? fixedIncomeValuator,
    UtcInstant Function()? clock,
  }) : ledgerEngine = ledgerEngine ?? LedgerEngine(),
       fixedIncomeValuator = fixedIncomeValuator ?? const FixedIncomeValuator(),
       _clock = clock ?? UtcInstant.now;
  final InvestmentRepository repository;
  final DashboardRepository reporting;
  final LocalUnitOfWork? unitOfWork;
  final LedgerEngine ledgerEngine;
  final EconomicSeriesService? economicSeries;
  final BusinessCalendar? businessCalendar;
  final FixedIncomeValuator fixedIncomeValuator;
  final UtcInstant Function() _clock;

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
          contractTerms: initial.contractTerms,
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
          contractTerms: initial.contractTerms,
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
    FixedIncomeTerms? contractTerms,
  }) async {
    if (contractTerms != null &&
        (instrument.assetClass != InvestmentAssetClass.fixedIncome ||
            contractTerms.currency != instrument.currency)) {
      throw ArgumentError(
        'Contract terms must match a fixed-income instrument.',
      );
    }
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
    await repository.saveBuy(
      transaction,
      lot,
      contract: contractTerms == null
          ? null
          : FixedIncomeContract(lotId: lot.id, terms: contractTerms),
    );
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
    FixedIncomeTerms? contractTerms,
  }) async {
    if (contractTerms != null &&
        (instrument.assetClass != InvestmentAssetClass.fixedIncome ||
            contractTerms.currency != instrument.currency)) {
      throw ArgumentError(
        'Contract terms must match a fixed-income instrument.',
      );
    }
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
    await repository.saveBuy(
      transaction,
      lot,
      contract: contractTerms == null
          ? null
          : FixedIncomeContract(lotId: lot.id, terms: contractTerms),
    );
    return transaction;
  }

  Future<InvestmentLotEditorSnapshot?> loadLotEditor({
    required EntityId vaultId,
    required EntityId lotId,
    required LocalDate asOf,
  }) => repository.loadLotEditor(vaultId: vaultId, lotId: lotId, asOf: asOf);

  Future<int> reviseContract({
    required EntityId vaultId,
    required FixedIncomeContract contract,
    required int expectedTransactionRevision,
    required UtcInstant now,
    String? expectedDisposalFingerprint,
  }) => repository.saveContract(
    vaultId: vaultId,
    contract: contract,
    expectedTransactionRevision: expectedTransactionRevision,
    updatedAt: now,
    expectedDisposalFingerprint: expectedDisposalFingerprint,
  );

  Future<int> recordManualValue({
    required EntityId vaultId,
    required EntityId lotId,
    required LocalDate valueDate,
    required int amountMinor,
    required CurrencyCode currency,
    required int expectedTransactionRevision,
    required UtcInstant now,
    String? notes,
    String? expectedDisposalFingerprint,
  }) => repository.addManualValue(
    vaultId: vaultId,
    value: FixedIncomeManualValue(
      id: EntityId.generate(),
      lotId: lotId,
      valueDate: valueDate,
      amountMinor: amountMinor,
      currency: currency,
      notes: notes,
      recordedAt: now,
    ),
    expectedTransactionRevision: expectedTransactionRevision,
    updatedAt: now,
    expectedDisposalFingerprint: expectedDisposalFingerprint,
  );

  Future<int> removeManualValue({
    required EntityId vaultId,
    required EntityId lotId,
    required EntityId valueId,
    required int expectedTransactionRevision,
    required UtcInstant now,
    String? expectedDisposalFingerprint,
  }) => repository.removeManualValue(
    vaultId: vaultId,
    lotId: lotId,
    valueId: valueId,
    expectedTransactionRevision: expectedTransactionRevision,
    updatedAt: now,
    expectedDisposalFingerprint: expectedDisposalFingerprint,
  );

  Future<int> replaceManualValue({
    required EntityId vaultId,
    required EntityId lotId,
    required EntityId valueId,
    required LocalDate valueDate,
    required int amountMinor,
    required CurrencyCode currency,
    required int expectedTransactionRevision,
    required UtcInstant now,
    String? notes,
    String? expectedDisposalFingerprint,
  }) => repository.replaceManualValue(
    vaultId: vaultId,
    oldValueId: valueId,
    newValue: FixedIncomeManualValue(
      id: EntityId.generate(),
      lotId: lotId,
      valueDate: valueDate,
      amountMinor: amountMinor,
      currency: currency,
      notes: notes,
      recordedAt: now,
    ),
    expectedTransactionRevision: expectedTransactionRevision,
    updatedAt: now,
    expectedDisposalFingerprint: expectedDisposalFingerprint,
  );

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

  Future<EconomicSeriesRefreshSummary> refreshEconomicSeries({
    required EntityId vaultId,
    required LocalDate asOf,
    UtcInstant? now,
    bool Function()? isActive,
  }) async {
    final series = economicSeries;
    if (series == null ||
        !series.remoteReadsEnabled ||
        !series.isActive ||
        isActive?.call() == false) {
      return const EconomicSeriesRefreshSummary();
    }
    bool active() => series.isActive && isActive?.call() != false;
    return series.prepareRefresh(() async {
      final ranges = <EconomicSeriesCode, EconomicSeriesRange>{};
      for (final instrument in await repository.listInstruments(vaultId)) {
        if (!active()) return const EconomicSeriesRefreshSummary();
        if (instrument.assetClass != InvestmentAssetClass.fixedIncome) continue;
        final lots = await repository.lotPositions(instrument.id, asOf: asOf);
        for (final position in lots) {
          if (!active()) return const EconomicSeriesRefreshSummary();
          if (position.remainingQuantity <= Decimal.zero) continue;
          final contract = await repository.findContract(
            vaultId,
            position.lot.id,
          );
          if (contract == null || contract.terms.indexCode == null) continue;
          final range = _contractSeriesRange(contract.terms, asOf);
          if (range.from.compareTo(range.through) > 0) continue;
          final code = contract.terms.indexCode!;
          final previous = ranges[code];
          ranges[code] = EconomicSeriesRange(
            from: previous != null && previous.from.compareTo(range.from) < 0
                ? previous.from
                : range.from,
            through:
                previous != null &&
                    previous.through.compareTo(range.through) > 0
                ? previous.through
                : range.through,
          );
        }
      }
      return series.refreshRanges(ranges: ranges, now: now, isActive: active);
    });
  }

  EconomicSeriesRange _contractSeriesRange(
    FixedIncomeTerms terms,
    LocalDate asOf,
  ) {
    final end =
        terms.maturityOn != null && asOf.compareTo(terms.maturityOn!) > 0
        ? terms.maturityOn!
        : asOf;
    return EconomicSeriesRange(
      from: terms.mode == FixedIncomeRemunerationMode.monthlyIndex
          ? terms.accrualStart.addDays(-31 * (terms.publicationLagMonths + 2))
          : terms.accrualStart,
      through: switch (terms.mode) {
        FixedIncomeRemunerationMode.dailyIndexPercent ||
        FixedIncomeRemunerationMode.dailyIndexSpread => end.addDays(-1),
        _ => end,
      },
    );
  }

  Future<PortfolioReport> report({
    required EntityId vaultId,
    required CurrencyCode currency,
    required LocalDate asOf,
  }) async {
    reporting.beginRead();
    final calculatedAt = _clock();
    final drafts = <_HoldingDraft>[];
    for (final instrument in await repository.listInstruments(vaultId)) {
      final lots = await repository.lotPositions(instrument.id, asOf: asOf);
      final performance = await repository.performance(
        instrument.id,
        asOf: asOf,
      );
      final contracts = <EntityId, FixedIncomeContract>{};
      if (instrument.assetClass == InvestmentAssetClass.fixedIncome) {
        for (final position in lots.where(
          (item) => item.remainingQuantity > Decimal.zero,
        )) {
          final contract = await repository.findContract(
            vaultId,
            position.lot.id,
          );
          if (contract != null) contracts[position.lot.id] = contract;
        }
      }
      final needsPrice = lots.any(
        (item) =>
            item.remainingQuantity > Decimal.zero &&
            !contracts.containsKey(item.lot.id),
      );
      final price = needsPrice
          ? await repository.latestPrice(
              vaultId,
              instrument.id,
              instrument.currency,
              asOf: asOf,
            )
          : null;
      // Preserve the legacy instrument-level rounding while still exposing a
      // value for each market-priced lot. Cumulative differences sum exactly
      // to price × the total uncontracted quantity rounded once.
      final marketLotAmounts = <EntityId, int>{};
      if (price != null) {
        var cumulativeQuantity = Decimal.zero;
        var allocatedMinor = 0;
        for (final position in lots.where(
          (item) =>
              item.remainingQuantity > Decimal.zero &&
              !contracts.containsKey(item.lot.id),
        )) {
          cumulativeQuantity += position.remainingQuantity;
          final cumulativeMinor = await _priceMinor(
            cumulativeQuantity,
            price.price,
            price.currency,
          );
          marketLotAmounts[position.lot.id] = cumulativeMinor - allocatedMinor;
          allocatedMinor = cumulativeMinor;
        }
      }
      final scale = await repository.currencyMinorUnits(instrument.currency);
      final valuations = <PositionValuation>[];
      final incompleteLotIds = <EntityId>[];
      var marketOriginal = 0;
      var marketReporting = 0;
      var hasKnownValue = false;
      var missingFx = false;
      var estimatedFx = false;
      var marketCumulativeSourceMinor = 0;
      var marketAllocatedInstrumentMinor = 0;
      var marketAllocatedReportingMinor = 0;
      for (final position in lots) {
        if (position.remainingQuantity == Decimal.zero) continue;
        final contract = contracts[position.lot.id];
        final valuation = contract == null
            ? _marketValuation(
                position,
                price,
                marketLotAmounts[position.lot.id],
                asOf,
                calculatedAt,
              )
            : await _contractValuation(
                vaultId: vaultId,
                position: position,
                terms: contract.terms,
                asOf: asOf,
                calculatedAt: calculatedAt,
              );
        valuations.add(valuation);
        final amount = valuation.amountMinor;
        if (amount == null ||
            valuation.state == ValuationState.incomplete ||
            valuation.state == ValuationState.manualRequired) {
          incompleteLotIds.add(position.lot.id);
          continue;
        }
        // Market-priced legacy lots retain the old aggregate FX rounding.
        // Cumulative differences distribute the rounded total across lots.
        final conversionAmount = contract == null
            ? (marketCumulativeSourceMinor += amount)
            : amount;
        final inInstrument = await reporting.convertMinor(
          vaultId: vaultId,
          source: valuation.currency,
          target: instrument.currency,
          date: asOf,
          amountMinor: conversionAmount,
        );
        final inReporting = await reporting.convertMinor(
          vaultId: vaultId,
          source: valuation.currency,
          target: currency,
          date: asOf,
          amountMinor: conversionAmount,
        );
        if (inInstrument == null || inReporting == null) {
          missingFx = true;
          incompleteLotIds.add(position.lot.id);
          continue;
        }
        final instrumentMinor = contract == null
            ? inInstrument.minorUnits - marketAllocatedInstrumentMinor
            : inInstrument.minorUnits;
        final reportingMinor = contract == null
            ? inReporting.minorUnits - marketAllocatedReportingMinor
            : inReporting.minorUnits;
        if (contract == null) {
          marketAllocatedInstrumentMinor = inInstrument.minorUnits;
          marketAllocatedReportingMinor = inReporting.minorUnits;
        }
        marketOriginal += instrumentMinor;
        marketReporting += reportingMinor;
        hasKnownValue = true;
        estimatedFx |= inInstrument.estimated || inReporting.estimated;
      }
      drafts.add(
        _HoldingDraft(
          instrument: instrument,
          lots: lots,
          performance: performance,
          price: price,
          valuations: valuations,
          instrumentValueMinor: hasKnownValue ? marketOriginal : null,
          reportingValueMinor: hasKnownValue ? marketReporting : null,
          incompleteLotIds: incompleteLotIds,
          missingFx: missingFx,
          estimatedFx: estimatedFx,
          currencyMinorUnits: scale,
        ),
      );
    }
    final totalMarket = drafts.fold(
      0,
      (sum, item) => sum + (item.reportingValueMinor ?? 0),
    );
    final holdings = <HoldingReport>[];
    final incompleteLotIds = <EntityId>[];
    var totalCost = 0, totalUnrealized = 0, totalRealized = 0, totalIncome = 0;
    for (final item in drafts) {
      final quantity = item.lots.fold(
        Decimal.zero,
        (sum, lot) => sum + lot.remainingQuantity,
      );
      final cost = item.lots.fold(
        0,
        (sum, lot) => sum + lot.remainingCostMinor,
      );
      final average = quantity == Decimal.zero
          ? Decimal.zero
          : (Decimal.fromInt(cost).shift(-item.currencyMinorUnits) / quantity)
                .toDecimal(scaleOnInfinitePrecision: 18);
      final incomplete = item.incompleteLotIds.isNotEmpty;
      incompleteLotIds.addAll(item.incompleteLotIds);
      final unrealized = incomplete || item.instrumentValueMinor == null
          ? null
          : item.instrumentValueMinor! - cost;
      final allocation =
          incomplete || totalMarket <= 0 || item.reportingValueMinor == null
          ? 0
          : ((BigInt.from(item.reportingValueMinor!) * BigInt.from(10000)) ~/
                    BigInt.from(totalMarket))
                .toInt();
      holdings.add(
        HoldingReport(
          instrument: item.instrument,
          quantity: quantity,
          costBasisMinor: cost,
          averageCost: average,
          marketValueMinor: incomplete ? null : item.instrumentValueMinor,
          reportingMarketValueMinor: incomplete
              ? null
              : item.reportingValueMinor,
          knownValueMinor: item.instrumentValueMinor,
          reportingKnownValueMinor: item.reportingValueMinor,
          unrealizedMinor: unrealized,
          realizedMinor: item.performance.realizedMinor,
          incomeMinor: item.performance.incomeMinor,
          allocationBps: allocation,
          price: item.price,
          lots: item.lots,
          missingFx: item.missingFx,
          estimatedFx: item.estimatedFx,
          lotValuations: item.valuations,
          hasIncompleteValuations: incomplete,
        ),
      );
      final costReporting = await reporting.convertMinor(
        vaultId: vaultId,
        source: item.instrument.currency,
        target: currency,
        date: asOf,
        amountMinor: cost,
      );
      final realizedReporting = await reporting.convertMinor(
        vaultId: vaultId,
        source: item.instrument.currency,
        target: currency,
        date: asOf,
        amountMinor: item.performance.realizedMinor,
      );
      final incomeReporting = await reporting.convertMinor(
        vaultId: vaultId,
        source: item.instrument.currency,
        target: currency,
        date: asOf,
        amountMinor: item.performance.incomeMinor,
      );
      totalCost += costReporting?.minorUnits ?? 0;
      if (!incomplete &&
          item.reportingValueMinor != null &&
          costReporting != null) {
        totalUnrealized += item.reportingValueMinor! - costReporting.minorUnits;
      }
      totalRealized += realizedReporting?.minorUnits ?? 0;
      totalIncome += incomeReporting?.minorUnits ?? 0;
    }
    holdings.sort(
      (a, b) => (b.reportingMarketValueMinor ?? 0).compareTo(
        a.reportingMarketValueMinor ?? 0,
      ),
    );
    final Object syncStatus = reporting;
    final incompleteAccountSync = syncStatus is AccountSyncReadStatus
        ? await syncStatus.hasIncompleteAccounts(vaultId)
        : false;
    return PortfolioReport(
      currency: currency,
      holdings: holdings,
      marketValueMinor: totalMarket,
      costBasisMinor: totalCost,
      unrealizedMinor: totalUnrealized,
      realizedMinor: totalRealized,
      incomeMinor: totalIncome,
      hasIncompleteValuations: incompleteLotIds.isNotEmpty,
      hasIncompleteAccountSync: incompleteAccountSync,
      incompleteLotIds: incompleteLotIds,
    );
  }

  PositionValuation _marketValuation(
    LotPosition position,
    InvestmentPrice? price,
    int? amountMinor,
    LocalDate asOf,
    UtcInstant calculatedAt,
  ) {
    if (price == null) {
      return PositionValuation(
        amountMinor: null,
        currency: position.lot.costCurrency,
        valueDate: asOf,
        calculatedAt: calculatedAt,
        origin: ValuationOrigin.market,
        state: ValuationState.incomplete,
        source: 'market_price_missing',
        missingPeriods: const [],
      );
    }
    return PositionValuation(
      amountMinor: amountMinor,
      currency: price.currency,
      valueDate: price.date,
      calculatedAt: calculatedAt,
      origin: ValuationOrigin.market,
      state: ValuationState.current,
      source: price.manual ? 'user_market_price' : 'market_price_cache',
      missingPeriods: const [],
    );
  }

  Future<PositionValuation> _contractValuation({
    required EntityId vaultId,
    required LotPosition position,
    required FixedIncomeTerms terms,
    required LocalDate asOf,
    required UtcInstant calculatedAt,
  }) async {
    final manual = await repository.manualValues(vaultId, position.lot.id);
    final eligible =
        manual
            .where(
              (value) =>
                  value.removedAt == null &&
                  value.valueDate.compareTo(asOf) <= 0 &&
                  value.currency == terms.currency,
            )
            .toList()
          ..sort((a, b) {
            final dateOrder = b.valueDate.compareTo(a.valueDate);
            if (dateOrder != 0) return dateOrder;
            final byRecording = b.recordedAt.compareTo(a.recordedAt);
            return byRecording != 0
                ? byRecording
                : b.id.value.compareTo(a.id.value);
          });
    var manualValid = position.disposedQuantity == Decimal.zero;
    if (eligible.isNotEmpty) {
      final fingerprint = eligible.first.disposalFingerprint;
      manualValid = fingerprint == null
          ? position.disposedQuantity == Decimal.zero
          : fingerprint ==
                await repository.disposalFingerprint(
                  position.lot.id,
                  asOf: asOf,
                );
    }
    final range = _contractSeriesRange(terms, asOf);
    final observations =
        terms.indexCode == null ||
            economicSeries == null ||
            range.from.compareTo(range.through) > 0
        ? const <EconomicSeriesObservation>[]
        : (await economicSeries!.read(
            code: terms.indexCode!,
            from: range.from,
            through: range.through,
          )).observations;
    return fixedIncomeValuator.evaluate(
      position: position,
      terms: terms,
      asOf: asOf,
      calculatedAt: calculatedAt,
      observations: observations,
      manualValues: manual,
      manualValidAfterDisposal: manualValid,
      calendar: businessCalendar,
      currencyMinorUnits: await repository.currencyMinorUnits(terms.currency),
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

final class _HoldingDraft {
  const _HoldingDraft({
    required this.instrument,
    required this.lots,
    required this.performance,
    required this.price,
    required this.valuations,
    required this.instrumentValueMinor,
    required this.reportingValueMinor,
    required this.incompleteLotIds,
    required this.missingFx,
    required this.estimatedFx,
    required this.currencyMinorUnits,
  });

  final InvestmentInstrument instrument;
  final List<LotPosition> lots;
  final InvestmentPerformanceSource performance;
  final InvestmentPrice? price;
  final List<PositionValuation> valuations;
  final int? instrumentValueMinor;
  final int? reportingValueMinor;
  final List<EntityId> incompleteLotIds;
  final bool missingFx;
  final bool estimatedFx;
  final int currencyMinorUnits;
}

void _positive(Decimal value, String name) {
  if (value <= Decimal.zero) throw ArgumentError.value(value, name);
}

void _nonNegative(int value, String name) {
  if (value < 0) throw RangeError.value(value, name);
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
