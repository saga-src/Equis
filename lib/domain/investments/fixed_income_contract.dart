import 'package:decimal/decimal.dart';

import '../economic_series/economic_series_observation.dart';
import '../shared/currency.dart';
import '../shared/decimal_value.dart';
import '../shared/local_date.dart';
import '../shared/utc_instant.dart';
import '../shared/uuid_v7.dart';

enum FixedIncomeRemunerationMode {
  fixedAnnual,
  dailyIndexPercent,
  dailyIndexSpread,
  monthlyIndex,
  trValidity,
  manualOnly,
}

enum FixedIncomeUpdateRule {
  annualCompound,
  dailyObservation,
  monthlyAnniversary,
  validityInterval,
  manualValue,
}

/// Terms are independent of the acquisition's quantity and cost basis.
final class FixedIncomeTerms {
  FixedIncomeTerms({
    required Decimal principal,
    required this.currency,
    required this.productName,
    required this.accrualStart,
    required this.mode,
    required this.updateRule,
    this.issuerName,
    this.maturityOn,
    this.liquidityOn,
    this.indexCode,
    Decimal? indexMultiplier,
    Decimal? annualRate,
    Decimal? annualSpread,
    this.dayCountBasis,
    this.calendarVersion,
    this.publicationLagMonths = 0,
    this.anniversaryDay,
  }) : principal = _canonical(principal),
       indexMultiplier = _canonicalNullable(indexMultiplier),
       annualRate = _canonicalNullable(annualRate),
       annualSpread = _canonicalNullable(annualSpread) {
    if (this.principal <= Decimal.zero) {
      throw ArgumentError.value(principal, 'principal');
    }
    if (productName.trim().isEmpty) {
      throw ArgumentError.value(productName, 'productName');
    }
    if (maturityOn != null && maturityOn!.compareTo(accrualStart) < 0) {
      throw ArgumentError.value(maturityOn, 'maturityOn');
    }
    if (liquidityOn != null && liquidityOn!.compareTo(accrualStart) < 0) {
      throw ArgumentError.value(liquidityOn, 'liquidityOn');
    }
    if (publicationLagMonths < 0 || publicationLagMonths > 120) {
      throw RangeError.range(
        publicationLagMonths,
        0,
        120,
        'publicationLagMonths',
      );
    }
    if (anniversaryDay != null &&
        (anniversaryDay! < 1 || anniversaryDay! > 31)) {
      throw RangeError.range(anniversaryDay!, 1, 31, 'anniversaryDay');
    }
    if (dayCountBasis != null &&
        dayCountBasis != 252 &&
        dayCountBasis != 360 &&
        dayCountBasis != 365) {
      throw ArgumentError.value(dayCountBasis, 'dayCountBasis');
    }
    if (dayCountBasis == 252 &&
        (calendarVersion == null || calendarVersion!.trim().isEmpty)) {
      throw ArgumentError('A verified calendar is required for basis 252.');
    }
    if (this.annualRate != null && this.annualRate! <= -Decimal.one) {
      throw ArgumentError.value(annualRate, 'annualRate');
    }
    if (this.annualSpread != null && this.annualSpread! <= -Decimal.one) {
      throw ArgumentError.value(annualSpread, 'annualSpread');
    }
    if (this.indexMultiplier != null && this.indexMultiplier! < Decimal.zero) {
      throw ArgumentError.value(indexMultiplier, 'indexMultiplier');
    }
    switch (mode) {
      case FixedIncomeRemunerationMode.fixedAnnual:
        _require(
          updateRule == FixedIncomeUpdateRule.annualCompound &&
              this.annualRate != null &&
              dayCountBasis != null &&
              indexCode == null &&
              this.indexMultiplier == null &&
              this.annualSpread == null &&
              anniversaryDay == null,
        );
      case FixedIncomeRemunerationMode.dailyIndexPercent:
        _require(
          updateRule == FixedIncomeUpdateRule.dailyObservation &&
              _daily(indexCode) &&
              this.indexMultiplier != null &&
              this.annualRate == null &&
              this.annualSpread == null &&
              dayCountBasis == null &&
              anniversaryDay == null,
        );
      case FixedIncomeRemunerationMode.dailyIndexSpread:
        _require(
          updateRule == FixedIncomeUpdateRule.dailyObservation &&
              _daily(indexCode) &&
              this.annualSpread != null &&
              this.indexMultiplier == null &&
              this.annualRate == null &&
              dayCountBasis == 252 &&
              anniversaryDay == null,
        );
      case FixedIncomeRemunerationMode.monthlyIndex:
        _require(
          updateRule == FixedIncomeUpdateRule.monthlyAnniversary &&
              _monthly(indexCode) &&
              anniversaryDay != null &&
              this.annualRate == null &&
              this.indexMultiplier == null,
        );
      case FixedIncomeRemunerationMode.trValidity:
        _require(
          updateRule == FixedIncomeUpdateRule.validityInterval &&
              indexCode == EconomicSeriesCode.trPeriod &&
              this.indexMultiplier == null &&
              this.annualRate == null &&
              this.annualSpread == null &&
              anniversaryDay == null,
        );
      case FixedIncomeRemunerationMode.manualOnly:
        _require(
          updateRule == FixedIncomeUpdateRule.manualValue &&
              indexCode == null &&
              this.indexMultiplier == null &&
              this.annualRate == null &&
              this.annualSpread == null &&
              anniversaryDay == null,
        );
    }
  }

  final Decimal principal;
  final CurrencyCode currency;
  final String productName;
  final String? issuerName;
  final LocalDate accrualStart;
  final LocalDate? maturityOn;
  final LocalDate? liquidityOn;
  final FixedIncomeRemunerationMode mode;
  final EconomicSeriesCode? indexCode;
  final Decimal? indexMultiplier;
  final Decimal? annualRate;
  final Decimal? annualSpread;
  final int? dayCountBasis;
  final String? calendarVersion;
  final int publicationLagMonths;
  final int? anniversaryDay;
  final FixedIncomeUpdateRule updateRule;

  static bool _daily(EconomicSeriesCode? code) =>
      code == EconomicSeriesCode.cdiDaily ||
      code == EconomicSeriesCode.selicDaily;

  static bool _monthly(EconomicSeriesCode? code) =>
      code == EconomicSeriesCode.ipcaMonthly ||
      code == EconomicSeriesCode.inpcMonthly ||
      code == EconomicSeriesCode.igpmMonthly;

  static void _require(bool valid) {
    if (!valid) throw ArgumentError('Inconsistent fixed-income terms.');
  }
}

final class FixedIncomeContract {
  const FixedIncomeContract({required this.lotId, required this.terms});
  final EntityId lotId;
  final FixedIncomeTerms terms;
}

final class FixedIncomeManualValue {
  const FixedIncomeManualValue({
    required this.id,
    required this.lotId,
    required this.valueDate,
    required this.amountMinor,
    required this.currency,
    required this.recordedAt,
    this.notes,
    this.removedAt,
    this.disposalFingerprint,
  });

  final EntityId id;
  final EntityId lotId;
  final LocalDate valueDate;
  final int amountMinor;
  final CurrencyCode currency;
  final String? notes;
  final UtcInstant recordedAt;
  final UtcInstant? removedAt;

  /// Effective lot disposals at [valueDate], or null for an older value.
  final String? disposalFingerprint;
}

Decimal _canonical(Decimal value) =>
    DecimalValue.parse(DecimalValue.canonical(value));
Decimal? _canonicalNullable(Decimal? value) =>
    value == null ? null : _canonical(value);
