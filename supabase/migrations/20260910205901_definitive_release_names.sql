begin;
-- Public release names only: identities, ciphertext, revisions and cursors stay intact.
lock table public.vaults_v2, public.devices_v2, public.sync_records_v2 in access exclusive mode;
create temporary table equis_release_audit on commit drop as
select 'vaults' as name, count(*) as rows, md5(coalesce(string_agg(to_jsonb(t)::text, '' order by id),'')) as digest from public.vaults_v2 t
union all select 'devices',count(*),md5(coalesce(string_agg(to_jsonb(t)::text, '' order by id),'')) from public.devices_v2 t
union all select 'records',count(*),md5(coalesce(string_agg(to_jsonb(t)::text, '' order by vault_id,entity_type,record_id),'')) from public.sync_records_v2 t;

-- Preserve pre-migration ciphertext outside the exposed API schema.
create schema if not exists equis_legacy;
revoke all on schema equis_legacy from public,anon,authenticated;
alter table public.vaults set schema equis_legacy;
alter table public.vault_members set schema equis_legacy;
alter table public.devices set schema equis_legacy;
alter table public.sync_records set schema equis_legacy;
alter table public.vault_key_recovery set schema equis_legacy;
revoke all on all tables in schema equis_legacy from public,anon,authenticated;
alter sequence public.sync_server_version_seq set schema equis_legacy;

alter table public.vaults_v2 rename to vaults;
alter table public.devices_v2 rename to devices;
alter table public.sync_records_v2 rename to sync_records;
alter sequence public.sync_server_version_v2_seq rename to sync_server_version_seq;

-- Recompile string-bodied functions against the renamed relations and sequence.
do $$
declare signature text; definition text;
begin
 foreach signature in array array[
  'equis_private.owns_vault_v2(uuid)',
  'equis_private.register_vault_v2(uuid,uuid,text)',
  'equis_private.apply_sync_batch_internal_v2(uuid,jsonb)',
  'equis_private.apply_sync_batch_v2(uuid,jsonb,text)',
  'equis_private.acknowledge_sync_cursor_v2(uuid,uuid,bigint)',
  'public.register_vault_v2(uuid,uuid,text)',
  'public.apply_sync_batch_v2(uuid,jsonb,text)',
  'public.acknowledge_sync_cursor_v2(uuid,uuid,bigint)'] loop
   definition := pg_get_functiondef(signature::regprocedure);
   definition := replace(definition,'_v2','');
   execute definition;
 end loop;
end; $$;
revoke all on function equis_private.owns_vault(uuid), equis_private.apply_sync_batch_internal(uuid,jsonb) from public,anon,authenticated;
revoke all on function equis_private.register_vault(uuid,uuid,text), equis_private.apply_sync_batch(uuid,jsonb,text), equis_private.acknowledge_sync_cursor(uuid,uuid,bigint), public.register_vault(uuid,uuid,text), public.apply_sync_batch(uuid,jsonb,text), public.acknowledge_sync_cursor(uuid,uuid,bigint) from public,anon;
grant execute on function equis_private.register_vault(uuid,uuid,text), equis_private.apply_sync_batch(uuid,jsonb,text), equis_private.acknowledge_sync_cursor(uuid,uuid,bigint), public.register_vault(uuid,uuid,text), public.apply_sync_batch(uuid,jsonb,text), public.acknowledge_sync_cursor(uuid,uuid,bigint) to authenticated;

drop function public.register_vault_v2(uuid,uuid,text), public.apply_sync_batch_v2(uuid,jsonb,text), public.acknowledge_sync_cursor_v2(uuid,uuid,bigint);
drop function equis_private.register_vault_v2(uuid,uuid,text), equis_private.apply_sync_batch_v2(uuid,jsonb,text), equis_private.acknowledge_sync_cursor_v2(uuid,uuid,bigint), equis_private.apply_sync_batch_internal_v2(uuid,jsonb), equis_private.owns_vault_v2(uuid);

-- Replace the closed legacy bucket policies with the owner + fingerprint contract.
drop policy equis_attachments_member_delete on storage.objects;
drop policy equis_attachments_member_insert on storage.objects;
drop policy equis_attachments_member_select on storage.objects;
drop policy equis_attachments_member_update on storage.objects;
drop policy equis_legacy_storage_disabled on storage.objects;
drop policy equis_v2_storage_owner on storage.objects;
create policy equis_storage_owner on storage.objects for all to authenticated
using (bucket_id='equis-attachments' and (storage.foldername(name))[1]='vault' and (storage.foldername(name))[4]='attachments'
 and exists(select 1 from public.vaults where id::text=(storage.foldername(name))[2] and key_fingerprint=(storage.foldername(name))[3] and owner_id=(select auth.uid())))
with check (bucket_id='equis-attachments' and (storage.foldername(name))[1]='vault' and (storage.foldername(name))[4]='attachments'
 and exists(select 1 from public.vaults where id::text=(storage.foldername(name))[2] and key_fingerprint=(storage.foldername(name))[3] and owner_id=(select auth.uid())));
do $$ begin
 if exists(select 1 from storage.objects where bucket_id in ('equis-attachments','equis-attachments-v2')) then
  raise exception 'Storage inventory changed: migrate objects through the Storage API before renaming';
 end if;
end; $$;
-- The empty retired bucket is removed through the Storage API after deployment.
revoke all on function public.is_vault_member(uuid),public.is_vault_attachment_path_member(text) from public,anon,authenticated;

-- Remove transition suffixes from indexes, constraints and policies as well.
do $$
declare item record;
begin
 for item in select conrelid::regclass as relation,conname from pg_constraint where connamespace='public'::regnamespace and conname like '%_v2%' loop
  execute format('alter table %s rename constraint %I to %I',item.relation,item.conname,replace(item.conname,'_v2',''));
 end loop;
 for item in select indexname from pg_indexes where schemaname='public' and indexname like '%_v2%' loop
  execute format('alter index public.%I rename to %I',item.indexname,replace(item.indexname,'_v2',''));
 end loop;
 for item in select tablename,policyname from pg_policies where schemaname='public' and policyname like '%_v2%' loop
  execute format('alter policy %I on public.%I rename to %I',item.policyname,item.tablename,replace(item.policyname,'_v2',''));
 end loop;
end; $$;

do $$
declare item record; n bigint; digest text;
begin
 for item in select * from equis_release_audit loop
  if item.name='records' then
   select count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'' order by vault_id,entity_type,record_id),'')) into n,digest from public.sync_records t;
  else
   execute format('select count(*),md5(coalesce(string_agg(to_jsonb(t)::text, %L order by id),%L)) from public.%I t','','',item.name) into n,digest;
  end if;
  if n<>item.rows or digest<>item.digest then raise exception 'Release rename changed vault data'; end if;
 end loop;
end; $$;
notify pgrst, 'reload schema';

commit;
