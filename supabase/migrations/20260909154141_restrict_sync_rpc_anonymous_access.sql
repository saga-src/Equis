-- These RPCs authenticate callers and enforce vault membership internally.
-- Remove inherited/default anonymous EXECUTE; retain authenticated access.
revoke execute on function public.apply_sync_batch(uuid, jsonb) from public, anon;
revoke execute on function public.create_equis_vault(uuid, uuid, text) from public, anon;
revoke execute on function public.acknowledge_sync_cursor(uuid, uuid, bigint) from public, anon;
revoke execute on function public.is_vault_member(uuid) from public, anon;
revoke execute on function public.is_vault_attachment_path_member(text) from public, anon;
grant execute on function public.apply_sync_batch(uuid, jsonb) to authenticated;
grant execute on function public.create_equis_vault(uuid, uuid, text) to authenticated;
grant execute on function public.acknowledge_sync_cursor(uuid, uuid, bigint) to authenticated;
grant execute on function public.is_vault_member(uuid) to authenticated;
grant execute on function public.is_vault_attachment_path_member(text) to authenticated;
