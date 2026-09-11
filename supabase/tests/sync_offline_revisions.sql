begin;
do $test$
declare u uuid; v uuid := gen_random_uuid(); d uuid := gen_random_uuid(); rec uuid := gen_random_uuid(); op uuid := gen_random_uuid(); m jsonb; r jsonb;
begin
select id into u from auth.users limit 1;
if u is null then raise exception 'test_requires_existing_identity'; end if;
perform set_config('request.jwt.claim.sub',u::text,true);
perform public.create_equis_vault(v,d,null);
m := jsonb_build_object('operation_id',op,'entity_type','tag','record_id',rec,'new_revision',3,'cipher_version',1,'nonce_hex',repeat('00',24),'ciphertext_hex',repeat('00',20));
r := public.apply_sync_batch(v,jsonb_build_array(m));
if r->0->>'status' <> 'accepted' then raise exception 'initial_offline_revision_rejected'; end if;
r := public.apply_sync_batch(v,jsonb_build_array(m));
if r->0->>'idempotent_replay' <> 'true' then raise exception 'replay_not_idempotent'; end if;
m := m || jsonb_build_object('operation_id',gen_random_uuid(),'expected_revision',3,'new_revision',7,'nonce_hex',repeat('01',24));
r := public.apply_sync_batch(v,jsonb_build_array(m));
if r->0->>'status' <> 'accepted' then raise exception 'coalesced_revision_rejected'; end if;
r := public.apply_sync_batch(v,jsonb_build_array(m || jsonb_build_object('new_revision',8)));
if r->0->>'status' <> 'conflict' then raise exception 'stale_write_not_rejected'; end if;
if (select count(*) from public.sync_records where vault_id=v) <> 1 then raise exception 'duplicate_created'; end if;
perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
begin
perform public.apply_sync_batch(v,jsonb_build_array(m));
raise exception 'cross_account_access_allowed';
exception when insufficient_privilege then null;
end;
end;
$test$;
rollback;
