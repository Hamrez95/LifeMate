begin;

create or replace function security.activate_retention_policy_idempotent(
  p_actor_account_id uuid,
  p_data_category character varying,
  p_purpose_code character varying,
  p_retention_days integer,
  p_grace_days integer,
  p_disposition character varying,
  p_legal_basis character varying,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=security,admin,pg_temp
as $$
declare
  v_operation constant character varying(120):='retention.policy.activate';
  v_existing admin.idempotency_keys%rowtype;
  v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_response:=security.activate_retention_policy(
    p_actor_account_id,p_data_category,p_purpose_code,p_retention_days,p_grace_days,
    p_disposition,p_legal_basis,p_reason,p_correlation_id
  ) || jsonb_build_object('replayed',false);

  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,
    response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function security.create_retention_hold_idempotent(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_data_category character varying,
  p_purpose_code character varying,
  p_reason_code character varying,
  p_reason character varying,
  p_expires_at_utc timestamptz,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=security,admin,pg_temp
as $$
declare
  v_operation constant character varying(120):='retention.hold.create';
  v_existing admin.idempotency_keys%rowtype;
  v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_response:=security.create_retention_hold(
    p_actor_account_id,p_account_id,p_data_category,p_purpose_code,p_reason_code,
    p_reason,p_expires_at_utc,p_correlation_id
  ) || jsonb_build_object('replayed',false);

  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,
    response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function security.release_retention_hold_idempotent(
  p_actor_account_id uuid,
  p_hold_id uuid,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=security,admin,pg_temp
as $$
declare
  v_operation constant character varying(120):='retention.hold.release';
  v_existing admin.idempotency_keys%rowtype;
  v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_response:=security.release_retention_hold(p_actor_account_id,p_hold_id,p_reason,p_correlation_id)
    || jsonb_build_object('replayed',false);

  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,
    response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function security.activate_retention_policy_idempotent(uuid,character varying,character varying,integer,integer,character varying,character varying,character varying,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function security.create_retention_hold_idempotent(uuid,uuid,character varying,character varying,character varying,character varying,timestamptz,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function security.release_retention_hold_idempotent(uuid,uuid,character varying,uuid,character varying,character varying) from public,anon,authenticated;
grant execute on function security.activate_retention_policy_idempotent(uuid,character varying,character varying,integer,integer,character varying,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function security.create_retention_hold_idempotent(uuid,uuid,character varying,character varying,character varying,character varying,timestamptz,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function security.release_retention_hold_idempotent(uuid,uuid,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

commit;
