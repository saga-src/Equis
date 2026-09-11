-- Equis Phase 18: intentionally minimal encrypted synchronization schema.

create sequence if not exists public.sync_server_version_seq as bigint;

create table public.vaults (
  id uuid primary key,
  created_at timestamptz not null default now()
);

create table public.vault_members (
  vault_id uuid not null references public.vaults(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner')),
  created_at timestamptz not null default now(),
  primary key (vault_id, user_id)
);

create table public.devices (
  id uuid primary key,
  vault_id uuid not null references public.vaults(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  public_key bytea,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  last_acknowledged_server_version bigint not null default 0
    check (last_acknowledged_server_version >= 0),
  unique (vault_id, id)
);

create table public.sync_records (
  vault_id uuid not null references public.vaults(id) on delete cascade,
  entity_type text not null check (
    entity_type in (
      'vault', 'account', 'category', 'counterparty', 'tag', 'transaction',
      'recurring_rule', 'installment_plan', 'credit_card_statement', 'budget',
      'goal', 'asset', 'investment_instrument', 'manual_fx_rate',
      'manual_market_price', 'attachment'
    )
  ),
  record_id uuid not null,
  revision bigint not null check (revision > 0),
  server_version bigint not null unique,
  cipher_version smallint not null check (cipher_version = 1),
  nonce bytea not null check (octet_length(nonce) = 24),
  ciphertext bytea not null check (octet_length(ciphertext) >= 20),
  is_deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (vault_id, entity_type, record_id)
);

create index idx_sync_records_pull
  on public.sync_records (vault_id, server_version);

create table public.vault_key_recovery (
  vault_id uuid primary key references public.vaults(id) on delete cascade,
  wrapped_vault_key bytea not null check (octet_length(wrapped_vault_key) = 48),
  kdf text not null check (kdf = 'argon2id'),
  kdf_parameters jsonb not null,
  salt bytea not null check (octet_length(salt) >= 16),
  nonce bytea not null check (octet_length(nonce) = 24),
  key_version integer not null default 1 check (key_version > 0),
  created_at timestamptz not null default now()
);

alter table public.vaults enable row level security;
alter table public.vault_members enable row level security;
alter table public.devices enable row level security;
alter table public.sync_records enable row level security;
alter table public.vault_key_recovery enable row level security;

create or replace function public.is_vault_member(p_vault_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.vault_members vm
    where vm.vault_id = p_vault_id
      and vm.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_vault_member(uuid) from public;
grant execute on function public.is_vault_member(uuid) to authenticated;

create policy vaults_member_select on public.vaults
  for select to authenticated
  using ((select public.is_vault_member(id)));

create policy vault_members_self_select on public.vault_members
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy devices_member_select on public.devices
  for select to authenticated
  using ((select public.is_vault_member(vault_id)));

create policy devices_self_insert on public.devices
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.is_vault_member(vault_id))
  );

create policy devices_self_update on public.devices
  for update to authenticated
  using (
    user_id = (select auth.uid())
    and (select public.is_vault_member(vault_id))
  )
  with check (
    user_id = (select auth.uid())
    and (select public.is_vault_member(vault_id))
  );

create policy sync_records_member_select on public.sync_records
  for select to authenticated
  using ((select public.is_vault_member(vault_id)));

create policy recovery_member_select on public.vault_key_recovery
  for select to authenticated
  using ((select public.is_vault_member(vault_id)));

create policy recovery_member_insert on public.vault_key_recovery
  for insert to authenticated
  with check ((select public.is_vault_member(vault_id)));

create policy recovery_member_update on public.vault_key_recovery
  for update to authenticated
  using ((select public.is_vault_member(vault_id)))
  with check ((select public.is_vault_member(vault_id)));

create or replace function public.create_equis_vault(
  p_vault_id uuid,
  p_device_id uuid,
  p_device_public_key_hex text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if p_device_public_key_hex is not null and
     p_device_public_key_hex !~ '^[0-9a-fA-F]+$' then
    raise exception using errcode = '22023', message = 'invalid_public_key';
  end if;

  insert into public.vaults (id) values (p_vault_id)
  on conflict (id) do nothing;

  if exists (
    select 1 from public.vault_members
    where vault_id = p_vault_id and user_id <> v_user_id
  ) then
    raise exception using errcode = '42501', message = 'vault_already_owned';
  end if;

  insert into public.vault_members (vault_id, user_id, role)
  values (p_vault_id, v_user_id, 'owner')
  on conflict (vault_id, user_id) do nothing;

  insert into public.devices (id, vault_id, user_id, public_key, last_seen_at)
  values (
    p_device_id,
    p_vault_id,
    v_user_id,
    case when p_device_public_key_hex is null then null
         else decode(p_device_public_key_hex, 'hex') end,
    now()
  )
  on conflict (id) do update
  set last_seen_at = excluded.last_seen_at,
      public_key = coalesce(excluded.public_key, public.devices.public_key)
  where public.devices.vault_id = excluded.vault_id
    and public.devices.user_id = excluded.user_id;

  if not exists (
    select 1 from public.devices
    where id = p_device_id
      and vault_id = p_vault_id
      and user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'device_identity_conflict';
  end if;
end;
$$;

revoke all on function public.create_equis_vault(uuid, uuid, text) from public;
grant execute on function public.create_equis_vault(uuid, uuid, text) to authenticated;

create or replace function public.acknowledge_sync_cursor(
  p_vault_id uuid,
  p_device_id uuid,
  p_server_version bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or p_server_version < 0 then
    raise exception using errcode = '22023', message = 'invalid_sync_acknowledgement';
  end if;

  update public.devices
  set last_acknowledged_server_version = greatest(
        last_acknowledged_server_version,
        p_server_version
      ),
      last_seen_at = now()
  where id = p_device_id
    and vault_id = p_vault_id
    and user_id = auth.uid();

  if not found then
    raise exception using errcode = '42501', message = 'device_access_denied';
  end if;
end;
$$;

revoke all on function public.acknowledge_sync_cursor(uuid, uuid, bigint) from public;
grant execute on function public.acknowledge_sync_cursor(uuid, uuid, bigint)
  to authenticated;

create or replace function public.apply_sync_batch(
  p_vault_id uuid,
  p_mutations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mutation jsonb;
  v_results jsonb := '[]'::jsonb;
  v_record public.sync_records%rowtype;
  v_operation_id uuid;
  v_entity_type text;
  v_record_id uuid;
  v_expected_revision bigint;
  v_new_revision bigint;
  v_cipher_version smallint;
  v_nonce bytea;
  v_ciphertext bytea;
  v_is_deleted boolean;
  v_server_version bigint;
begin
  if auth.uid() is null or not public.is_vault_member(p_vault_id) then
    raise exception using errcode = '42501', message = 'vault_access_denied';
  end if;
  if jsonb_typeof(p_mutations) <> 'array' or
     jsonb_array_length(p_mutations) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'invalid_sync_batch';
  end if;

  for v_mutation in select value from jsonb_array_elements(p_mutations)
  loop
    begin
      v_operation_id := (v_mutation ->> 'operation_id')::uuid;
      v_entity_type := v_mutation ->> 'entity_type';
      v_record_id := (v_mutation ->> 'record_id')::uuid;
      v_expected_revision := nullif(v_mutation ->> 'expected_revision', '')::bigint;
      v_new_revision := (v_mutation ->> 'new_revision')::bigint;
      v_cipher_version := (v_mutation ->> 'cipher_version')::smallint;
      v_nonce := decode(v_mutation ->> 'nonce_hex', 'hex');
      v_ciphertext := decode(v_mutation ->> 'ciphertext_hex', 'hex');
      v_is_deleted := coalesce((v_mutation ->> 'is_deleted')::boolean, false);
    exception when others then
      raise exception using errcode = '22023', message = 'invalid_sync_mutation';
    end;

    if v_entity_type not in (
         'vault', 'account', 'category', 'counterparty', 'tag', 'transaction',
         'recurring_rule', 'installment_plan', 'credit_card_statement', 'budget',
         'goal', 'asset', 'investment_instrument', 'manual_fx_rate',
         'manual_market_price', 'attachment'
       ) or v_new_revision < 1 or v_cipher_version <> 1 or
       octet_length(v_nonce) <> 24 or octet_length(v_ciphertext) < 20 then
      raise exception using errcode = '22023', message = 'invalid_sync_mutation';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_vault_id::text || ':' || v_entity_type || ':' || v_record_id::text,
        0
      )
    );

    select * into v_record
    from public.sync_records
    where vault_id = p_vault_id
      and entity_type = v_entity_type
      and record_id = v_record_id
    for update;

    if found and v_record.revision = v_new_revision and
       v_record.cipher_version = v_cipher_version and
       v_record.nonce = v_nonce and v_record.ciphertext = v_ciphertext and
       v_record.is_deleted = v_is_deleted then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'operation_id', v_operation_id,
        'status', 'accepted',
        'revision', v_record.revision,
        'server_version', v_record.server_version,
        'idempotent_replay', true
      ));
    elsif (not found and coalesce(v_expected_revision, 0) = 0 and
           v_new_revision = 1) or
          (found and v_expected_revision = v_record.revision and
           v_new_revision = v_expected_revision + 1) then
      v_server_version := nextval('public.sync_server_version_seq');
      insert into public.sync_records (
        vault_id, entity_type, record_id, revision, server_version,
        cipher_version, nonce, ciphertext, is_deleted, updated_at
      ) values (
        p_vault_id, v_entity_type, v_record_id, v_new_revision,
        v_server_version, v_cipher_version, v_nonce, v_ciphertext,
        v_is_deleted, now()
      )
      on conflict (vault_id, entity_type, record_id) do update set
        revision = excluded.revision,
        server_version = excluded.server_version,
        cipher_version = excluded.cipher_version,
        nonce = excluded.nonce,
        ciphertext = excluded.ciphertext,
        is_deleted = excluded.is_deleted,
        updated_at = excluded.updated_at;

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'operation_id', v_operation_id,
        'status', 'accepted',
        'revision', v_new_revision,
        'server_version', v_server_version,
        'idempotent_replay', false
      ));
    else
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'operation_id', v_operation_id,
        'status', 'conflict',
        'remote_revision', case when found then v_record.revision else null end,
        'server_version', case when found then v_record.server_version else null end
      ));
    end if;
  end loop;

  return v_results;
end;
$$;

revoke all on function public.apply_sync_batch(uuid, jsonb) from public;
grant execute on function public.apply_sync_batch(uuid, jsonb) to authenticated;

revoke all on sequence public.sync_server_version_seq from anon, authenticated;
revoke all on table public.vaults from anon, authenticated;
revoke all on table public.vault_members from anon, authenticated;
revoke all on table public.devices from anon, authenticated;
revoke all on table public.sync_records from anon, authenticated;
revoke all on table public.vault_key_recovery from anon, authenticated;

grant select on public.vaults, public.vault_members, public.devices,
  public.sync_records to authenticated;
grant insert, update on public.devices to authenticated;
grant select, insert, update on public.vault_key_recovery to authenticated;

do $$
begin
  if exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sync_records'
  ) then
    alter publication supabase_realtime add table public.sync_records;
  end if;
end
$$;
