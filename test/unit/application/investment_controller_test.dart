import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:equis/application/ports/dashboard_repository.dart';
import 'package:equis/application/ports/investment_repository.dart';
import 'package:equis/application/ports/ledger_repository.dart';
import 'package:equis/application/services/investment_service.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/investments/fixed_income_contract.dart';
import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vaultId = EntityId.generate();
  final cash = LedgerPocket(
    id: EntityId.generate(),
    currency: CurrencyCode.brl,
    nature: AccountNature.asset,
  );
  FixedIncomeTerms terms(String rate) => FixedIncomeTerms(
    principal: Decimal.fromInt(1000),
    currency: CurrencyCode.brl,
    productName: 'LCI',
    accrualStart: LocalDate(2026, 1, 10),
    mode: FixedIncomeRemunerationMode.fixedAnnual,
    updateRule: FixedIncomeUpdateRule.annualCompound,
    annualRate: Decimal.parse(rate),
    dayCountBasis: 365,
  );

  test(
    'controller forwards distinct terms for initial and later lots',
    () async {
      final repository = _RecordingInvestmentRepository();
      final controller = InvestmentController(
        service: InvestmentService(
          repository: repository,
          reporting: _EmptyDashboardRepository(),
        ),
        market: null,
        vaultId: vaultId,
        reportingCurrency: CurrencyCode.brl,
      );
      addTearDown(controller.dispose);

      final first = terms('0.1208');
      await controller.createInstrument(
        name: 'LCI manual',
        symbol: '',
        exchange: '',
        assetClass: InvestmentAssetClass.fixedIncome,
        currency: CurrencyCode.brl,
        initialMode: InitialPositionMode.historicalBuy,
        initialPocket: cash,
        quantity: '1',
        unitPrice: '1000',
        date: LocalDate(2026, 1, 10),
        contractTerms: first,
      );
      expect(repository.savedContracts.single?.terms, same(first));
      final second = terms('0.15');
      await controller.trade(
        instrument: repository.savedInstrument!,
        pocket: cash,
        quantity: '1',
        unitPrice: '1000',
        fees: '',
        taxes: '',
        date: LocalDate(2026, 2, 10),
        sell: false,
        contractTerms: second,
      );
      expect(repository.savedContracts, hasLength(2));
      expect(repository.savedContracts.last?.terms, same(second));
    },
  );

  test(
    'controller converts manual amounts and exposes revision conflicts',
    () async {
      final repository = _RecordingInvestmentRepository();
      final controller = InvestmentController(
        service: InvestmentService(
          repository: repository,
          reporting: _EmptyDashboardRepository(),
        ),
        market: null,
        vaultId: vaultId,
        reportingCurrency: CurrencyCode.brl,
      );
      addTearDown(controller.dispose);
      final lotId = EntityId.generate();
      await controller.recordManualValue(
        lotId: lotId,
        valueDate: LocalDate(2026, 2, 10),
        amount: '1234,56',
        currency: CurrencyCode.brl,
        expectedRevision: 7,
      );
      expect(repository.savedManual?.amountMinor, 123456);
      expect(repository.expectedRevision, 7);
      repository.failManual = true;
      await expectLater(
        controller.recordManualValue(
          lotId: lotId,
          valueDate: LocalDate(2026, 2, 10),
          amount: '1234,56',
          currency: CurrencyCode.brl,
          expectedRevision: 7,
        ),
        throwsA(isA<LedgerRevisionConflict>()),
      );
      expect(controller.state.error, isA<LedgerRevisionConflict>());
    },
  );

  test(
    'busy investment mutation reports an error instead of succeeding',
    () async {
      final repository = _RecordingInvestmentRepository();
      final pendingSave = Completer<void>();
      repository.pendingSave = pendingSave.future;
      final controller = InvestmentController(
        service: InvestmentService(
          repository: repository,
          reporting: _EmptyDashboardRepository(),
        ),
        market: null,
        vaultId: vaultId,
        reportingCurrency: CurrencyCode.brl,
      );
      addTearDown(controller.dispose);
      final first = controller.createInstrument(
        name: 'First',
        symbol: '',
        exchange: '',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.brl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.loading, isTrue);
      await expectLater(
        controller.createInstrument(
          name: 'Second',
          symbol: '',
          exchange: '',
          assetClass: InvestmentAssetClass.stock,
          currency: CurrencyCode.brl,
        ),
        throwsStateError,
      );
      pendingSave.complete();
      await first;
    },
  );

  test(
    'mutation failures remain in state and are rethrown to the UI',
    () async {
      final controller = InvestmentController(
        service: null,
        market: null,
        vaultId: EntityId.generate(),
        reportingCurrency: CurrencyCode.brl,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.createInstrument(
          name: 'Acme',
          symbol: 'ACME3',
          exchange: 'B3',
          assetClass: InvestmentAssetClass.stock,
          currency: CurrencyCode.brl,
        ),
        throwsA(isA<StateError>()),
      );

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isA<StateError>());
    },
  );
}

class _RecordingInvestmentRepository implements InvestmentRepository {
  InvestmentInstrument? savedInstrument;
  final savedContracts = <FixedIncomeContract?>[];
  FixedIncomeManualValue? savedManual;
  int? expectedRevision;
  bool failManual = false;
  Future<void>? pendingSave;

  @override
  Future<void> saveInstrument(InvestmentInstrument instrument) async {
    savedInstrument = instrument;
    await pendingSave;
  }

  @override
  Future<void> saveBuy(
    LedgerTransaction transaction,
    InvestmentLot lot, {
    FixedIncomeContract? contract,
  }) async {
    savedContracts.add(contract);
  }

  @override
  Future<int> addManualValue({
    required EntityId vaultId,
    required FixedIncomeManualValue value,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  }) async {
    if (failManual) {
      throw LedgerRevisionConflict(
        transactionId: EntityId.generate(),
        expectedRevision: expectedTransactionRevision,
        actualRevision: expectedTransactionRevision + 1,
      );
    }
    savedManual = value;
    expectedRevision = expectedTransactionRevision;
    return expectedTransactionRevision + 1;
  }

  @override
  Future<int> currencyMinorUnits(CurrencyCode currency) async => 2;

  @override
  Future<List<InvestmentInstrument>> listInstruments(EntityId vaultId) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyDashboardRepository implements DashboardRepository {
  @override
  void beginRead() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
