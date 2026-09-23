import '../../domain/shared/currency.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';
import '../ports/startup_refresh_gate.dart';
import 'fx_rate_selector.dart';
import 'local_finance_session_service.dart';
import 'market_data_service.dart';

final class StartupRefreshResult {
  const StartupRefreshResult({
    required this.attempted,
    this.marketFailed = false,
    this.fxFailures = 0,
  });

  final bool attempted;
  final bool marketFailed;
  final int fxFailures;
  bool get partialFailure => marketFailed || fxFailures > 0;
}

final class StartupRefreshService {
  const StartupRefreshService({
    required this.session,
    required this.marketData,
    required this.fxRates,
    required this.gate,
    this.minimumInterval = const Duration(hours: 3),
  });

  final LocalFinanceSessionService session;
  final MarketDataService marketData;
  final FxRateSelector fxRates;
  final StartupRefreshGate gate;
  final Duration minimumInterval;

  Future<StartupRefreshResult> refreshOnOpen(UtcInstant now) async {
    final snapshot = await session.load();
    final vault = snapshot.vault;
    if (vault == null) {
      return const StartupRefreshResult(attempted: false);
    }
    final previous = await gate.lastAttempt(vault.id);
    if (previous != null &&
        now.epochMicroseconds - previous.epochMicroseconds <
            minimumInterval.inMicroseconds) {
      return const StartupRefreshResult(attempted: false);
    }

    final dateTime = now.toDateTime();
    final today = LocalDate(dateTime.year, dateTime.month, dateTime.day);
    var marketFailed = false;
    var fxFailures = 0;
    try {
      final states = await marketData.load(
        vaultId: vault.id,
        asOf: today,
        now: now,
        refresh: true,
        purpose: MarketQuotePurpose.portfolio,
      );
      marketFailed = states.any((state) => state.refreshFailed);
    } on Exception {
      marketFailed = true;
    }

    final currencies = <CurrencyCode>{
      for (final account in snapshot.accounts)
        for (final pocket in account.pockets) pocket.currency,
    }..remove(vault.baseCurrency);
    for (final currency in currencies) {
      try {
        final selected = await fxRates.select(
          vaultId: vault.id,
          base: vault.baseCurrency,
          quote: currency,
          date: today,
          refresh: true,
        );
        if (selected == null) fxFailures++;
      } on Exception {
        fxFailures++;
      }
    }
    await gate.recordAttempt(vault.id, now);
    return StartupRefreshResult(
      attempted: true,
      marketFailed: marketFailed,
      fxFailures: fxFailures,
    );
  }
}
