-- Equis 1.1.0: private central market-asset catalog and tracked quotes.

create extension if not exists pg_trgm with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

create schema if not exists equis_private;
revoke all on schema equis_private from public, anon, authenticated;

create table public.market_provider_settings (
  provider text primary key check (provider in ('brapi', 'twelve_data', 'coin_gecko')),
  daily_credit_limit integer not null check (daily_credit_limit > 0),
  scheduled_credit_reserve integer not null default 0
    check (scheduled_credit_reserve >= 0),
  interactive_credit_reserve integer not null default 0
    check (interactive_credit_reserve >= 0),
  usage_date date not null default current_date,
  scheduled_credits_used integer not null default 0
    check (scheduled_credits_used >= 0),
  interactive_credits_used integer not null default 0
    check (interactive_credits_used >= 0),
  catalog_enabled boolean not null default false,
  persistence_allowed boolean not null default false,
  redistribution_allowed boolean not null default false,
  catalog_cursor jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  check (scheduled_credit_reserve + interactive_credit_reserve <= daily_credit_limit)
);

insert into public.market_provider_settings (
  provider,
  daily_credit_limit,
  scheduled_credit_reserve,
  interactive_credit_reserve
) values
  ('brapi', 1000, 800, 200),
  ('twelve_data', 800, 600, 200),
  ('coin_gecko', 1000, 800, 200)
on conflict (provider) do nothing;

