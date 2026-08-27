begin;

create or replace function admin.open_reconciliation_case(
  p_actor_account_id uuid,
  p_transaction_id uuid,
  p_case_type character varying,
  p_reason character varying,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,commerce,pg_temp
as $$
declare v_case_type character varying(40):=trim(coalesce(p_case_type,'')); v_id uuid;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.reconciliation.write') then
    return jsonb_build_object('httpStatus',403,'code','reconciliation_write_denied');
  end if;
  if v_case_type not in ('MissingProviderEvent','StatusMismatch','AmountMismatch','ReferenceMismatch','ManualReview')
     or p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','reconciliation_case_invalid');
  end if;
  if p_transaction_id is not null and not exists(select 1 from commerce.transactions where id=p_transaction_id) then
    return jsonb_build_object('httpStatus',404,'code','commerce_transaction_not_found');
  end if;
  insert into commerce.reconciliation_cases(transaction_id,case_type,status,source,reason)
  values(p_transaction_id,v_case_type,'Open','Admin',trim(p_reason)) returning id into v_id;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'commerce.reconciliation.open','reconciliation_case',v_id::text,'Succeeded',trim(p_reason),p_correlation_id,true,jsonb_build_object('transactionId',p_transaction_id,'caseType',v_case_type));
  return jsonb_build_object('httpStatus',201,'code','ok','caseId',v_id,'status','Open');
end $$;

create or replace function commerce.preview_transaction_correction(
  p_case_id uuid,
  p_correction_type character varying,
  p_corrected_status character varying,
  p_annotation_code character varying
) returns jsonb
language plpgsql
security definer
stable
set search_path=pg_catalog,commerce,pg_temp
as $$
declare v_case commerce.reconciliation_cases%rowtype; v_tx commerce.transactions%rowtype; v_type character varying(40):=trim(coalesce(p_correction_type,''));
begin
  select * into v_case from commerce.reconciliation_cases where id=p_case_id;
  if not found or v_case.transaction_id is null then return jsonb_build_object('httpStatus',404,'code','reconciliation_case_not_found'); end if;
  if v_case.status not in ('Open','InReview') then return jsonb_build_object('httpStatus',409,'code','reconciliation_case_closed'); end if;
  select * into v_tx from commerce.transactions where id=v_case.transaction_id;
  if v_type='NormalizedStatusClassification' then
    if p_corrected_status not in ('Pending','Succeeded','Failed','Cancelled','Refunded','Chargeback') then return jsonb_build_object('httpStatus',400,'code','corrected_status_invalid'); end if;
    if p_annotation_code is not null then return jsonb_build_object('httpStatus',400,'code','correction_shape_invalid'); end if;
  elsif v_type='ReferenceAnnotation' then
    if p_corrected_status is not null or p_annotation_code is null or p_annotation_code !~ '^[a-z][a-z0-9._-]{2,79}$' then return jsonb_build_object('httpStatus',400,'code','correction_shape_invalid'); end if;
  else return jsonb_build_object('httpStatus',400,'code','correction_type_invalid'); end if;
  return jsonb_build_object(
    'httpStatus',200,'code','ok',
    'before',jsonb_build_object('caseId',v_case.id,'caseStatus',v_case.status,'transactionId',v_tx.id,'providerNormalizedStatus',v_tx.normalized_status),
    'delta',jsonb_build_object('correctionType',v_type,'correctedNormalizedStatus',p_corrected_status,'annotationCode',p_annotation_code),
    'after',jsonb_build_object('caseId',v_case.id,'caseStatus','Resolved','transactionId',v_tx.id,'effectiveNormalizedStatus',coalesce(p_corrected_status,v_tx.normalized_status),'classificationSource','ManualCorrection')
  );
end $$;

