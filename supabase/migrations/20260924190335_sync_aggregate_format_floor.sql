-- The server cannot inspect encrypted aggregates. A vault-wide, monotonic
-- floor prevents 1.1 clients from replacing format-2 ciphertext after opt-in.
begin;

alter table public.vaults
  add column min_aggregate_format smallint not null default 1
  constraint vaults_min_aggregate_format_check
    check (min_aggregate_format in (1, 2));

create function equis_private.prevent_sync_format_downgrade()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.min_aggregate_format < old.min_aggregate_format then
    raise exception using
      errcode = '22023',
      message = 'aggregate_format_downgrade_forbidden';
  end if;
  return new;
end;
$$;
revoke all on function equis_private.prevent_sync_format_downgrade()
  from public, anon, authenticated;

create trigger vaults_min_aggregate_format_monotonic
before update of min_aggregate_format on public.vaults
for each row execute function equis_private.prevent_sync_format_downgrade();

-- All three operations lock this exact row before checking the floor or
-- changing sync records. The existing per-record CAS remains in _internal.
create function equis_private.lock_vault_for_sync(
  p_vault_id uuid,
  p_key_fingerprint text
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vault public.vaults%rowtype;
begin
  if not equis_private.owns_vault(p_vault_id) then
    raise exception using errcode = '42501', message = 'owner_account_required';
  end if;

  select * into v_vault
  from public.vaults
  where id = p_vault_id
  for update;
  if not found or v_vault.owner_id <> auth.uid() then
    raise exception using errcode = '42501', message = 'owner_account_required';
  end if;
  if p_key_fingerprint is null or
     v_vault.key_fingerprint <> p_key_fingerprint then
    raise exception using errcode = 'EVK01', message = 'vault_key_mismatch';
  end if;
  return v_vault.min_aggregate_format;
end;
$$;
revoke all on function equis_private.lock_vault_for_sync(uuid, text)
  from public, anon, authenticated;

-- Replace only the private implementation; the public three-argument RPC and
-- its existing grants keep the 1.1 signature. Re-check under the vault lock.
create or replace function equis_private.apply_sync_batch(
  p_vault_id uuid,
  p_mutations jsonb,
  p_key_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if equis_private.lock_vault_for_sync(p_vault_id, p_key_fingerprint) >= 2 then
    raise exception using errcode = 'EVP02', message = 'client_upgrade_required';
  end if;
  return equis_private.apply_sync_batch_internal(p_vault_id, p_mutations);
end;
$$;
revoke all on function equis_private.apply_sync_batch(uuid, jsonb, text)
  from public, anon;
grant execute on function equis_private.apply_sync_batch(uuid, jsonb, text)
  to authenticated;

-- Activation is explicit. New clients must pull and rebase after this call
-- before their first format-2 push. The floor can never move back to 1.
create function equis_private.activate_sync_aggregate_format_2(
  p_vault_id uuid,
  p_key_fingerprint text
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_floor smallint;
begin
  v_floor := equis_private.lock_vault_for_sync(
    p_vault_id, p_key_fingerprint
  );
  if v_floor < 2 then
    update public.vaults
    set min_aggregate_format = 2
    where id = p_vault_id;
  end if;
  return 2;
end;
$$;
revoke all on function equis_private.activate_sync_aggregate_format_2(
  uuid, text
) from public, anon;
grant execute on function equis_private.activate_sync_aggregate_format_2(
  uuid, text
) to authenticated;

create function public.activate_sync_aggregate_format_2(
  p_vault_id uuid,
  p_key_fingerprint text
)
returns smallint
language sql
security invoker
set search_path = ''
as $$
  select equis_private.activate_sync_aggregate_format_2(
    p_vault_id, p_key_fingerprint
  );
$$;
revoke all on function public.activate_sync_aggregate_format_2(uuid, text)
  from public, anon;
grant execute on function public.activate_sync_aggregate_format_2(uuid, text)
  to authenticated;

create function equis_private.apply_sync_batch_format_2(
  p_vault_id uuid,
  p_mutations jsonb,
  p_key_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if equis_private.lock_vault_for_sync(
    p_vault_id, p_key_fingerprint
  ) < 2 then
    raise exception using
      errcode = 'EVP03',
      message = 'aggregate_format_activation_required';
  end if;
  return equis_private.apply_sync_batch_internal(p_vault_id, p_mutations);
end;
$$;
revoke all on function equis_private.apply_sync_batch_format_2(
  uuid, jsonb, text
) from public, anon;
grant execute on function equis_private.apply_sync_batch_format_2(
  uuid, jsonb, text
) to authenticated;

create function public.apply_sync_batch_format_2(
  p_vault_id uuid,
  p_mutations jsonb,
  p_key_fingerprint text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select equis_private.apply_sync_batch_format_2(
    p_vault_id, p_mutations, p_key_fingerprint
  );
$$;
revoke all on function public.apply_sync_batch_format_2(
  uuid, jsonb, text
) from public, anon;
grant execute on function public.apply_sync_batch_format_2(
  uuid, jsonb, text
) to authenticated;

notify pgrst, 'reload schema';
commit;