create table public.market_sync_runs (
  id bigint generated always as identity primary key,
  provider text not null check (provider in ('brapi', 'twelve_data', 'coin_gecko', 'system')),
  operation text not null check (
    operation in ('catalog', 'ranking', 'quotes', 'cleanup', 'on_demand')
  ),
  status text not null default 'running'
    check (status in ('running', 'completed', 'partial', 'failed', 'disabled')),
  cursor jsonb not null default '{}'::jsonb,
  counters jsonb not null default '{}'::jsonb,
  error_code text,
  rate_limit_remaining integer,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create index market_sync_runs_provider_started_idx
  on public.market_sync_runs (provider, started_at desc);

create table public.market_assets (
  id bigint generated always as identity primary key,
  canonical_key text not null unique
    check (char_length(canonical_key) between 1 and 512),
  symbol text not null check (char_length(symbol) between 1 and 80),
  name text not null check (char_length(name) between 1 and 300),
  asset_class text not null check (
    asset_class in (
      'stock', 'etf', 'fund', 'reit', 'fii', 'bond', 'fixed_income',
      'crypto', 'commodity', 'cash_equivalent', 'other'
    )
  ),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  exchange text not null default '',
  mic_code text,
  country text,
  isin text check (isin is null or isin ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'),
  is_active boolean not null default true,
  relevance_score numeric(18, 8) not null default 0,
  demand_count bigint not null default 0 check (demand_count >= 0),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index market_assets_symbol_upper_idx
  on public.market_assets (upper(symbol));
create index market_assets_active_class_currency_idx
  on public.market_assets (asset_class, currency, relevance_score desc)
  where is_active;
create index market_assets_symbol_trgm_idx
  on public.market_assets using gin (symbol extensions.gin_trgm_ops);
create index market_assets_name_trgm_idx
  on public.market_assets using gin (name extensions.gin_trgm_ops);

create table public.market_asset_sources (
  id bigint generated always as identity primary key,
  asset_id bigint not null references public.market_assets(id) on delete cascade,
  provider text not null check (provider in ('brapi', 'twelve_data', 'coin_gecko')),
  provider_symbol text not null check (char_length(provider_symbol) between 1 and 160),
  external_identifiers jsonb not null default '{}'::jsonb,
  exchange text not null default '',
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  source_rank integer check (source_rank is null or source_rank > 0),
  is_active boolean not null default true,
  missing_sync_count smallint not null default 0
    check (missing_sync_count between 0 and 3),
  last_seen_run_id bigint references public.market_sync_runs(id) on delete set null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_symbol, exchange, currency)
);

create index market_asset_sources_asset_id_idx
  on public.market_asset_sources (asset_id);
create index market_asset_sources_active_provider_idx
  on public.market_asset_sources (provider, source_rank, asset_id)
  where is_active;

create table public.market_asset_quotes_latest (
  asset_id bigint primary key references public.market_assets(id) on delete cascade,
  price numeric(38, 18) not null check (price > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  quoted_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  provider text not null check (provider in ('brapi', 'twelve_data', 'coin_gecko')),
  is_stale boolean not null default false,
  error_code text
);

create index market_asset_quotes_latest_fetched_idx
  on public.market_asset_quotes_latest (fetched_at desc);

create table public.market_asset_quotes_daily (
  asset_id bigint not null references public.market_assets(id) on delete cascade,
  quote_date date not null,
  close_price numeric(38, 18) not null check (close_price > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  quoted_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  provider text not null check (provider in ('brapi', 'twelve_data', 'coin_gecko')),
  primary key (asset_id, quote_date)
);

create index market_asset_quotes_daily_retention_idx
  on public.market_asset_quotes_daily (quote_date);

create table public.market_asset_refresh_targets (
  asset_id bigint primary key references public.market_assets(id) on delete cascade,
  last_seen_at timestamptz not null,
  last_activity text not null
    check (last_activity in ('portfolio', 'preview', 'manual_refresh')),
  priority smallint not null default 10 check (priority between 1 and 100),
  next_refresh_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  failure_count integer not null default 0 check (failure_count >= 0),
  last_error_code text,
  updated_at timestamptz not null default now()
);

create index market_asset_refresh_targets_due_idx
  on public.market_asset_refresh_targets (
    priority desc, next_refresh_at, lease_until, last_seen_at desc
  );

alter table public.market_provider_settings enable row level security;
alter table public.market_sync_runs enable row level security;
alter table public.market_assets enable row level security;
alter table public.market_asset_sources enable row level security;
alter table public.market_asset_quotes_latest enable row level security;
alter table public.market_asset_quotes_daily enable row level security;
alter table public.market_asset_refresh_targets enable row level security;

revoke all on table public.market_provider_settings from public, anon, authenticated;
revoke all on table public.market_sync_runs from public, anon, authenticated;
revoke all on table public.market_assets from public, anon, authenticated;
revoke all on table public.market_asset_sources from public, anon, authenticated;
revoke all on table public.market_asset_quotes_latest from public, anon, authenticated;
revoke all on table public.market_asset_quotes_daily from public, anon, authenticated;
revoke all on table public.market_asset_refresh_targets from public, anon, authenticated;
revoke all on sequence
  public.market_sync_runs_id_seq,
  public.market_assets_id_seq,
  public.market_asset_sources_id_seq
from anon, authenticated;

grant select, insert, update, delete on table
  public.market_provider_settings,
  public.market_sync_runs,
  public.market_assets,
  public.market_asset_sources,
  public.market_asset_quotes_latest,
  public.market_asset_quotes_daily,
  public.market_asset_refresh_targets
to service_role;
grant usage, select on sequence
  public.market_sync_runs_id_seq,
  public.market_assets_id_seq,
  public.market_asset_sources_id_seq
to service_role;

create or replace function public.search_market_assets(
  p_query text,
  p_asset_class text default null,
  p_currency text default null,
  p_limit integer default 10
)
returns table (
  asset_id text,
  symbol text,
  name text,
  asset_class text,
  currency text,
  exchange text,
  provider text,
  provider_symbol text,
  relevance_score numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    a.id::text,
    a.symbol,
    a.name,
    a.asset_class,
    a.currency,
    nullif(coalesce(s.exchange, a.exchange), ''),
    s.provider,
    s.provider_symbol,
    a.relevance_score
  from public.market_assets a
  join lateral (
    select src.provider, src.provider_symbol, src.exchange
    from public.market_asset_sources src
    where src.asset_id = a.id and src.is_active
    order by
      case src.provider
        when 'brapi' then 1
        when 'twelve_data' then 2
        else 3
      end,
      src.source_rank nulls last,
      src.id
    limit 1
  ) s on true
  where a.is_active
    and (p_asset_class is null or a.asset_class = p_asset_class)
    and (p_currency is null or a.currency = upper(p_currency))
    and (
      upper(a.symbol) = upper(trim(p_query))
      or upper(a.symbol) like upper(trim(p_query)) || '%'
      or a.name ilike trim(p_query) || '%'
      or extensions.similarity(a.symbol, trim(p_query)) >= 0.2
      or extensions.similarity(a.name, trim(p_query)) >= 0.2
    )
  order by
    case
      when upper(a.symbol) = upper(trim(p_query)) then 0
      when upper(a.symbol) like upper(trim(p_query)) || '%' then 1
      when lower(a.name) = lower(trim(p_query)) then 2
      when a.name ilike trim(p_query) || '%' then 3
      else 4
    end,
    greatest(
      extensions.similarity(a.symbol, trim(p_query)),
      extensions.similarity(a.name, trim(p_query))
    ) desc,
    a.relevance_score desc,
    a.demand_count desc,
    a.symbol,
    a.id
  limit least(greatest(p_limit, 1), 10);
$$;

create or replace function public.renew_market_asset_targets(
  p_assets jsonb,
  p_activity text
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer;
  v_priority smallint;
begin
  if p_assets is null
     or jsonb_typeof(p_assets) <> 'array'
     or jsonb_array_length(p_assets) not between 1 and 200
     or p_activity not in ('portfolio', 'preview', 'manual_refresh') then
    raise exception using errcode = '22023', message = 'invalid_market_heartbeat';
  end if;

  v_priority := case p_activity
    when 'portfolio' then 100
    when 'manual_refresh' then 80
    else 40
  end;

  with requested as (
    select distinct
      case lower(item ->> 'provider')
        when 'twelvedata' then 'twelve_data'
        when 'coingecko' then 'coin_gecko'
        else lower(item ->> 'provider')
      end as provider,
      case
        when lower(item ->> 'provider') = 'coingecko'
          then lower(trim(item ->> 'provider_symbol'))
        else upper(trim(item ->> 'provider_symbol'))
      end as provider_symbol,
      upper(coalesce(item ->> 'exchange', '')) as exchange,
      upper(coalesce(item ->> 'currency', '')) as currency
    from jsonb_array_elements(p_assets) item
    where char_length(trim(coalesce(item ->> 'provider_symbol', ''))) between 1 and 160
  ), resolved as (
    select distinct s.asset_id
    from requested r
    join public.market_asset_sources s
     on s.provider = r.provider
     and s.provider_symbol = r.provider_symbol
     and (r.exchange = '' or s.exchange = r.exchange)
     and s.currency = r.currency
  ), renewed as (
    insert into public.market_asset_refresh_targets (
      asset_id, last_seen_at, last_activity, priority, next_refresh_at, updated_at
    )
    select asset_id, now(), p_activity, v_priority, now(), now()
    from resolved
    on conflict (asset_id) do update set
      last_seen_at = excluded.last_seen_at,
      last_activity = excluded.last_activity,
      priority = greatest(public.market_asset_refresh_targets.priority, excluded.priority),
      next_refresh_at = least(public.market_asset_refresh_targets.next_refresh_at, now()),
      updated_at = now()
    returning asset_id
  )
  select count(*) into v_count from renewed;

  with requested as (
    select distinct
      case lower(item ->> 'provider')
        when 'twelvedata' then 'twelve_data'
        when 'coingecko' then 'coin_gecko'
        else lower(item ->> 'provider')
      end as provider,
      case
        when lower(item ->> 'provider') = 'coingecko'
          then lower(trim(item ->> 'provider_symbol'))
        else upper(trim(item ->> 'provider_symbol'))
      end as provider_symbol,
      upper(coalesce(item ->> 'exchange', '')) as exchange,
      upper(coalesce(item ->> 'currency', '')) as currency
    from jsonb_array_elements(p_assets) item
  ), resolved as (
    select distinct s.asset_id
    from requested r
    join public.market_asset_sources s
     on s.provider = r.provider
     and s.provider_symbol = r.provider_symbol
     and (r.exchange = '' or s.exchange = r.exchange)
     and s.currency = r.currency
  )
  update public.market_assets a
  set demand_count = demand_count + 1,
      updated_at = now()
  where a.id in (select asset_id from resolved);

  return v_count;
end;
$$;

create or replace function public.reserve_market_provider_credits(
  p_provider text,
  p_usage text,
  p_credits integer default 1
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_settings public.market_provider_settings%rowtype;
  v_allowed boolean;
begin
  if p_provider not in ('brapi', 'twelve_data', 'coin_gecko')
     or p_usage not in ('scheduled', 'interactive')
     or p_credits not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'invalid_market_credit_request';
  end if;

  select * into v_settings
  from public.market_provider_settings
  where provider = p_provider
  for update;

  if v_settings.usage_date <> current_date then
    update public.market_provider_settings
    set usage_date = current_date,
        scheduled_credits_used = 0,
        interactive_credits_used = 0,
        updated_at = now()
    where provider = p_provider
    returning * into v_settings;
  end if;

  if p_usage = 'scheduled' then
    v_allowed := v_settings.scheduled_credits_used + p_credits <=
      v_settings.scheduled_credit_reserve;
    if v_allowed then
      update public.market_provider_settings
      set scheduled_credits_used = scheduled_credits_used + p_credits,
          updated_at = now()
      where provider = p_provider;
    end if;
  else
    v_allowed := v_settings.interactive_credits_used + p_credits <=
      v_settings.interactive_credit_reserve;
    if v_allowed then
      update public.market_provider_settings
      set interactive_credits_used = interactive_credits_used + p_credits,
          updated_at = now()
      where provider = p_provider;
    end if;
  end if;

  return v_allowed;
end;
$$;

create or replace function public.claim_market_refresh_targets(
  p_limit integer default 100,
  p_lease_seconds integer default 300
)
returns table (
  asset_id text,
  symbol text,
  asset_class text,
  currency text,
  exchange text,
  provider text,
  provider_symbol text,
  lease_token uuid
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_limit not between 1 and 500 or p_lease_seconds not between 30 and 1800 then
    raise exception using errcode = '22023', message = 'invalid_market_lease';
  end if;

  return query
  with due as (
    select t.asset_id
    from public.market_asset_refresh_targets t
    join public.market_assets a on a.id = t.asset_id and a.is_active
    where t.last_seen_at >= now() - interval '30 days'
      and t.next_refresh_at <= now()
      and (t.lease_until is null or t.lease_until < now())
    order by t.priority desc, t.next_refresh_at, t.last_seen_at desc
    limit p_limit
    for update of t skip locked
  ), claimed as (
    update public.market_asset_refresh_targets t
    set lease_token = gen_random_uuid(),
        lease_until = now() + make_interval(secs => p_lease_seconds),
        updated_at = now()
    from due
    where t.asset_id = due.asset_id
    returning t.asset_id, t.lease_token
  )
  select
    a.id::text,
    a.symbol,
    a.asset_class,
    a.currency,
    s.exchange,
    s.provider,
    s.provider_symbol,
    c.lease_token
  from claimed c
  join public.market_assets a on a.id = c.asset_id
  join lateral (
    select src.provider, src.provider_symbol, src.exchange
    from public.market_asset_sources src
    where src.asset_id = a.id and src.is_active
    order by src.source_rank nulls last, src.id
    limit 1
  ) s on true;
end;
$$;

create or replace function public.complete_market_refresh(
  p_asset_id bigint,
  p_lease_token uuid,
  p_success boolean,
  p_next_refresh_at timestamptz,
  p_error_code text default null
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_updated integer;
begin
  update public.market_asset_refresh_targets
  set next_refresh_at = p_next_refresh_at,
      lease_token = null,
      lease_until = null,
      failure_count = case when p_success then 0 else failure_count + 1 end,
      last_error_code = case when p_success then null else p_error_code end,
      priority = case when p_success then greatest(priority - 1, 10) else priority end,
      updated_at = now()
  where asset_id = p_asset_id and lease_token = p_lease_token;
  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

create or replace function public.complete_market_catalog_run(
  p_run_id bigint,
  p_provider text,
  p_complete boolean
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_provider not in ('brapi', 'twelve_data', 'coin_gecko') then
    raise exception using errcode = '22023', message = 'invalid_market_provider';
  end if;
  if not p_complete then return; end if;

  update public.market_asset_sources
  set missing_sync_count = case
        when last_seen_run_id = p_run_id then 0
        else least(missing_sync_count + 1, 3)
      end,
      is_active = case
        when last_seen_run_id = p_run_id then true
        else missing_sync_count + 1 < 3
      end,
      updated_at = now()
  where provider = p_provider;

  update public.market_assets a
  set is_active = exists (
        select 1 from public.market_asset_sources s
        where s.asset_id = a.id and s.is_active
      ),
      updated_at = now()
  where exists (
    select 1 from public.market_asset_sources s where s.asset_id = a.id
  );
end;
$$;

create or replace function public.prune_market_quote_history()
returns table (quotes_deleted bigint, targets_deleted bigint)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  delete from public.market_asset_quotes_daily
  where quote_date < current_date - interval '5 years';
  get diagnostics quotes_deleted = row_count;

  delete from public.market_asset_refresh_targets
  where last_seen_at < now() - interval '30 days';
  get diagnostics targets_deleted = row_count;
  return next;
end;
$$;

revoke all on function public.search_market_assets(text, text, text, integer)
  from public, anon, authenticated;
revoke all on function public.renew_market_asset_targets(jsonb, text)
  from public, anon, authenticated;
revoke all on function public.reserve_market_provider_credits(text, text, integer)
  from public, anon, authenticated;
revoke all on function public.claim_market_refresh_targets(integer, integer)
  from public, anon, authenticated;
revoke all on function public.complete_market_refresh(bigint, uuid, boolean, timestamptz, text)
  from public, anon, authenticated;
revoke all on function public.complete_market_catalog_run(bigint, text, boolean)
  from public, anon, authenticated;
revoke all on function public.prune_market_quote_history()
  from public, anon, authenticated;

grant execute on function public.search_market_assets(text, text, text, integer)
  to service_role;
grant execute on function public.renew_market_asset_targets(jsonb, text)
  to service_role;
grant execute on function public.reserve_market_provider_credits(text, text, integer)
  to service_role;
grant execute on function public.claim_market_refresh_targets(integer, integer)
  to service_role;
grant execute on function public.complete_market_refresh(bigint, uuid, boolean, timestamptz, text)
  to service_role;
grant execute on function public.complete_market_catalog_run(bigint, text, boolean)
  to service_role;
grant execute on function public.prune_market_quote_history()
  to service_role;

create or replace function equis_private.invoke_market_sync(p_operation text)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_project_url text;
  v_sync_secret text;
  v_request_id bigint;
begin
  if p_operation not in ('catalog', 'quotes', 'cleanup') then
    raise exception using errcode = '22023', message = 'invalid_market_sync_operation';
  end if;

  select decrypted_secret into v_project_url
  from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_sync_secret
  from vault.decrypted_secrets where name = 'market_sync_secret' limit 1;

  if v_project_url is null or v_sync_secret is null then
    return null;
  end if;

  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/sync-market-data',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-equis-sync-secret', v_sync_secret
    ),
    body := jsonb_build_object('operation', p_operation)
  ) into v_request_id;
  return v_request_id;
end;
$$;

revoke all on function equis_private.invoke_market_sync(text)
  from public, anon, authenticated, service_role;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job
    where jobname in (
      'equis-market-catalog',
      'equis-market-quotes',
      'equis-market-cleanup'
    )
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'equis-market-catalog',
    '30 4 * * *',
    $job$select equis_private.invoke_market_sync('catalog');$job$
  );
  perform cron.schedule(
    'equis-market-quotes',
    '15 * * * *',
    $job$select equis_private.invoke_market_sync('quotes');$job$
  );
  perform cron.schedule(
    'equis-market-cleanup',
    '45 5 * * *',
    $job$select equis_private.invoke_market_sync('cleanup');$job$
  );
end
$$;
