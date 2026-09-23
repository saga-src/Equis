-- Restore the authenticated role's ability to resolve the deliberately
-- restricted sync functions in equis_private. Object-level EXECUTE grants
-- remain the allowlist; no private tables or broad function access is added.
revoke all on schema equis_private from public, anon;
grant usage on schema equis_private to authenticated;

do $$
begin
  if not has_schema_privilege(
    'authenticated',
    'equis_private',
    'usage'
  ) then
    raise exception 'authenticated must retain usage on equis_private';
  end if;

  if has_schema_privilege('anon', 'equis_private', 'usage') then
    raise exception 'anon must not have usage on equis_private';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.register_vault(uuid,uuid,text)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.apply_sync_batch(uuid,jsonb,text)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.acknowledge_sync_cursor(uuid,uuid,bigint)',
    'execute'
  ) then
    raise exception 'authenticated sync wrapper privileges are incomplete';
  end if;

  if not has_function_privilege(
    'authenticated',
    'equis_private.register_vault(uuid,uuid,text)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'equis_private.apply_sync_batch(uuid,jsonb,text)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'equis_private.acknowledge_sync_cursor(uuid,uuid,bigint)',
    'execute'
  ) then
    raise exception 'authenticated private sync privileges are incomplete';
  end if;
end;
$$;