create or replace function admin.apply_approved_transaction_correction(
  p_actor_account_id uuid,
  p_case_id uuid,
  p_correction_type character varying,
  p_corrected_status character varying,
  p_annotation_code character varying,
  p_reason character varying,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,commerce,pg_temp
as $$
declare v_preview jsonb; v_approval jsonb; v_case commerce.reconciliation_cases%rowtype; v_id uuid;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.reconciliation.write') then return jsonb_build_object('httpStatus',403,'code','reconciliation_write_denied'); end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then return jsonb_build_object('httpStatus',400,'code','correction_reason_invalid'); end if;
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
    reason,approval_request_id,actor_account_id,correlation_id
  ) values(
    v_case.transaction_id,p_case_id,p_correction_type,p_corrected_status,p_annotation_code,
    trim(p_reason),p_approval_request_id,p_actor_account_id,p_correlation_id
  ) returning id into v_id;
  update commerce.reconciliation_cases set status='Resolved',resolved_at_utc=now(),updated_at_utc=now() where id=p_case_id;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'commerce.reconciliation.correct','transaction_correction',v_id::text,'Succeeded',trim(p_reason),p_correlation_id,true,jsonb_build_object('caseId',p_case_id,'transactionId',v_case.transaction_id,'correctionType',p_correction_type));
  return jsonb_build_object('httpStatus',200,'code','ok','correctionId',v_id,'caseId',p_case_id,'status','Resolved');
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
declare v_sub commerce.subscriptions%rowtype; v_actor_type character varying(20):=initcap(lower(trim(coalesce(p_actor_type,'')))); v_event character varying(24); v_event_id uuid;
begin
  if v_actor_type not in ('User','Admin') then return jsonb_build_object('httpStatus',400,'code','cancellation_actor_invalid'); end if;
  if p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9._-]{2,79}$' or (p_reason_text is not null and length(p_reason_text)>1000)
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180 then return jsonb_build_object('httpStatus',400,'code','cancellation_request_invalid'); end if;
  select * into v_sub from commerce.subscriptions where id=p_subscription_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','subscription_not_found'); end if;
  if v_actor_type='User' and v_sub.owner_account_id<>p_actor_account_id then return jsonb_build_object('httpStatus',403,'code','subscription_owner_denied'); end if;
  if v_actor_type='Admin' and not admin.account_has_permission(p_actor_account_id,'commerce.churn.write') then return jsonb_build_object('httpStatus',403,'code','churn_write_denied'); end if;
  if v_sub.cancellation_version<>p_expected_version then return jsonb_build_object('httpStatus',409,'code','subscription_cancellation_version_conflict','currentVersion',v_sub.cancellation_version); end if;
  if exists(select 1 from commerce.subscription_cancellation_events where subscription_id=v_sub.id and idempotency_key=p_idempotency_key) then
    return jsonb_build_object('httpStatus',200,'code','ok','subscriptionId',v_sub.id,'cancelAtPeriodEnd',v_sub.cancel_at_period_end,'version',v_sub.cancellation_version,'replayed',true);
  end if;
  v_event:=case when p_cancel_at_period_end then 'CancelAtPeriodEnd' else 'ResumeRenewal' end;
  update commerce.subscriptions set
    cancel_at_period_end=p_cancel_at_period_end,
    non_renewal_requested_at_utc=case when p_cancel_at_period_end then now() else null end,
    cancellation_reason_code=case when p_cancel_at_period_end then p_reason_code else null end,
    cancellation_reason_text=case when p_cancel_at_period_end then nullif(trim(coalesce(p_reason_text,'')),'') else null end,
    cancellation_version=cancellation_version+1,
    updated_at_utc=now()
  where id=v_sub.id;
  insert into commerce.subscription_cancellation_events(
    subscription_id,event_type,reason_code,reason_text,actor_account_id,actor_type,correlation_id,idempotency_key
  ) values(v_sub.id,v_event,p_reason_code,nullif(trim(coalesce(p_reason_text,'')),''),p_actor_account_id,v_actor_type,p_correlation_id,p_idempotency_key)
  returning id into v_event_id;
  return jsonb_build_object(
    'httpStatus',200,'code','ok','subscriptionId',v_sub.id,'eventId',v_event_id,
    'cancelAtPeriodEnd',p_cancel_at_period_end,'currentPeriodEndUtc',v_sub.current_period_end_utc,
    'entitlementChanged',false,'version',v_sub.cancellation_version+1,'replayed',false
  );
end $$;

revoke all on function admin.open_reconciliation_case(uuid,uuid,character varying,character varying,uuid) from public,anon,authenticated;
revoke all on function commerce.preview_transaction_correction(uuid,character varying,character varying,character varying) from public,anon,authenticated;
revoke all on function admin.apply_approved_transaction_correction(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid) from public,anon,authenticated;
revoke all on function commerce.set_subscription_renewal_intent(uuid,character varying,uuid,bigint,boolean,character varying,character varying,uuid,character varying) from public,anon,authenticated;
grant execute on function admin.open_reconciliation_case(uuid,uuid,character varying,character varying,uuid) to lifemate_admin_runtime;
grant execute on function commerce.preview_transaction_correction(uuid,character varying,character varying,character varying) to lifemate_admin_runtime;
grant execute on function admin.apply_approved_transaction_correction(uuid,uuid,character varying,character varying,character varying,character varying,uuid,bigint,uuid) to lifemate_admin_runtime;
grant execute on function commerce.set_subscription_renewal_intent(uuid,character varying,uuid,bigint,boolean,character varying,character varying,uuid,character varying) to lifemate_admin_runtime,lifemate_edge_runtime;

commit;
