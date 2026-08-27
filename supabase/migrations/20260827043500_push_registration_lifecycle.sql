begin;

grant usage on schema messaging to lifemate_edge_runtime;

create or replace function messaging.upsert_push_registration(
  p_app_user_id uuid,
  p_product_code varchar,
  p_platform varchar,
  p_provider varchar,
  p_token_hash varchar,
  p_ciphertext_b64 text,
  p_nonce_b64 varchar,
  p_key_version smallint
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,identity,pg_temp
as $$
declare
  v_account_id uuid;
  v_existing messaging.push_registrations%rowtype;
  v_row messaging.push_registrations%rowtype;
  v_cipher bytea;
  v_was_existing boolean:=false;
begin
  v_account_id:=identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account_id is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing','message','Account mapping is unavailable.');
  end if;
  if p_product_code is null or p_product_code !~ '^[a-z0-9][a-z0-9_.:-]{0,63}$'
     or p_platform not in ('Android','iOS','Web')
     or p_provider is null or p_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$'
     or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_nonce_b64 is null or length(p_nonce_b64) not between 16 and 64
     or p_key_version is null or p_key_version not between 1 and 32767
     or p_ciphertext_b64 is null or length(p_ciphertext_b64) not between 24 and 12288 then
    return jsonb_build_object('httpStatus',400,'code','push_registration_invalid','message','Push registration is invalid.');
  end if;
  begin
    v_cipher:=decode(p_ciphertext_b64,'base64');
  exception when others then
    return jsonb_build_object('httpStatus',400,'code','push_registration_invalid','message','Push registration envelope is invalid.');
  end;
  if octet_length(v_cipher) not between 17 and 8192 then
    return jsonb_build_object('httpStatus',400,'code','push_registration_invalid','message','Push registration envelope is invalid.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('messaging.push:'||p_provider||':'||p_token_hash,0));
  select * into v_existing from messaging.push_registrations
  where provider=p_provider and token_hash=p_token_hash for update;
  v_was_existing:=found;
  if v_was_existing and v_existing.account_id<>v_account_id then
    return jsonb_build_object('httpStatus',409,'code','push_token_account_conflict','message','This push token is already bound to another account.');
  end if;

  if v_was_existing then
    update messaging.push_registrations set
      product_code=p_product_code,platform=p_platform,token_ciphertext=v_cipher,
      token_nonce_b64=p_nonce_b64,encryption_key_version=p_key_version,status='Active',
      last_seen_at_utc=now(),updated_at_utc=now()
    where id=v_existing.id returning * into v_row;
  else
    insert into messaging.push_registrations(
      account_id,product_code,platform,provider,token_hash,token_ciphertext,
      token_nonce_b64,encryption_key_version,status,last_seen_at_utc
    ) values(
      v_account_id,p_product_code,p_platform,p_provider,p_token_hash,v_cipher,
      p_nonce_b64,p_key_version,'Active',now()
    ) returning * into v_row;
  end if;

  return jsonb_build_object(
    'httpStatus',case when v_was_existing then 200 else 201 end,
    'code','ok','registrationId',v_row.id,'productCode',v_row.product_code,
    'platform',v_row.platform,'provider',v_row.provider,'status',v_row.status,
    'lastSeenAtUtc',v_row.last_seen_at_utc
  );
end $$;

create or replace function messaging.revoke_push_registration(
  p_app_user_id uuid,
  p_registration_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,identity,pg_temp
as $$
declare
  v_account_id uuid;
  v_row messaging.push_registrations%rowtype;
begin
  v_account_id:=identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account_id is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing','message','Account mapping is unavailable.');
  end if;
  select * into v_row from messaging.push_registrations
  where id=p_registration_id and account_id=v_account_id for update;
  if not found then
    return jsonb_build_object('httpStatus',404,'code','push_registration_not_found','message','Push registration was not found.');
  end if;
  if v_row.status='Revoked' then
    return jsonb_build_object('httpStatus',200,'code','ok','registrationId',v_row.id,'status','Revoked','replayed',true);
  end if;
  update messaging.push_registrations set
    status='Revoked',token_ciphertext='\x'::bytea,token_nonce_b64='AA==',updated_at_utc=now()
  where id=v_row.id;
  return jsonb_build_object('httpStatus',200,'code','ok','registrationId',v_row.id,'status','Revoked','replayed',false);
end $$;

revoke all on function messaging.upsert_push_registration(uuid,varchar,varchar,varchar,varchar,text,varchar,smallint)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_worker_runtime;
revoke all on function messaging.revoke_push_registration(uuid,uuid)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_worker_runtime;
grant execute on function messaging.upsert_push_registration(uuid,varchar,varchar,varchar,varchar,text,varchar,smallint)
  to lifemate_edge_runtime;
grant execute on function messaging.revoke_push_registration(uuid,uuid)
  to lifemate_edge_runtime;

comment on function messaging.upsert_push_registration(uuid,varchar,varchar,varchar,varchar,text,varchar,smallint)
is 'Authenticated user registration boundary. Receives only an authenticated encrypted token envelope; browser roles never receive direct table access.';
comment on function messaging.revoke_push_registration(uuid,uuid)
is 'Owner-only push registration revocation. Ciphertext is retired on revoke so stale tokens cannot be reused by delivery workers.';

commit;
