-- Contract/RLS regression. Everything, including test Auth identities, rolls back.
begin;
select set_config('equis.test.owner', gen_random_uuid()::text, true);
select set_config('equis.test.other', gen_random_uuid()::text, true);
select set_config('equis.test.vault', gen_random_uuid()::text, true);
select set_config('equis.test.device', gen_random_uuid()::text, true);
insert into auth.users(id,aud,role) values(current_setting('equis.test.owner')::uuid,'authenticated','authenticated'),(current_setting('equis.test.other')::uuid,'authenticated','authenticated');
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('equis.test.owner'),true);
do $$
declare
 v uuid := current_setting('equis.test.vault')::uuid;
 d uuid := current_setting('equis.test.device')::uuid;
 fingerprint text := repeat('a',64);
 mutation jsonb;
 result jsonb;
begin
 perform public.register_vault(v,d,fingerprint);
 perform public.register_vault(v,d,fingerprint);
 if (select count(*) from public.vaults where id=v)<>1 then raise exception 'registration duplicated'; end if;
 begin
  perform public.register_vault(v,d,repeat('b',64));
  raise exception 'mismatched key accepted';
 exception when sqlstate 'EVK01' then null; end;
 mutation := jsonb_build_array(jsonb_build_object('operation_id',gen_random_uuid(),'entity_type','tag','record_id',gen_random_uuid(),'expected_revision',null,'new_revision',3,'cipher_version',1,'nonce_hex',repeat('01',24),'ciphertext_hex',repeat('02',40),'is_deleted',false));
 result := public.apply_sync_batch(v,mutation,fingerprint);
 if result->0->>'status'<>'accepted' then raise exception 'initial offline revision failed'; end if;
 result := public.apply_sync_batch(v,mutation,fingerprint);
 if result->0->>'idempotent_replay'<>'true' then raise exception 'replay failed'; end if;
 mutation := jsonb_set(jsonb_set(mutation,'{0,expected_revision}','3'),'{0,new_revision}','7');
 result := public.apply_sync_batch(v,mutation,fingerprint);
 if result->0->>'status'<>'accepted' then raise exception 'offline update failed'; end if;
 begin
  perform public.apply_sync_batch(v,mutation,repeat('b',64));
  raise exception 'wrong key upload accepted';
 exception when sqlstate 'EVK01' then null; end;
 if (select count(*) from public.sync_records where vault_id=v)<>1 then raise exception 'duplicate records'; end if;
 perform public.acknowledge_sync_cursor(v,d,(result->0->>'server_version')::bigint);
 insert into storage.objects(bucket_id,name) values('equis-attachments','vault/'||v::text||'/'||fingerprint||'/attachments/'||gen_random_uuid()::text);
 begin
  insert into storage.objects(bucket_id,name) values('equis-attachments','vault/'||v::text||'/'||repeat('b',64)||'/attachments/'||gen_random_uuid()::text);
  raise exception 'wrong attachment identity accepted';
 exception when insufficient_privilege then null; end;
 begin
  update public.vaults set owner_id=current_setting('equis.test.other')::uuid where id=v;
  raise exception 'owner changed directly';
 exception when insufficient_privilege then null; end;
 begin
  perform public.create_equis_vault(gen_random_uuid(),gen_random_uuid(),null);
  raise exception 'legacy client accepted';
 exception when sqlstate 'EVP01' then null; end;
 perform set_config('request.jwt.claim.sub',current_setting('equis.test.other'),true);
 if exists(select 1 from public.vaults where id=v) or exists(select 1 from public.sync_records where vault_id=v) then raise exception 'cross-account read'; end if;
 if exists(select 1 from storage.objects where bucket_id='equis-attachments' and name like 'vault/'||v::text||'/%') then raise exception 'cross-account attachment read'; end if;
 begin
  perform public.register_vault(v,gen_random_uuid(),fingerprint);
  raise exception 'vault ownership stolen';
 exception when insufficient_privilege then null; end;
 begin
  perform public.apply_sync_batch(v,mutation,fingerprint);
  raise exception 'cross-account write';
 exception when insufficient_privilege then null; end;
end; $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.register_vault(uuid,uuid,text)','execute') or has_function_privilege('authenticated','equis_private.apply_sync_batch_internal(uuid,jsonb)','execute') then raise exception 'unexpected RPC grants'; end if;
end; $$;
rollback;
