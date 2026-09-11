import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/financial_intelligence_service.dart';
import '../../domain/intelligence/financial_intelligence_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

final class FinancialIntelligenceState {
  const FinancialIntelligenceState({
    this.report,
    this.loading = false,
    this.error,
  });

  final FinancialIntelligenceReport? report;
  final bool loading;
  final Object? error;
}

final class FinancialIntelligenceController
    extends StateNotifier<FinancialIntelligenceState> {
  FinancialIntelligenceController({
    required FinancialIntelligenceService? service,
    required EntityId? vaultId,
    required CurrencyCode? currency,
  }) : this._(service, vaultId, currency);

  FinancialIntelligenceController._(
    this._service,
    this._vaultId,
    this._currency,
  ) : super(const FinancialIntelligenceState());

  final FinancialIntelligenceService? _service;
  final EntityId? _vaultId;
  final CurrencyCode? _currency;

  Future<void> reload() async {
    final service = _service;
    final vaultId = _vaultId;
    final currency = _currency;
    if (service == null || vaultId == null || currency == null) return;
    state = FinancialIntelligenceState(report: state.report, loading: true);
    try {
      final now = DateTime.now();
      final report = await service.load(
        vaultId: vaultId,
        currency: currency,
        asOf: LocalDate(now.year, now.month, now.day),
      );
      state = FinancialIntelligenceState(report: report);
    } catch (error) {
      state = FinancialIntelligenceState(report: state.report, error: error);
    }
  }
}
