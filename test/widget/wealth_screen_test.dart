import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/wealth/asset_models.dart';
import 'package:equis/domain/wealth/net_worth_models.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/wealth/wealth_controller.dart';
import 'package:equis/presentation/wealth/wealth_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders net worth, history, accounts, and physical assets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const instant = UtcInstant.fromEpochMicroseconds(1);
    final vaultId = EntityId.generate();
    final accountId = EntityId.generate();
    final finance = LocalFinanceSnapshot(
      vault: VaultProfile(
        id: vaultId,
        name: 'Local',
        baseCurrency: CurrencyCode.brl,
        locale: 'en-US',
        timezone: 'UTC',
        createdAt: instant,
        updatedAt: instant,
      ),
      accounts: [
        AccountAggregate(
          account: AccountProfile(
            id: accountId,
            vaultId: vaultId,
            name: 'Checking',
            type: AccountType.checking,
            nature: AccountNature.asset,
            createdAt: instant,
            updatedAt: instant,
          ),
          pockets: [
            AccountPocketProfile(
              id: EntityId.generate(),
              accountId: accountId,
              currency: CurrencyCode.brl,
              isDefault: true,
            ),
          ],
        ),
      ],
    );
    final asset = PhysicalAsset(
      id: EntityId.generate(),
      vaultId: vaultId,
      name: 'My car',
      type: PhysicalAssetType.vehicle,
      currency: CurrencyCode.brl,
      acquiredOn: LocalDate(2025, 1, 1),
      acquisitionCostMinor: 5000000,
      valuationMethod: AssetValuationMethod.straightLine,
      usefulLifeMonths: 60,
      createdAt: instant,
      updatedAt: instant,
    );
    final dates = [
      LocalDate(2026, 6, 30),
      LocalDate(2026, 7, 31),
      LocalDate(2026, 8, 18),
    ];
    final points = [
      NetWorthPoint(
        date: dates[0],
        assetsMinor: 6000000,
        liabilitiesMinor: 1000000,
        missingRates: const {},
        usesEstimatedRates: false,
      ),
      NetWorthPoint(
        date: dates[1],
        assetsMinor: 6200000,
        liabilitiesMinor: 900000,
        missingRates: const {},
        usesEstimatedRates: false,
      ),
      NetWorthPoint(
        date: dates[2],
        assetsMinor: 6500000,
        liabilitiesMinor: 800000,
        missingRates: const {},
        usesEstimatedRates: false,
      ),
    ];
    final report = NetWorthReport(
      currency: CurrencyCode.brl,
      current: points.last,
      history: points,
      physicalAssets: [
        AssetValue(
          asset: asset,
          valueMinor: 4500000,
          reportingMinor: 4500000,
          asOf: dates.last,
          source: AssetValuationSource.calculated,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: WealthScreen(
            financeOverride: finance,
            stateOverride: WealthState(report: report),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Net worth'), findsWidgets);
    expect(find.byKey(const Key('net-worth-total')), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('My car'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Add asset'), findsOneWidget);
  });
}
