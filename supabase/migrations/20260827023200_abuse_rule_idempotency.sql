begin;

create or replace function security.upsert_abuse_rule_idempotent(
  p_actor_account_id uuid,
  p_code character varying,
  p_context_code character varying,
  p_display_name character varying,
  p_rule_kind character varying,
  p_subject_scope character varying,
  p_enforcement_action character varying,
  p_window_seconds integer,
  p_max_count integer,
  p_cooldown_seconds integer,
  p_evidence_code character varying,
  p_approval_request_type character varying,
  p_priority integer,
  p_expected_version bigint,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path=security,admin,pg_temp
as $$
declare
  v_operation character varying(160):='security.abuse.rule.upsert';
  v_existing admin.idempotency_keys%rowtype;
  v_result jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
  for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different rule mutation.');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching rule mutation is still processing.');
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_result:=security.upsert_abuse_rule(
    p_actor_account_id,p_code,p_context_code,p_display_name,p_rule_kind,p_subject_scope,p_enforcement_action,
    p_window_seconds,p_max_count,p_cooldown_seconds,p_evidence_code,p_approval_request_type,p_priority,
    p_expected_version,p_reason,p_correlation_id
  );
  if coalesce((v_result->>'httpStatus')::integer,500)<400 then
    update admin.idempotency_keys
    set status='Completed',response_status=(v_result->>'httpStatus')::integer,
        response_json=v_result||jsonb_build_object('replayed',false),updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
    return v_result||jsonb_build_object('replayed',false);
  end if;
  delete from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result||jsonb_build_object('replayed',false);
end $$;

create or replace function security.retire_abuse_rule_idempotent(
  p_actor_account_id uuid,
  p_rule_id uuid,
  p_expected_version bigint,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
set search_path=security,admin,pg_temp
as $$
declare
  v_operation character varying(160):='security.abuse.rule.retire';
  v_existing admin.idempotency_keys%rowtype;
  v_result jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
  for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different retirement.');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching retirement is still processing.');
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_result:=security.retire_abuse_rule(p_actor_account_id,p_rule_id,p_expected_version,p_reason,p_correlation_id);
  if coalesce((v_result->>'httpStatus')::integer,500)<400 then
    update admin.idempotency_keys
    set status='Completed',response_status=(v_result->>'httpStatus')::integer,
        response_json=v_result||jsonb_build_object('replayed',false),updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
    return v_result||jsonb_build_object('replayed',false);
  end if;
  delete from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result||jsonb_build_object('replayed',false);
end $$;

revoke all on function security.upsert_abuse_rule_idempotent(uuid,character varying,character varying,character varying,character varying,character varying,character varying,integer,integer,integer,character varying,character varying,integer,bigint,character varying,uuid,character varying,character varying) from public;
revoke all on function security.retire_abuse_rule_idempotent(uuid,uuid,bigint,character varying,uuid,character varying,character varying) from public;
grant execute on function security.upsert_abuse_rule_idempotent(uuid,character varying,character varying,character varying,character varying,character varying,character varying,integer,integer,integer,character varying,character varying,integer,bigint,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function security.retire_abuse_rule_idempotent(uuid,uuid,bigint,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

commit;
