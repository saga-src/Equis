import 'package:drift/native.dart';
import 'package:equis/application/ports/fx_rate_ports.dart';
import 'package:equis/application/services/fx_rate_selector.dart';
import 'package:equis/domain/entities/vault_profile.dart';
import 'package:equis/domain/fx/fx_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/persistence/database/equis_database.dart'
    hide ManualFxRate;
import 'package:equis/infrastructure/repositories/drift_foundational_repositories.dart';
import 'package:equis/infrastructure/repositories/drift_fx_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const now = UtcInstant.fromEpochMicroseconds(1786636800123456);
  final date = LocalDate.parse('2026-08-13');

  test(
    'selection priority is transaction manual then date/pair manual',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final vault = await _vault(database, now);
      final manualRepository = DriftManualFxRateRepository(database);
      await manualRepository.save(
        ManualFxRate(
          id: EntityId.generate(),
          vaultId: vault.id,
          base: CurrencyCode.usd,
          quote: CurrencyCode.brl,
          date: date,
          rate: '5.40',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final provider = _FakeProvider(null);
      final selector = FxRateSelector(
        manualRates: manualRepository,
        cache: DriftFxRateCacheRepository(database, clock: () => now),
        provider: provider,
      );
      final transactionManual = await selector.select(
        vaultId: vault.id,
        base: CurrencyCode.usd,
        quote: CurrencyCode.brl,
        date: date,
        transactionManualRate: '5.55',
      );
      expect(transactionManual?.source, FxRateSource.transactionManual);
      expect(transactionManual?.rate, '5.55');
      expect(provider.calls, 0);

      final dateManual = await selector.select(
        vaultId: vault.id,
        base: CurrencyCode.usd,
        quote: CurrencyCode.brl,
        date: date,
      );
      expect(dateManual?.source, FxRateSource.datePairManual);
      expect(dateManual?.rate, '5.4');
      expect(dateManual?.isEstimated, isFalse);
      expect(provider.calls, 0);
    },
  );

  test('automatic exact rate is cached and available offline', () async {
    final database = EquisDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final vault = await _vault(database, now);
    final remote = FxRateQuote(
      base: CurrencyCode.usd,
      quote: CurrencyCode.brl,
      requestedDate: date,
      rateDate: date,
      rate: '5.43728193',
      source: FxRateSource.automaticExact,
      provider: 'frankfurter_v2',
    );
    final cache = DriftFxRateCacheRepository(database, clock: () => now);
    final online = FxRateSelector(
      manualRates: DriftManualFxRateRepository(database),
      cache: cache,
      provider: _FakeProvider(remote),
    );
    expect(
      (await online.select(
        vaultId: vault.id,
        base: CurrencyCode.usd,
        quote: CurrencyCode.brl,
        date: date,
      ))?.rate,
      '5.43728193',
    );

    final offline = FxRateSelector(
      manualRates: DriftManualFxRateRepository(database),
      cache: cache,
      provider: _ThrowingProvider(),
    );
    final cached = await offline.select(
      vaultId: vault.id,
      base: CurrencyCode.usd,
      quote: CurrencyCode.brl,
      date: date,
    );
    expect(cached?.source, FxRateSource.automaticExact);
    expect(cached?.isEstimated, isFalse);
  });

  test(
    'offline fallback prefers previous market day before latest cache',
    () async {
      final database = EquisDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final vault = await _vault(database, now);
      final cache = DriftFxRateCacheRepository(database, clock: () => now);
      await cache.save(
        FxRateQuote(
          base: CurrencyCode.usd,
          quote: CurrencyCode.brl,
          requestedDate: LocalDate.parse('2026-08-12'),
          rateDate: LocalDate.parse('2026-08-12'),
          rate: '5.41',
          source: FxRateSource.automaticExact,
          provider: 'frankfurter_v2',
        ),
      );
      final selector = FxRateSelector(
        manualRates: DriftManualFxRateRepository(database),
        cache: cache,
        provider: _ThrowingProvider(),
      );
      final selected = await selector.select(
        vaultId: vault.id,
        base: CurrencyCode.usd,
        quote: CurrencyCode.brl,
        date: date,
      );
      expect(selected?.source, FxRateSource.previousMarketDay);
      expect(selected?.rateDate, LocalDate.parse('2026-08-12'));
      expect(selected?.isEstimated, isTrue);

      final beforeAllCache = await selector.select(
        vaultId: vault.id,
        base: CurrencyCode.usd,
        quote: CurrencyCode.brl,
        date: LocalDate.parse('2020-01-01'),
      );
      expect(beforeAllCache?.source, FxRateSource.latestCached);
      expect(beforeAllCache?.isEstimated, isTrue);
    },
  );
}

Future<VaultProfile> _vault(EquisDatabase database, UtcInstant now) async {
  final vault = VaultProfile(
    id: EntityId.generate(),
    name: 'Vault',
    baseCurrency: CurrencyCode.brl,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    createdAt: now,
    updatedAt: now,
  );
  await DriftVaultRepository(database).save(vault);
  return vault;
}

final class _FakeProvider implements FxRateProvider {
  _FakeProvider(this.result);
  final FxRateQuote? result;
  int calls = 0;

  @override
  Future<FxRateQuote?> quote({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) async {
    calls++;
    return result;
  }
}

final class _ThrowingProvider implements FxRateProvider {
  @override
  Future<FxRateQuote?> quote({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) => throw Exception('offline');
}
