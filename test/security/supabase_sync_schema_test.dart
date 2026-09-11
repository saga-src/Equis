import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202608220001_phase18_sync_schema.sql',
    ).readAsStringSync().toLowerCase();
  });

  test('migration creates only the five locked cloud tables', () {
    final tables = RegExp(
      r'create table public\.([a-z_]+)',
    ).allMatches(sql).map((match) => match.group(1)).toSet();
    expect(tables, {
      'vaults',
      'vault_members',
      'devices',
      'sync_records',
      'vault_key_recovery',
    });
  });

  test('sync schema contains no plaintext financial columns', () {
    const forbidden = {
      'amount_minor',
      'balance',
      'merchant',
      'counterparty_name',
      'account_name',
      'category_name',
      'note',
      'budget_limit',
      'goal_target',
      'asset_value',
    };
    for (final column in forbidden) {
      expect(sql, isNot(contains(column)), reason: column);
    }
    expect(sql, contains('ciphertext bytea not null'));
    expect(sql, contains('nonce bytea not null'));
  });

  test('RLS, membership, pull index, and guarded RPC are present', () {
    for (final table in {
      'vaults',
      'vault_members',
      'devices',
      'sync_records',
      'vault_key_recovery',
    }) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
    }
    expect(sql, contains('create index idx_sync_records_pull'));
    expect(sql, contains('create or replace function public.is_vault_member'));
    expect(sql, contains('create or replace function public.apply_sync_batch'));
    expect(
      sql,
      contains('create or replace function public.acknowledge_sync_cursor'),
    );
    expect(sql, contains('last_acknowledged_server_version bigint'));
    expect(sql, contains('security definer'));
    expect(sql, contains("set search_path = ''"));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains("'idempotent_replay', true"));
    expect(sql, contains("'status', 'conflict'"));
    expect(sql, contains("nextval('public.sync_server_version_seq')"));
  });

  test('anonymous and direct sync writes are not granted', () {
    expect(sql, contains('revoke all on table public.sync_records'));
    expect(sql, isNot(contains('grant insert on public.sync_records')));
    expect(sql, isNot(contains('grant update on public.sync_records')));
    expect(sql, isNot(contains('grant delete on public.sync_records')));
    expect(sql, contains('grant execute on function public.apply_sync_batch'));
  });
}
