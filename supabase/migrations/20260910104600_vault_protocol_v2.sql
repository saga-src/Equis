-- New protocol is isolated from legacy ciphertext. No user data is deleted here.
create schema if not exists equis_private;
revoke all on schema equis_private from public, anon;
grant usage on schema equis_private to authenticated;

create table public.vaults_v2 (
  id uuid primary key,
  owner_id uuid not null references auth.users(id),
  key_fingerprint text not null check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  protocol_version smallint not null default 2 check (protocol_version = 2),
  created_at timestamptz not null default now()
);
create index vaults_v2_owner_idx on public.vaults_v2(owner_id);
create table public.devices_v2 (
  id uuid primary key,
  vault_id uuid not null references public.vaults_v2(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_acknowledged_server_version bigint not null default 0 check (last_acknowledged_server_version >= 0)
);
create index devices_v2_vault_idx on public.devices_v2(vault_id);
create index devices_v2_user_idx on public.devices_v2(user_id);
create sequence public.sync_server_version_v2_seq as bigint;
create table public.sync_records_v2 (like public.sync_records including all);
alter table public.sync_records_v2 add foreign key(vault_id) references public.vaults_v2(id) on delete cascade;

alter table public.vaults_v2 enable row level security;
alter table public.devices_v2 enable row level security;
alter table public.sync_records_v2 enable row level security;
revoke all on public.vaults_v2, public.devices_v2, public.sync_records_v2 from public, anon, authenticated;
grant select on public.vaults_v2, public.devices_v2, public.sync_records_v2 to authenticated;
revoke all on sequence public.sync_server_version_v2_seq from public, anon, authenticated;
create policy vault_v2_owner_read on public.vaults_v2 for select to authenticated using (owner_id = (select auth.uid()));
create policy device_v2_owner_read on public.devices_v2 for select to authenticated using (vault_id in (select id from public.vaults_v2 where owner_id = (select auth.uid())));
create policy record_v2_owner_read on public.sync_records_v2 for select to authenticated using (vault_id in (select id from public.vaults_v2 where owner_id = (select auth.uid())));

create function equis_private.owns_vault_v2(p_vault_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.vaults_v2 where id = p_vault_id and owner_id = auth.uid());
$$;
revoke all on function equis_private.owns_vault_v2(uuid) from public, anon, authenticated;

create function equis_private.register_vault_v2(p_vault_id uuid, p_device_id uuid, p_key_fingerprint text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_vault public.vaults_v2%rowtype;
begin
  if auth.uid() is null then raise exception using errcode='42501', message='authentication_required'; end if;
  if p_vault_id is null or p_device_id is null or p_key_fingerprint is null or p_key_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023', message='invalid_vault_identity';
  end if;
  insert into public.vaults_v2(id, owner_id, key_fingerprint) values(p_vault_id, auth.uid(), p_key_fingerprint) on conflict(id) do nothing;
  select * into strict v_vault from public.vaults_v2 where id=p_vault_id for update;
  if v_vault.owner_id <> auth.uid() then raise exception using errcode='42501', message='owner_account_required'; end if;
  if v_vault.key_fingerprint <> p_key_fingerprint then raise exception using errcode='EVK01', message='vault_key_mismatch'; end if;
  insert into public.devices_v2(id,vault_id,user_id) values(p_device_id,p_vault_id,auth.uid())
    on conflict(id) do update set last_seen_at=now() where public.devices_v2.vault_id=excluded.vault_id and public.devices_v2.user_id=excluded.user_id;
  if not found then raise exception using errcode='42501', message='device_identity_conflict'; end if;
end;
$$;
revoke all on function equis_private.register_vault_v2(uuid,uuid,text) from public, anon;
grant execute on function equis_private.register_vault_v2(uuid,uuid,text) to authenticated;
create function public.register_vault_v2(p_vault_id uuid,p_device_id uuid,p_key_fingerprint text) returns void
language sql security invoker set search_path='' as $$ select equis_private.register_vault_v2(p_vault_id,p_device_id,p_key_fingerprint); $$;
revoke all on function public.register_vault_v2(uuid,uuid,text) from public, anon;
grant execute on function public.register_vault_v2(uuid,uuid,text) to authenticated;

-- Reuse the tested monotonic-revision/CAS implementation, isolated in a private schema.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.apply_sync_batch(uuid,jsonb)'::regprocedure) into definition;
  if position('v_new_revision > v_expected_revision' in definition)=0 then raise exception 'Monotonic sync migration is required'; end if;
  definition := replace(definition,'public.apply_sync_batch(', 'equis_private.apply_sync_batch_internal_v2(');
  definition := replace(definition,'public.sync_records','public.sync_records_v2');
  definition := replace(definition,'public.sync_server_version_seq','public.sync_server_version_v2_seq');
  definition := replace(definition,'public.is_vault_member','equis_private.owns_vault_v2');
  execute definition;
end;
$$;
revoke all on function equis_private.apply_sync_batch_internal_v2(uuid,jsonb) from public, anon, authenticated;

create function equis_private.apply_sync_batch_v2(p_vault_id uuid,p_mutations jsonb,p_key_fingerprint text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare fingerprint text;
begin
  if not equis_private.owns_vault_v2(p_vault_id) then raise exception using errcode='42501', message='owner_account_required'; end if;
  select key_fingerprint into fingerprint from public.vaults_v2 where id=p_vault_id;
  if p_key_fingerprint is null or fingerprint <> p_key_fingerprint then raise exception using errcode='EVK01', message='vault_key_mismatch'; end if;
  return equis_private.apply_sync_batch_internal_v2(p_vault_id,p_mutations);
end;
$$;
revoke all on function equis_private.apply_sync_batch_v2(uuid,jsonb,text) from public, anon;
grant execute on function equis_private.apply_sync_batch_v2(uuid,jsonb,text) to authenticated;
create function public.apply_sync_batch_v2(p_vault_id uuid,p_mutations jsonb,p_key_fingerprint text) returns jsonb
language sql security invoker set search_path='' as $$ select equis_private.apply_sync_batch_v2(p_vault_id,p_mutations,p_key_fingerprint); $$;
revoke all on function public.apply_sync_batch_v2(uuid,jsonb,text) from public, anon;
grant execute on function public.apply_sync_batch_v2(uuid,jsonb,text) to authenticated;

create function equis_private.acknowledge_sync_cursor_v2(p_vault_id uuid,p_device_id uuid,p_server_version bigint) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not equis_private.owns_vault_v2(p_vault_id) then raise exception using errcode='42501', message='owner_account_required'; end if;
  if p_server_version is null or p_server_version<0 then raise exception using errcode='22023', message='invalid_cursor'; end if;
  update public.devices_v2 set last_acknowledged_server_version=greatest(last_acknowledged_server_version,p_server_version),last_seen_at=now()
    where id=p_device_id and vault_id=p_vault_id and user_id=auth.uid();
  if not found then raise exception using errcode='42501', message='device_access_denied'; end if;
end;
$$;
revoke all on function equis_private.acknowledge_sync_cursor_v2(uuid,uuid,bigint) from public, anon;
grant execute on function equis_private.acknowledge_sync_cursor_v2(uuid,uuid,bigint) to authenticated;
create function public.acknowledge_sync_cursor_v2(p_vault_id uuid,p_device_id uuid,p_server_version bigint) returns void
language sql security invoker set search_path='' as $$ select equis_private.acknowledge_sync_cursor_v2(p_vault_id,p_device_id,p_server_version); $$;
revoke all on function public.acknowledge_sync_cursor_v2(uuid,uuid,bigint) from public, anon;
grant execute on function public.acknowledge_sync_cursor_v2(uuid,uuid,bigint) to authenticated;

insert into storage.buckets(id,name,public) values('equis-attachments-v2','equis-attachments-v2',false) on conflict(id) do nothing;
create policy equis_v2_storage_owner on storage.objects for all to authenticated
using (bucket_id='equis-attachments-v2' and (storage.foldername(name))[1]='vault' and (storage.foldername(name))[4]='attachments'
  and exists(select 1 from public.vaults_v2 where id::text=(storage.foldername(name))[2] and key_fingerprint=(storage.foldername(name))[3] and owner_id=(select auth.uid())))
with check (bucket_id='equis-attachments-v2' and (storage.foldername(name))[1]='vault' and (storage.foldername(name))[4]='attachments'
  and exists(select 1 from public.vaults_v2 where id::text=(storage.foldername(name))[2] and key_fingerprint=(storage.foldername(name))[3] and owner_id=(select auth.uid())));

-- Fail old clients explicitly; do not delete their existing ciphertext yet.
create or replace function public.create_equis_vault(p_vault_id uuid,p_device_id uuid,p_device_public_key_hex text default null) returns void
language plpgsql security invoker set search_path='' as $$ begin raise exception using errcode='EVP01', message='client_upgrade_required'; end; $$;
create or replace function public.apply_sync_batch(p_vault_id uuid,p_mutations jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$ begin raise exception using errcode='EVP01', message='client_upgrade_required'; end; $$;
create or replace function public.acknowledge_sync_cursor(p_vault_id uuid,p_device_id uuid,p_server_version bigint) returns void
language plpgsql security invoker set search_path='' as $$ begin raise exception using errcode='EVP01', message='client_upgrade_required'; end; $$;
revoke all on public.vaults,public.vault_members,public.devices,public.sync_records,public.vault_key_recovery from anon,authenticated;
-- Restrictive policy closes every legacy Storage route even if older permissive policies remain.
create policy equis_legacy_storage_disabled on storage.objects as restrictive for all to authenticated
using (bucket_id <> 'equis-attachments') with check (bucket_id <> 'equis-attachments');

do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.sync_records_v2;
 end if;
end; $$;
