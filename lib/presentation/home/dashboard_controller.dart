import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/services/dashboard_service.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

final class DashboardState {
  const DashboardState({this.snapshot, this.loading = false, this.error});

  final DashboardSnapshot? snapshot;
  final bool loading;
  final Object? error;
}

final class DashboardController extends StateNotifier<DashboardState> {
  DashboardController({
    required DashboardService? service,
    required EntityId? vaultId,
    required CurrencyCode? reportingCurrency,
  }) : this._(service, vaultId, reportingCurrency);

  DashboardController._(this._service, this._vaultId, this._reportingCurrency)
    : super(const DashboardState());

  final DashboardService? _service;
  final EntityId? _vaultId;
  final CurrencyCode? _reportingCurrency;

  Future<void> reload() async {
    final service = _service;
    final vaultId = _vaultId;
    final currency = _reportingCurrency;
    if (service == null || vaultId == null || currency == null) return;
    state = DashboardState(snapshot: state.snapshot, loading: true);
    try {
      state = DashboardState(
        snapshot: await service.load(
          vaultId: vaultId,
          reportingCurrency: currency,
          asOf: _today(),
        ),
      );
    } catch (error) {
      state = DashboardState(snapshot: state.snapshot, error: error);
    }
  }
}

LocalDate _today() {
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}
