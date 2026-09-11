-- Equis Phase 19: private ciphertext-only attachment storage.

insert into storage.buckets (id, name, public, allowed_mime_types)
values (
  'equis-attachments',
  'equis-attachments',
  false,
  array['application/octet-stream']
)
on conflict (id) do update set
  public = false,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_vault_attachment_path_member(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    array_length(string_to_array(p_name, '/'), 1) = 4
    and split_part(p_name, '/', 1) = 'vault'
    and split_part(p_name, '/', 3) = 'attachments'
    and split_part(p_name, '/', 4) ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and exists (
      select 1
      from public.vault_members vm
      where vm.vault_id::text = split_part(p_name, '/', 2)
        and vm.user_id = (select auth.uid())
    );
$$;

revoke all on function public.is_vault_attachment_path_member(text) from public;
grant execute on function public.is_vault_attachment_path_member(text)
  to authenticated;

drop policy if exists equis_attachments_member_select on storage.objects;
create policy equis_attachments_member_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'equis-attachments'
    and (select public.is_vault_attachment_path_member(name))
  );

drop policy if exists equis_attachments_member_insert on storage.objects;
create policy equis_attachments_member_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'equis-attachments'
    and (select public.is_vault_attachment_path_member(name))
  );

drop policy if exists equis_attachments_member_update on storage.objects;
create policy equis_attachments_member_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'equis-attachments'
    and (select public.is_vault_attachment_path_member(name))
  )
  with check (
    bucket_id = 'equis-attachments'
    and (select public.is_vault_attachment_path_member(name))
  );

drop policy if exists equis_attachments_member_delete on storage.objects;
create policy equis_attachments_member_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'equis-attachments'
    and (select public.is_vault_attachment_path_member(name))
  );
