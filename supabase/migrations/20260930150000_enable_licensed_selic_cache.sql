-- SGS 11 has an explicit ODbL license in the official BCB open-data catalog:
-- https://dadosabertos.bcb.gov.br/pt_BR/dataset/11-taxa-de-juros---selic
-- Equis includes the source/license notice, publishes its transformed Selic
-- table under ODbL, and exposes machine-readable data in bounded date pages.
-- This evidence does not grant rights for the other five SGS series.
begin;
-- The collector allows 15 seconds for SGS, plus Edge startup and database work.
-- pg_net's default two-second timeout can disconnect a normal collection.
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
    select 1 from public.economic_series_settings where persistence_allowed
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
    body := '{"operation":"collect"}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request_id;
  return v_request_id;
end;
$$;
revoke all on function equis_private.invoke_economic_series_sync()
  from public, anon, authenticated, service_role;

update public.economic_series_settings
set persistence_allowed = true,
    redistribution_allowed = true,
    updated_at = now()
where code = 11;
do $verify$
begin
  if not exists (select 1 from public.economic_series_settings
      where code = 11 and persistence_allowed and redistribution_allowed) then
    raise exception 'Licensed Selic settings were not provisioned';
  end if;
end;
$verify$;
commit;
