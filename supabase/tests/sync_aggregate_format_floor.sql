-- Run after migrations against an isolated PostgreSQL instance. Roll back all
-- test identities, ciphertext and floor changes.
begin;
select set_config('equis.test.owner', gen_random_uuid()::text, true);
select set_config('equis.test.other', gen_random_uuid()::text, true);
select set_config('equis.test.vault', gen_random_uuid()::text, true);
select set_config('equis.test.device', gen_random_uuid()::text, true);
insert into auth.users(id, aud, role)
values
  (current_setting('equis.test.owner')::uuid, 'authenticated', 'authenticated'),
  (current_setting('equis.test.other')::uuid, 'authenticated', 'authenticated');

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', current_setting('equis.test.owner'), true
);
do $test$
declare
  v uuid := current_setting('equis.test.vault')::uuid;
  d uuid := current_setting('equis.test.device')::uuid;
  fingerprint text := repeat('a', 64);
  v_record_id uuid := gen_random_uuid();
  mutation jsonb;
  result jsonb;
begin
  perform public.register_vault(v, d, fingerprint);
  if (select min_aggregate_format from public.vaults where id = v)
      is distinct from 1 then
    raise exception 'new vault must start at format 1';
  end if;

  mutation := jsonb_build_array(jsonb_build_object(
    'operation_id', gen_random_uuid(),
    'entity_type', 'transaction',
    'record_id', v_record_id,
    'expected_revision', null,
    'new_revision', 3,
    'cipher_version', 1,
    'nonce_hex', repeat('01', 24),
    'ciphertext_hex', repeat('02', 40),
    'is_deleted', false
  ));

  begin
    perform public.apply_sync_batch_format_2(v, mutation, fingerprint);
    raise exception 'format-2 push before activation was accepted';
  exception when sqlstate 'EVP03' then null;
  end;
  result := public.apply_sync_batch(v, mutation, fingerprint);
  if result->0->>'status' <> 'accepted' then
    raise exception '1.1 push before activation failed';
  end if;
  if (select revision from public.sync_records
      where vault_id = v and entity_type = 'transaction'
        and record_id = v_record_id) is distinct from 3 then
    raise exception '1.1 revision was not stored';
  end if;

  begin
    perform public.activate_sync_aggregate_format_2(v, repeat('b', 64));
    raise exception 'wrong fingerprint activated format 2';
  exception when sqlstate 'EVK01' then null;
  end;
  if public.activate_sync_aggregate_format_2(v, fingerprint) <> 2 or
     public.activate_sync_aggregate_format_2(v, fingerprint) <> 2 then
    raise exception 'activation must be idempotent';
  end if;
  if (select min_aggregate_format from public.vaults where id = v)
      is distinct from 2 then
    raise exception 'format floor was not raised';
  end if;

  begin
    perform public.apply_sync_batch(v, mutation, fingerprint);
    raise exception '1.1 replay after activation was accepted';
  exception when sqlstate 'EVP02' then null;
  end;
  begin
    perform public.apply_sync_batch(
      v, mutation, repeat('b', 64)
    );
    raise exception '1.1 wrong fingerprint was accepted';
  exception when sqlstate 'EVK01' then null;
  end;
  begin
    perform public.apply_sync_batch(v, mutation);
    raise exception 'pre-1.1 RPC was accepted';
  exception when sqlstate 'EVP01' then null;
  end;
  begin
    perform public.apply_sync_batch_format_2(
      v, mutation, repeat('b', 64)
    );
    raise exception 'format-2 wrong fingerprint was accepted';
  exception when sqlstate 'EVK01' then null;
  end;

  mutation := jsonb_set(
    jsonb_set(mutation, '{0,expected_revision}', '3'::jsonb),
    '{0,new_revision}', '7'::jsonb
  );
  result := public.apply_sync_batch_format_2(v, mutation, fingerprint);
  if result->0->>'status' <> 'accepted' or
     result->0->>'revision' <> '7' then
    raise exception 'format-2 CAS update failed';
  end if;
  if (select revision from public.sync_records
      where vault_id = v and entity_type = 'transaction'
        and record_id = v_record_id) is distinct from 7 then
    raise exception 'format-2 revision was not stored';
  end if;
  result := public.apply_sync_batch_format_2(v, mutation, fingerprint);
  if result->0->>'idempotent_replay' <> 'true' then
    raise exception 'format-2 idempotent replay failed';
  end if;
  mutation := jsonb_set(mutation, '{0,new_revision}', '8'::jsonb);
  result := public.apply_sync_batch_format_2(v, mutation, fingerprint);
  if result->0->>'status' <> 'conflict' then
    raise exception 'format-2 stale CAS write was accepted';
  end if;

  perform set_config(
    'request.jwt.claim.sub', current_setting('equis.test.other'), true
  );
  begin
    perform public.apply_sync_batch(v, mutation, fingerprint);
    raise exception 'other owner used 1.1 push';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.activate_sync_aggregate_format_2(v, fingerprint);
    raise exception 'other owner activated format 2';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.apply_sync_batch_format_2(v, mutation, fingerprint);
    raise exception 'other owner used format-2 push';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

reset role;
do $test$
declare
  v uuid := current_setting('equis.test.vault')::uuid;
begin
  begin
    update public.vaults set min_aggregate_format = 1 where id = v;
    raise exception 'format floor was lowered';
  exception when sqlstate '22023' then null;
  end;
  if (select min_aggregate_format from public.vaults where id = v)
      is distinct from 2 then
    raise exception 'format floor changed after downgrade attempt';
  end if;

  if has_function_privilege(
    'anon', 'public.activate_sync_aggregate_format_2(uuid,text)', 'execute'
  ) or has_function_privilege(
    'anon', 'public.apply_sync_batch_format_2(uuid,jsonb,text)', 'execute'
  ) or has_function_privilege(
    'authenticated', 'equis_private.lock_vault_for_sync(uuid,text)', 'execute'
  ) or has_function_privilege(
    'authenticated',
    'equis_private.apply_sync_batch_internal(uuid,jsonb)',
    'execute'
  ) then
    raise exception 'unexpected format-gate RPC grant';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.apply_sync_batch(uuid,jsonb,text)', 'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.activate_sync_aggregate_format_2(uuid,text)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.apply_sync_batch_format_2(uuid,jsonb,text)',
    'execute'
  ) then
    raise exception 'authenticated format-gate RPC grant missing';
  end if;
end;
$test$;
rollback;
