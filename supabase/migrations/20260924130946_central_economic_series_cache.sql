-- Public economic observations, independent of any vault or instrument.
-- Source-specific storage and redistribution remain disabled until reviewed.
create table public.economic_series_settings (
  code integer primary key check (code in (11, 12, 188, 189, 226, 433)),
  unit text not null check (unit in (
    'percent_per_day', 'percent_per_month', 'percent_per_validity_period'
  )),
  source text not null default 'BCB_SGS' check (source = 'BCB_SGS'),
  persistence_allowed boolean not null default false,
  redistribution_allowed boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (code, unit)
);

insert into public.economic_series_settings (code, unit) values
  (11, 'percent_per_day'),
  (12, 'percent_per_day'),
  (188, 'percent_per_month'),
  (189, 'percent_per_month'),
  (226, 'percent_per_validity_period'),
  (433, 'percent_per_month');

create table public.economic_series_observations (
  code integer not null,
  unit text not null,
  reference_start date not null,
  reference_end date not null check (reference_end >= reference_start),
  value numeric(24, 12) not null,
  source text not null default 'BCB_SGS' check (source = 'BCB_SGS'),
  fetched_at timestamptz not null,
  primary key (code, reference_start),
  foreign key (code, unit)
    references public.economic_series_settings(code, unit)
);

create index economic_series_observations_period_idx
  on public.economic_series_observations (code, reference_end);

create table public.economic_series_collection_state (
  code integer primary key references public.economic_series_settings(code),
  next_from date not null,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  recent_seeded_at timestamptz,
  last_error_code text,
  last_reference_start date,
  last_reference_end date,
  last_observation_count integer not null default 0
    check (last_observation_count >= 0),
  lease_token uuid,
  lease_until timestamptz
);

-- Earliest observations confirmed from bounded official SGS queries.
-- Starting at source inception covers old lots without sending position dates.
insert into public.economic_series_collection_state (code, next_from) values
  (11, date '1986-06-04'),
  (12, date '1986-03-06'),
  (188, date '1979-04-01'),
  (189, date '1989-06-01'),
  (226, date '1991-02-01'),
  (433, date '1980-01-01');

alter table public.economic_series_settings enable row level security;
alter table public.economic_series_observations enable row level security;
alter table public.economic_series_collection_state enable row level security;

revoke all on table
  public.economic_series_settings,
  public.economic_series_observations,
  public.economic_series_collection_state
from public, anon, authenticated;

grant select, insert, update on table
  public.economic_series_settings,
  public.economic_series_observations,
  public.economic_series_collection_state
to service_role;

-- Return numeric observations as text so JSON clients never round a factor.
create function public.read_economic_series(
  p_code integer,
  p_from date,
  p_through date
)
returns table (
  code integer,
  unit text,
  reference_start date,
  reference_end date,
  value text,
  source text,
  fetched_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select o.code, o.unit, o.reference_start, o.reference_end,
    o.value::text, o.source, o.fetched_at
  from public.economic_series_observations o
  where o.code = p_code
    and o.reference_start <= p_through
    and o.reference_end >= p_from
  order by o.reference_start
  limit 410;
$$;

revoke all on function public.read_economic_series(integer, date, date)
  from public, anon, authenticated;
grant execute on function public.read_economic_series(integer, date, date)
  to service_role;

-- The cron job is inert while every source has persistence_allowed=false.
-- The URL and secret must be provisioned in Vault before enabling collection.
create or replace function equis_private.invoke_economic_series_sync()
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
  if not exists (
    select 1 from public.economic_series_settings
    where persistence_allowed
  ) then
    return null;
  end if;

  select decrypted_secret into v_project_url
  from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_sync_secret
  from vault.decrypted_secrets
  where name = 'economic_series_sync_secret' limit 1;
  if v_project_url is null or v_sync_secret is null then
    return null;
  end if;

  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/sync-economic-series',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-equis-sync-secret', v_sync_secret
    ),
    body := '{"operation":"collect"}'::jsonb
  ) into v_request_id;
  return v_request_id;
end;
$$;

revoke all on function equis_private.invoke_economic_series_sync()
  from public, anon, authenticated, service_role;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'equis-economic-series'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'equis-economic-series',
    '30 * * * *',
    $job$select equis_private.invoke_economic_series_sync();$job$
  );
end;
$$;
