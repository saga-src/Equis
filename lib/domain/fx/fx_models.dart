import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum FxRateSource {
  transactionManual('transaction_manual'),
  datePairManual('date_pair_manual'),
  automaticExact('automatic_exact'),
  previousMarketDay('previous_market_day'),
  latestCached('latest_cached'),
  identity;

  const FxRateSource([String? storageValue])
    : storageValue = storageValue ?? '';
  final String storageValue;
  String get stored => storageValue.isEmpty ? name : storageValue;
}

final class FxRateQuote {
  FxRateQuote({
    required this.base,
    required this.quote,
    required this.requestedDate,
    required this.rateDate,
    required String rate,
    required this.source,
    required this.provider,
  }) : rate = DecimalValue.canonical(DecimalValue.parse(rate)) {
    if (base == quote && this.rate != '1') {
      throw ArgumentError('Identity currency rate must be one.');
    }
    if (DecimalValue.parse(this.rate).sign <= 0) {
      throw ArgumentError.value(rate, 'rate', 'must be positive');
    }
  }

  final CurrencyCode base;
  final CurrencyCode quote;
  final LocalDate requestedDate;
  final LocalDate rateDate;
  final String rate;
  final FxRateSource source;
  final String provider;

  bool get isEstimated =>
      source == FxRateSource.previousMarketDay ||
      source == FxRateSource.latestCached ||
      rateDate != requestedDate;
}

final class ManualFxRate {
  ManualFxRate({
    required this.id,
    required this.vaultId,
    required this.base,
    required this.quote,
    required this.date,
    required String rate,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.deletedAt,
    this.revision = 1,
  }) : rate = DecimalValue.canonical(DecimalValue.parse(rate)) {
    if (base == quote) {
      throw ArgumentError('Manual FX pair currencies must differ.');
    }
    if (DecimalValue.parse(this.rate).sign <= 0) {
      throw ArgumentError.value(rate, 'rate', 'must be positive');
    }
  }

  final EntityId id;
  final EntityId vaultId;
  final CurrencyCode base;
  final CurrencyCode quote;
  final LocalDate date;
  final String rate;
  final String? notes;
  final int revision;
  final UtcInstant createdAt;
  final UtcInstant updatedAt;
  final UtcInstant? deletedAt;
}
