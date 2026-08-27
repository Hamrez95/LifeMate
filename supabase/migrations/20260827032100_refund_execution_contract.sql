begin;

create or replace function admin.request_commerce_refund_v2(
  p_actor_account_id uuid,
  p_transaction_id uuid,
  p_amount_minor bigint,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,commerce,security,pg_temp
as $$
declare
  v_operation constant character varying:='commerce.refund.request.v2';
  v_existing admin.idempotency_keys%rowtype;
  v_tx commerce.transactions%rowtype;
  v_remaining bigint;
  v_request_id uuid;
  v_approval jsonb;
  v_abuse jsonb;
  v_before jsonb;
  v_delta jsonb;
  v_after jsonb;
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.refund.request') then
    return jsonb_build_object('httpStatus',403,'code','refund_request_denied','message','Actor cannot request refunds.');
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','refund_request_invalid','message','Refund request metadata is invalid.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was used for another refund request.'); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching refund request is still processing.');
  end if;

  select * into v_tx from commerce.transactions where id=p_transaction_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','commerce_transaction_not_found','message','Transaction was not found.'); end if;
  if v_tx.normalized_status<>'Succeeded' then return jsonb_build_object('httpStatus',409,'code','refund_not_eligible','message','Only a succeeded payment transaction can be refunded.'); end if;
  if v_tx.account_id is null then return jsonb_build_object('httpStatus',409,'code','refund_account_unlinked','message','Transaction must be reconciled to an account before refund review.'); end if;

  select greatest(v_tx.amount_minor-coalesce(sum(ro.amount_minor) filter(where ro.status='Succeeded'),0),0)
  into v_remaining from commerce.refund_operations ro where ro.transaction_id=v_tx.id;
  if p_amount_minor is null or p_amount_minor<1 or p_amount_minor>v_remaining then
    return jsonb_build_object('httpStatus',409,'code','refund_amount_invalid','message','Requested refund exceeds remaining refundable amount.','remainingRefundableMinor',v_remaining::text,'currency',v_tx.currency);
  end if;
  if exists(select 1 from commerce.refund_requests rr where rr.transaction_id=v_tx.id and rr.status in ('PendingReview','Approved','Submitted')) then
    return jsonb_build_object('httpStatus',409,'code','refund_workflow_already_active','message','An active refund workflow already exists for this transaction.');
  end if;

  v_abuse:=security.evaluate_abuse_rules(
    p_actor_account_id,v_tx.account_id,'refund.request',v_tx.id::text,'{}'::varchar[],
    'refund-request:'||p_idempotency_key,p_request_hash
  );
  if coalesce((v_abuse->>'httpStatus')::integer,500)>=400 then return v_abuse; end if;
  if v_abuse->>'action'='Deny' then return jsonb_build_object('httpStatus',403,'code','refund_abuse_denied','message','Refund was denied by an explainable abuse rule.','reasonCodes',v_abuse->'reasonCodes'); end if;
  if v_abuse->>'action'='RequireApproval' and coalesce(v_abuse->>'approvalRequestType','commerce_refund_execution')<>'commerce_refund_execution' then
    return jsonb_build_object('httpStatus',409,'code','refund_approval_policy_mismatch','message','Abuse rule requires an incompatible approval policy.');
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  insert into commerce.refund_requests(
    transaction_id,requested_by_account_id,status,amount_minor,currency,reason,version
  ) values(v_tx.id,p_actor_account_id,'PendingReview',p_amount_minor,v_tx.currency,trim(p_reason),1)
  returning id into v_request_id;

  v_before:=jsonb_build_object('transactionId',v_tx.id,'status',v_tx.normalized_status,'remainingRefundableMinor',v_remaining::text,'currency',v_tx.currency);
  v_delta:=jsonb_build_object('refundRequestId',v_request_id,'amountMinor',p_amount_minor::text,'currency',v_tx.currency,'reason',trim(p_reason));
  v_after:=jsonb_build_object('refundRequestId',v_request_id,'status','PendingReview','remainingAfterSuccessMinor',(v_remaining-p_amount_minor)::text,'currency',v_tx.currency);
  v_approval:=admin.create_approval_request(
    p_actor_account_id,'commerce_refund_execution','commerce_refund',v_request_id::text,
    v_before,v_delta,v_after,trim(p_reason),p_correlation_id,p_idempotency_key,p_request_hash
  );
  if coalesce((v_approval->>'httpStatus')::integer,500)>=400 then
    raise exception using errcode='22023',message='Refund approval request could not be created.';
  end if;
  update commerce.refund_requests set approval_request_id=(v_approval->>'id')::uuid,updated_at_utc=now() where id=v_request_id;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,'commerce.refund.request.v2','refund_request',v_request_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('transactionId',v_tx.id,'amountMinor',p_amount_minor::text,'currency',v_tx.currency,'approvalRequestId',v_approval->>'id','abuseDecisionId',v_abuse->>'decisionId'));
  v_result:=jsonb_build_object('httpStatus',201,'code','ok','refundRequestId',v_request_id,'approvalRequestId',v_approval->>'id','status','PendingReview','amountMinor',p_amount_minor::text,'currency',v_tx.currency,'remainingRefundableMinor',v_remaining::text,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=201,response_json=v_result,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result;
end $$;

create or replace function admin.submit_approved_commerce_refund(
  p_actor_account_id uuid,
  p_refund_request_id uuid,
  p_expected_refund_version bigint,
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
  v_operation constant character varying:='commerce.refund.execute';
  v_existing admin.idempotency_keys%rowtype;
  v_request commerce.refund_requests%rowtype;
  v_tx commerce.transactions%rowtype;
  v_remaining bigint;
  v_before jsonb;
  v_delta jsonb;
  v_after jsonb;
  v_approval jsonb;
  v_operation_id uuid;
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.refund.execute') then return jsonb_build_object('httpStatus',403,'code','refund_execute_denied','message','Actor cannot submit refunds.'); end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180 or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','refund_execute_invalid','message','Refund execution metadata is invalid.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was used for another refund execution.'); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching refund execution is still processing.');
  end if;

  select * into v_request from commerce.refund_requests where id=p_refund_request_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','refund_request_not_found','message','Refund request was not found.'); end if;
  if v_request.version<>p_expected_refund_version then return jsonb_build_object('httpStatus',409,'code','refund_version_conflict','message','Refund request changed; refresh before execution.','currentVersion',v_request.version); end if;
  if v_request.status<>'PendingReview' then return jsonb_build_object('httpStatus',409,'code','refund_request_not_pending','message','Only PendingReview requests may be submitted.'); end if;
  select * into v_tx from commerce.transactions where id=v_request.transaction_id for update;
  select greatest(v_tx.amount_minor-coalesce(sum(ro.amount_minor) filter(where ro.status='Succeeded'),0),0)
  into v_remaining from commerce.refund_operations ro where ro.transaction_id=v_tx.id;
  if v_request.amount_minor>v_remaining then return jsonb_build_object('httpStatus',409,'code','refund_remaining_changed','message','Remaining refundable amount changed; create a new request.','remainingRefundableMinor',v_remaining::text); end if;

  v_before:=jsonb_build_object('transactionId',v_tx.id,'status',v_tx.normalized_status,'remainingRefundableMinor',v_remaining::text,'currency',v_tx.currency);
  v_delta:=jsonb_build_object('refundRequestId',v_request.id,'amountMinor',v_request.amount_minor::text,'currency',v_request.currency,'reason',v_request.reason);
  v_after:=jsonb_build_object('refundRequestId',v_request.id,'status','PendingReview','remainingAfterSuccessMinor',(v_remaining-v_request.amount_minor)::text,'currency',v_request.currency);
  if v_request.approval_request_id is null then return jsonb_build_object('httpStatus',409,'code','refund_approval_missing','message','Refund request has no approval workflow.'); end if;
  v_approval:=admin.consume_approval_request(p_actor_account_id,v_request.approval_request_id,p_approval_expected_version,v_operation,p_correlation_id);
  if v_approval->>'requestType'<>'commerce_refund_execution' or v_approval->>'targetType'<>'commerce_refund' or v_approval->>'targetId'<>v_request.id::text
     or v_approval->'before'<>v_before or v_approval->'delta'<>v_delta or v_approval->'after'<>v_after then
    raise exception using errcode='22023',message='Refund approval snapshot no longer matches current financial state.';
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  insert into commerce.refund_operations(
    refund_request_id,transaction_id,provider,amount_minor,currency,status,actor_account_id,
    correlation_id,idempotency_key,request_hash
  ) values(
    v_request.id,v_tx.id,v_tx.provider,v_request.amount_minor,v_request.currency,'PendingProvider',p_actor_account_id,
    p_correlation_id,p_idempotency_key,p_request_hash
  ) returning id into v_operation_id;
  update commerce.refund_requests
  set status='Submitted',reviewed_by_account_id=p_actor_account_id,reviewed_at_utc=now(),version=version+1,updated_at_utc=now()
  where id=v_request.id;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,'commerce.refund.execute','refund_operation',v_operation_id::text,'Succeeded',v_request.reason,p_correlation_id,p_idempotency_key,true,
    jsonb_build_object('refundRequestId',v_request.id,'transactionId',v_tx.id,'amountMinor',v_request.amount_minor::text,'currency',v_request.currency,'providerStatus','PendingProvider'));
  v_result:=jsonb_build_object('httpStatus',202,'code','ok','refundRequestId',v_request.id,'refundOperationId',v_operation_id,'status','PendingProvider','amountMinor',v_request.amount_minor::text,'currency',v_request.currency,'provider',v_tx.provider,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=202,response_json=v_result,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result;
end $$;

create or replace function commerce.record_refund_provider_result(
  p_refund_operation_id uuid,
  p_result character varying,
  p_provider_reference character varying,
  p_provider_error_code character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,extensions,pg_temp
as $$
declare v_op commerce.refund_operations%rowtype; v_result character varying(16):=initcap(lower(trim(coalesce(p_result,''))));
begin
  if v_result not in ('Succeeded','Failed') then return jsonb_build_object('httpStatus',400,'code','provider_result_invalid'); end if;
  select * into v_op from commerce.refund_operations where id=p_refund_operation_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','refund_operation_not_found'); end if;
  if v_op.status in ('Succeeded','Failed') then return jsonb_build_object('httpStatus',200,'code','ok','status',v_op.status,'replayed',true); end if;
  if v_op.status not in ('PendingProvider','Submitted') then return jsonb_build_object('httpStatus',409,'code','refund_operation_state_invalid','status',v_op.status); end if;
  update commerce.refund_operations set
    status=v_result,
    provider_reference_hash=case when p_provider_reference is null then null else encode(extensions.digest(p_provider_reference,'sha256'),'hex') end,
    provider_error_code=case when v_result='Failed' then left(nullif(trim(coalesce(p_provider_error_code,'')),''),120) else null end,
    submitted_at_utc=coalesce(submitted_at_utc,now()),settled_at_utc=now(),updated_at_utc=now()
  where id=v_op.id;
  update commerce.refund_requests set
    status=v_result,updated_at_utc=now(),version=version+1,
    resolution_reason=case when v_result='Failed' then 'Provider execution failed; see privacy-safe provider error code.' else resolution_reason end
  where id=v_op.refund_request_id;
  return jsonb_build_object('httpStatus',200,'code','ok','refundOperationId',v_op.id,'refundRequestId',v_op.refund_request_id,'status',v_result,'replayed',false);
end $$;

revoke all on function admin.request_commerce_refund_v2(uuid,uuid,bigint,character varying,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function admin.submit_approved_commerce_refund(uuid,uuid,bigint,bigint,uuid,character varying,character varying) from public,anon,authenticated;
revoke all on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying) from public,anon,authenticated;
grant execute on function admin.request_commerce_refund_v2(uuid,uuid,bigint,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.submit_approved_commerce_refund(uuid,uuid,bigint,bigint,uuid,character varying,character varying) to lifemate_admin_runtime;
grant execute on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying) to lifemate_worker_runtime;

commit;
