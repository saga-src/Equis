import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  late String publicFunction;
  late String syncFunction;
  late String edgeConfig;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260922164311_central_asset_catalog.sql',
    ).readAsStringSync().toLowerCase();
    publicFunction = File(
      'supabase/functions/market-quotes/index.ts',
    ).readAsStringSync();
    syncFunction = File(
      'supabase/functions/sync-market-data/index.ts',
    ).readAsStringSync();
    edgeConfig = File('supabase/config.toml').readAsStringSync();
  });

  test('migration creates only asset-named central market tables', () {
    final tables = RegExp(
      r'create table public\.([a-z_]+)',
    ).allMatches(sql).map((match) => match.group(1)).toSet();
    expect(tables, {
      'market_provider_settings',
      'market_sync_runs',
      'market_assets',
      'market_asset_sources',
      'market_asset_quotes_latest',
      'market_asset_quotes_daily',
      'market_asset_refresh_targets',
    });
    expect(sql, isNot(contains('market_instrument')));
    expect(sql, isNot(contains('instrument_id')));
  });

  test('catalog is RLS protected and grants service role only', () {
    for (final table in {
      'market_provider_settings',
      'market_sync_runs',
      'market_assets',
      'market_asset_sources',
      'market_asset_quotes_latest',
      'market_asset_quotes_daily',
      'market_asset_refresh_targets',
    }) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(sql, contains('revoke all on table public.$table'));
    }
    expect(sql, contains('to service_role'));
    expect(
      sql,
      isNot(contains('grant select on public.market_assets to anon')),
    );
    expect(
      sql,
      isNot(contains('grant select on public.market_assets to authenticated')),
    );
    expect(sql, contains('security invoker'));
  });

  test('leases, expiry, retention, and cron jobs are explicit', () {
    expect(sql, contains('for update of t skip locked'));
    expect(sql, contains("now() - interval '30 days'"));
    expect(sql, contains("current_date - interval '5 years'"));
    expect(sql, contains("'30 4 * * *'"));
    expect(sql, contains("'15 * * * *'"));
    expect(sql, contains('market_sync_secret'));
  });

  test('central schema contains no portfolio or personal association', () {
    for (final forbidden in {
      'user_id',
      'vault_id',
      'quantity',
      'cost_basis',
      'balance',
      'transaction_id',
      'holding_id',
    }) {
      expect(sql, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('edge contracts include search quote heartbeat and sync secret', () {
    expect(publicFunction, contains('"search"'));
    expect(publicFunction, contains('"quote"'));
    expect(publicFunction, contains('"heartbeat"'));
    expect(publicFunction, contains('assetId'));
    expect(publicFunction, contains('providerSymbol'));
    expect(syncFunction, contains('x-equis-sync-secret'));
    expect(syncFunction, contains('scheduledQuotesEnabled'));
    expect(
      edgeConfig,
      contains('[functions.market-quotes]\nverify_jwt = true'),
    );
    expect(
      edgeConfig,
      contains('[functions.sync-market-data]\nverify_jwt = false'),
    );
  });
}
