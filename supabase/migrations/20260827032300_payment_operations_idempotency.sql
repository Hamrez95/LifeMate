begin;

alter table commerce.transaction_corrections
  add column if not exists idempotency_key character varying(180),
  add column if not exists request_hash character varying(128);
create unique index if not exists ux_transaction_corrections_actor_idempotency
  on commerce.transaction_corrections(actor_account_id,idempotency_key)
  where idempotency_key is not null;

create or replace function admin.apply_approved_transaction_correction_v2(
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
  v_existing commerce.transaction_corrections%rowtype;
  v_preview jsonb;
  v_approval jsonb;
  v_case commerce.reconciliation_cases%rowtype;
  v_id uuid;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.reconciliation.write') then return jsonb_build_object('httpStatus',403,'code','reconciliation_write_denied'); end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('httpStatus',400,'code','correction_request_invalid'); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':commerce.reconciliation.correct:'||p_idempotency_key,0));
  select * into v_existing from commerce.transaction_corrections where actor_account_id=p_actor_account_id and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict'); end if;
    return jsonb_build_object('httpStatus',200,'code','ok','correctionId',v_existing.id,'caseId',v_existing.reconciliation_case_id,'status','Resolved','replayed',true);
  end if;
  select * into v_case from commerce.reconciliation_cases where id=p_case_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','reconciliation_case_not_found'); end if;
  v_preview:=commerce.preview_transaction_correction(p_case_id,p_correction_type,p_corrected_status,p_annotation_code);
  if coalesce((v_preview->>'httpStatus')::integer,500)>=400 then return v_preview; end if;
  v_approval:=admin.consume_approval_request(p_actor_account_id,p_approval_request_id,p_approval_expected_version,'commerce.reconciliation.correct',p_correlation_id);
  if v_approval->>'requestType'<>'commerce_transaction_correction' or v_approval->>'targetType'<>'reconciliation_case' or v_approval->>'targetId'<>p_case_id::text
     or v_approval->'before'<>v_preview->'before' or v_approval->'delta'<>v_preview->'delta' or v_approval->'after'<>v_preview->'after' then
    raise exception using errcode='22023',message='Correction approval snapshot no longer matches current reconciliation state.';
  end if;
  insert into commerce.transaction_corrections(
    transaction_id,reconciliation_case_id,correction_type,corrected_normalized_status,annotation_code,
    reason,approval_request_id,actor_account_id,correlation_id,idempotency_key,request_hash
  ) values(
    v_case.transaction_id,p_case_id,p_correction_type,p_corrected_status,p_annotation_code,
    trim(p_reason),p_approval_request_id,p_actor_account_id,p_correlation_id,p_idempotency_key,p_request_hash
  ) returning id into v_id;
  update commerce.reconciliation_cases set status='Resolved',resolved_at_utc=now(),updated_at_utc=now() where id=p_case_id;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,'commerce.reconciliation.correct','transaction_correction',v_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,true,jsonb_build_object('caseId',p_case_id,'transactionId',v_case.transaction_id,'correctionType',p_correction_type));
  return jsonb_build_object('httpStatus',200,'code','ok','correctionId',v_id,'caseId',p_case_id,'status','Resolved','replayed',false);
end $$;

create or replace function commerce.set_subscription_renewal_intent(
  p_actor_account_id uuid,
  p_actor_type character varying,
  p_subscription_id uuid,
  p_expected_version bigint,
  p_cancel_at_period_end boolean,
  p_reason_code character varying,
  p_reason_text character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,pg_temp
as $$
declare
  v_sub commerce.subscriptions%rowtype;
  v_actor_type character varying(20):=initcap(lower(trim(coalesce(p_actor_type,''))));
  v_event character varying(24);
  v_existing commerce.subscription_cancellation_events%rowtype;
  v_event_id uuid;
begin
  if v_actor_type not in ('User','Admin') then return jsonb_build_object('httpStatus',400,'code','cancellation_actor_invalid'); end if;
  if p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9._-]{2,79}$' or (p_reason_text is not null and length(p_reason_text)>1000)
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180 then return jsonb_build_object('httpStatus',400,'code','cancellation_request_invalid'); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_subscription_id::text||':'||p_idempotency_key,0));
  select * into v_existing from commerce.subscription_cancellation_events where subscription_id=p_subscription_id and idempotency_key=p_idempotency_key;
  if found then
    select * into v_sub from commerce.subscriptions where id=p_subscription_id;
    return jsonb_build_object('httpStatus',200,'code','ok','subscriptionId',p_subscription_id,'eventId',v_existing.id,'cancelAtPeriodEnd',v_sub.cancel_at_period_end,'version',v_sub.cancellation_version,'entitlementChanged',false,'replayed',true);
  end if;
  select * into v_sub from commerce.subscriptions where id=p_subscription_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','subscription_not_found'); end if;
  if v_actor_type='User' and v_sub.owner_account_id<>p_actor_account_id then return jsonb_build_object('httpStatus',403,'code','subscription_owner_denied'); end if;
  if v_actor_type='Admin' and not admin.account_has_permission(p_actor_account_id,'commerce.churn.write') then return jsonb_build_object('httpStatus',403,'code','churn_write_denied'); end if;
  if v_sub.cancellation_version<>p_expected_version then return jsonb_build_object('httpStatus',409,'code','subscription_cancellation_version_conflict','currentVersion',v_sub.cancellation_version); end if;
  v_event:=case when p_cancel_at_period_end then 'CancelAtPeriodEnd' else 'ResumeRenewal' end;
  update commerce.subscriptions set
    cancel_at_period_end=p_cancel_at_period_end,
    non_renewal_requested_at_utc=case when p_cancel_at_period_end then now() else null end,
    cancellation_reason_code=case when p_cancel_at_period_end then p_reason_code else null end,
    cancellation_reason_text=case when p_cancel_at_period_end then nullif(trim(coalesce(p_reason_text,'')),'') else null end,
    cancellation_version=cancellation_version+1,updated_at_utc=now()
  where id=v_sub.id;
  insert into commerce.subscription_cancellation_events(
    subscription_id,event_type,reason_code,reason_text,actor_account_id,actor_type,correlation_id,idempotency_key
  ) values(v_sub.id,v_event,p_reason_code,nullif(trim(coalesce(p_reason_text,'')),''),p_actor_account_id,v_actor_type,p_correlation_id,p_idempotency_key)
  returning id into v_event_id;
  return jsonb_build_object('httpStatus',200,'code','ok','subscriptionId',v_sub.id,'eventId',v_event_id,'cancelAtPeriodEnd',p_cancel_at_period_end,'currentPeriodEndUtc',v_sub.current_period_end_utc,'entitlementChanged',false,'version',v_sub.cancellation_version+1,'replayed',false);
end $$;

revoke all on function admin.apply_approved_transaction_correction_v2(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid,character varying,character varying) from public,anon,authenticated;
grant execute on function admin.apply_approved_transaction_correction_v2(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid,character varying,character varying) to lifemate_admin_runtime;

commit;
