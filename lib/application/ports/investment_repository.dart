import '../../domain/investments/investment_models.dart';
import '../../domain/ledger/ledger_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

abstract interface class InvestmentRepository {
  Future<void> saveInstrument(InvestmentInstrument instrument);
  Future<bool> hasProtectedHistory(EntityId instrumentId);
  Future<InvestmentInstrument?> findInstrument(EntityId id);
  Future<List<InvestmentInstrument>> listInstruments(EntityId vaultId);
  Future<int> currencyMinorUnits(CurrencyCode currency);
  Future<void> saveBuy(LedgerTransaction transaction, InvestmentLot lot);
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
