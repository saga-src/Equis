import '../../domain/investments/investment_models.dart';
import '../../domain/investments/fixed_income_contract.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';
import '../../domain/shared/utc_instant.dart';

abstract interface class InvestmentRepository {
  Future<void> saveInstrument(InvestmentInstrument instrument);
  Future<bool> hasProtectedHistory(EntityId instrumentId);
  Future<InvestmentInstrument?> findInstrument(EntityId id);
  Future<List<InvestmentInstrument>> listInstruments(EntityId vaultId);
  Future<int> currencyMinorUnits(CurrencyCode currency);
  Future<void> saveBuy(
    LedgerTransaction transaction,
    InvestmentLot lot, {
    FixedIncomeContract? contract,
  });
  Future<FixedIncomeContract?> findContract(EntityId vaultId, EntityId lotId);
  Future<InvestmentLotEditorSnapshot?> loadLotEditor({
    required EntityId vaultId,
    required EntityId lotId,
    required LocalDate asOf,
  });
  Future<int> saveContract({
    required EntityId vaultId,
    required FixedIncomeContract contract,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  });
  Future<List<FixedIncomeManualValue>> manualValues(
    EntityId vaultId,
    EntityId lotId,
  );
  Future<String> disposalFingerprint(EntityId lotId, {required LocalDate asOf});
  Future<int> addManualValue({
    required EntityId vaultId,
    required FixedIncomeManualValue value,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  });
  Future<int> replaceManualValue({
    required EntityId vaultId,
    required EntityId oldValueId,
    required FixedIncomeManualValue newValue,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  });
  Future<int> removeManualValue({
    required EntityId vaultId,
    required EntityId lotId,
    required EntityId valueId,
    required int expectedTransactionRevision,
    required UtcInstant updatedAt,
    String? expectedDisposalFingerprint,
  });
  Future<void> saveSale(
    LedgerTransaction transaction,
    List<LotDisposal> disposals,
  );
  Future<void> saveLedgerTransaction(LedgerTransaction transaction);
  Future<List<LotPosition>> lotPositions(
    EntityId instrumentId, {
    required LocalDate asOf,
  });
  Future<InvestmentPerformanceSource> performance(
    EntityId instrumentId, {
    required LocalDate asOf,
  });
  Future<InvestmentPrice?> latestPrice(
    EntityId vaultId,
    EntityId instrumentId,
    CurrencyCode instrumentCurrency, {
    required LocalDate asOf,
  });
}

final class InvestmentLotEditorSnapshot {
  InvestmentLotEditorSnapshot({
    required this.lotId,
    required this.contract,
    required List<FixedIncomeManualValue> manualValues,
    required this.acquisitionTransactionRevision,
    required this.disposalFingerprint,
  }) : manualValues = List.unmodifiable(manualValues);

  final EntityId lotId;
  final FixedIncomeContract? contract;
  final List<FixedIncomeManualValue> manualValues;
  final int acquisitionTransactionRevision;

  /// Effective disposals across all dates when the editor was opened.
  final String disposalFingerprint;
}

final class InvestmentLotStateConflict implements Exception {
  const InvestmentLotStateConflict(this.lotId);
  final EntityId lotId;
}

final class InstrumentRevisionConflict implements Exception {
  const InstrumentRevisionConflict({
    required this.id,
    required this.expected,
    required this.actual,
  });
  final EntityId id;
  final int expected;
  final int? actual;
}

final class InsufficientLotQuantity implements Exception {
  const InsufficientLotQuantity(this.instrumentId);
  final EntityId instrumentId;
}

final class InvestmentCurrencyMismatch implements Exception {
  const InvestmentCurrencyMismatch({
    required this.expected,
    required this.actual,
  });
  final CurrencyCode expected;
  final CurrencyCode actual;
}

final class InvestmentAssetInUse implements Exception {
  const InvestmentAssetInUse(this.instrumentId);
  final EntityId instrumentId;
}
