begin;

create or replace function admin.open_reconciliation_case_idempotent(
  p_actor_account_id uuid,
  p_transaction_id uuid,
  p_case_type character varying,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,commerce,pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.reconciliation.open';
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
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was used for another reconciliation request.');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching reconciliation request is still processing.');
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_result:=admin.open_reconciliation_case(
    p_actor_account_id,p_transaction_id,p_case_type,p_reason,p_correlation_id
  );
  update admin.idempotency_keys
  set status='Completed',response_status=coalesce((v_result->>'httpStatus')::integer,500),
      response_json=v_result||jsonb_build_object('replayed',false),updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result||jsonb_build_object('replayed',false);
end
$$;

create or replace function admin.apply_approved_transaction_correction_idempotent(
  p_actor_account_id uuid,
  p_case_id uuid,
  p_correction_type character varying,
  p_corrected_status character varying,
  p_annotation_code character varying,
  p_reason character varying,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,commerce,pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.reconciliation.correct';
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
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was used for another correction.');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching correction is still processing.');
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_result:=admin.apply_approved_transaction_correction(
    p_actor_account_id,p_case_id,p_correction_type,p_corrected_status,p_annotation_code,p_reason,
    p_approval_request_id,p_approval_expected_version,p_correlation_id
  );
  update admin.idempotency_keys
  set status='Completed',response_status=coalesce((v_result->>'httpStatus')::integer,500),
      response_json=v_result||jsonb_build_object('replayed',false),updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result||jsonb_build_object('replayed',false);
end
$$;

create or replace function commerce.set_subscription_renewal_intent_v2(
  p_actor_account_id uuid,
  p_actor_type character varying,
  p_subscription_id uuid,
  p_expected_version bigint,
  p_cancel_at_period_end boolean,
  p_reason_code character varying,
  p_reason_text character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,pg_temp
as $$
declare
  v_operation character varying(160):='commerce.subscription.renewal_intent:'||p_subscription_id::text;
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
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was used for another renewal intent.');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching renewal intent is still processing.');
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_result:=commerce.set_subscription_renewal_intent(
    p_actor_account_id,p_actor_type,p_subscription_id,p_expected_version,p_cancel_at_period_end,
    p_reason_code,p_reason_text,p_correlation_id,p_idempotency_key
  );
  update admin.idempotency_keys
  set status='Completed',response_status=coalesce((v_result->>'httpStatus')::integer,500),
      response_json=v_result||jsonb_build_object('replayed',false),updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result||jsonb_build_object('replayed',false);
end
$$;

revoke all on function admin.open_reconciliation_case(uuid,uuid,character varying,character varying,uuid) from lifemate_admin_runtime;
revoke all on function admin.apply_approved_transaction_correction(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid) from lifemate_admin_runtime;
revoke all on function commerce.set_subscription_renewal_intent(uuid,character varying,uuid,bigint,boolean,character varying,character varying,uuid,character varying) from lifemate_admin_runtime,lifemate_edge_runtime;

revoke all on function admin.open_reconciliation_case_idempotent(uuid,uuid,character varying,character varying,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function admin.apply_approved_transaction_correction_idempotent(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function commerce.set_subscription_renewal_intent_v2(uuid,character varying,uuid,bigint,boolean,character varying,character varying,uuid,character varying,character varying) from public,anon,authenticated;

grant execute on function admin.open_reconciliation_case_idempotent(uuid,uuid,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.apply_approved_transaction_correction_idempotent(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function commerce.set_subscription_renewal_intent_v2(uuid,character varying,uuid,bigint,boolean,character varying,character varying,uuid,character varying,character varying) to lifemate_admin_runtime,lifemate_edge_runtime;

commit;
