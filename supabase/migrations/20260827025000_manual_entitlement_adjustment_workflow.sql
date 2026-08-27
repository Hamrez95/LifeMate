begin;

-- #492 Manual Subscription / Entitlement Operations.
-- This extends the existing entitlement/event ledger. Financial subscription,
-- order and payment facts are deliberately not rewritten by this workflow.

insert into admin.roles(code,display_name,rank,status,is_system)
values('sales','Sales',125,'Active',true)
on conflict(code) do update set
  display_name=excluded.display_name,
  status=case when admin.roles.status='Disabled' then admin.roles.status else excluded.status end,
  updated_at_utc=now();

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('commerce.entitlement.adjust.read','commerce','SENSITIVE',true,'Read manual entitlement adjustment history and approval linkage'),
('commerce.entitlement.adjust.request','commerce','HIGH_RISK',true,'Request a manual entitlement grant, extension, reduction or revoke'),
('commerce.entitlement.adjust.approve','commerce','HIGH_RISK',true,'Approve or reject manual entitlement adjustments'),
('commerce.entitlement.adjust.execute','commerce','HIGH_RISK',true,'Execute approved manual entitlement adjustments; Founder may execute directly under explicit permission')
on conflict(code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values
  ('commerce.entitlement.adjust.read'),
  ('commerce.entitlement.adjust.request')
) p(code)
where r.code='support'
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values
  ('commerce.read'),
  ('commerce.entitlement.adjust.read'),
  ('commerce.entitlement.adjust.request'),
  ('commerce.entitlement.adjust.approve'),
  ('commerce.entitlement.adjust.execute'),
  ('operations.approval.read')
) p(code)
where r.code='sales'
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values
  ('commerce.entitlement.adjust.read'),
  ('commerce.entitlement.adjust.request'),
  ('commerce.entitlement.adjust.approve'),
  ('commerce.entitlement.adjust.execute'),
  ('operations.approval.read')
) p(code)
where r.code in ('founder','super_admin')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'commerce.entitlement.adjust.read'
from admin.roles r
where r.code='finance'
on conflict do nothing;

insert into admin.approval_policies(
  request_type,display_name,request_permission,approval_permission,execution_permission,
  self_approval_allowed,default_expiry_minutes,status,version
) values(
  'manual_entitlement_adjustment','Manual entitlement adjustment',
  'commerce.entitlement.adjust.request','commerce.entitlement.adjust.approve',
  'commerce.entitlement.adjust.execute',false,1440,'Active',1
)
on conflict(request_type) do update set
  display_name=excluded.display_name,
  request_permission=excluded.request_permission,
  approval_permission=excluded.approval_permission,
  execution_permission=excluded.execution_permission,
  self_approval_allowed=false,
  status='Active',
  version=admin.approval_policies.version+1,
  updated_at_utc=now();

insert into admin.approval_policy_approver_roles(request_type,role_code) values
('manual_entitlement_adjustment','sales'),
('manual_entitlement_adjustment','founder'),
('manual_entitlement_adjustment','super_admin')
on conflict do nothing;

alter table commerce.entitlements
  add column if not exists version bigint not null default 1 check (version>=1);

create table if not exists commerce.manual_entitlement_adjustments (
  id uuid primary key default gen_random_uuid(),
  subject_account_id uuid not null references identity.accounts(id) on delete restrict,
  beneficiary_person_id uuid references core.persons(id) on delete restrict,
  entitlement_id uuid references commerce.entitlements(id) on delete restrict,
  feature_id uuid references commerce.features(id) on delete restrict,
  offer_id uuid references commerce.offers(id) on delete restrict,
  operation character varying(16) not null check (operation in ('Grant','Extend','Reduce','Revoke')),
  status character varying(24) not null check (status in ('Executed','Failed')),
  approval_request_id uuid references admin.approval_requests(id) on delete restrict,
  actor_account_id uuid not null,
  reason character varying(1000) not null check (length(trim(reason)) between 10 and 1000),
  before_json jsonb not null default '{}'::jsonb check (jsonb_typeof(before_json)='object' and octet_length(before_json::text)<=8192),
  after_json jsonb not null default '{}'::jsonb check (jsonb_typeof(after_json)='object' and octet_length(after_json::text)<=8192),
  correlation_id uuid not null,
  idempotency_key character varying(180) not null,
  request_hash character varying(128) not null,
  created_at_utc timestamptz not null default now(),
  unique(actor_account_id,idempotency_key)
);
create index if not exists ix_commerce_manual_adjustments_subject
  on commerce.manual_entitlement_adjustments(subject_account_id,created_at_utc desc,id desc);
create index if not exists ix_commerce_manual_adjustments_entitlement
  on commerce.manual_entitlement_adjustments(entitlement_id,created_at_utc desc)
  where entitlement_id is not null;

alter table commerce.manual_entitlement_adjustments enable row level security;
alter table commerce.manual_entitlement_adjustments force row level security;
revoke all on commerce.manual_entitlement_adjustments from public,anon,authenticated;
grant select on commerce.manual_entitlement_adjustments to lifemate_admin_runtime;
create policy manual_entitlement_adjustments_admin_read
  on commerce.manual_entitlement_adjustments for select to lifemate_admin_runtime using (true);

create or replace function commerce.manual_entitlement_actor_may_skip_approval(
  p_actor_account_id uuid,
  p_at timestamptz default now()
) returns boolean
language sql
stable
security definer
set search_path=pg_catalog,admin,pg_temp
as $$
  select admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute',p_at)
     and exists(
       select 1
       from admin.members m
       join admin.member_roles mr on mr.account_id=m.account_id
       join admin.roles r on r.id=mr.role_id
       where m.account_id=p_actor_account_id
         and m.status='Active'
         and r.status='Active'
         and r.code in ('founder','super_admin')
         and mr.revoked_at_utc is null
         and mr.starts_at_utc<=p_at
         and (mr.expires_at_utc is null or mr.expires_at_utc>p_at)
     )
$$;

create or replace function commerce.execute_manual_entitlement_adjustment(
  p_actor_account_id uuid,
  p_subject_account_id uuid,
  p_entitlement_id uuid,
  p_feature_id uuid,
  p_offer_id uuid,
  p_operation character varying,
  p_exact_expires_at_utc timestamptz,
  p_add_days integer,
  p_add_months integer,
  p_reason character varying,
  p_confirmed boolean,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_abuse_decision_id uuid,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,security,identity,core,pg_temp
as $$
declare
  v_operation character varying(16):=initcap(lower(trim(coalesce(p_operation,''))));
  v_existing commerce.manual_entitlement_adjustments%rowtype;
  v_ent commerce.entitlements%rowtype;
  v_before jsonb:='{}'::jsonb;
  v_after jsonb:='{}'::jsonb;
  v_new_expiry timestamptz;
  v_adjustment_id uuid;
  v_approval jsonb;
  v_abuse security.abuse_decisions%rowtype;
  v_feature_id uuid;
  v_event_type character varying(32);
  v_source_key character varying(160);
  v_is_direct_founder boolean;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute') then
    return jsonb_build_object('httpStatus',403,'code','entitlement_adjust_execute_denied','message','Actor cannot execute entitlement adjustments.','replayed',false);
  end if;
  if not exists(select 1 from identity.accounts where id=p_subject_account_id and status<>'Deleted') then
    return jsonb_build_object('httpStatus',404,'code','entitlement_subject_not_found','message','Target account was not found.','replayed',false);
  end if;
  if v_operation not in ('Grant','Extend','Reduce','Revoke') then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_operation_invalid','message','Operation is invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_reason_invalid','message','A bounded reason is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  if v_operation in ('Reduce','Revoke') and coalesce(p_confirmed,false)=false then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_confirmation_required','message','Reduction and revoke require explicit confirmation.','replayed',false);
  end if;
  if (p_add_days is not null and p_add_months is not null)
     or (p_exact_expires_at_utc is not null and (p_add_days is not null or p_add_months is not null))
     or (p_add_days is not null and (p_add_days<1 or p_add_days>3650))
     or (p_add_months is not null and (p_add_months<1 or p_add_months>120)) then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_expiry_invalid','message','Expiry adjustment is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':manual-entitlement:'||p_idempotency_key,0));
  select * into v_existing from commerce.manual_entitlement_adjustments
  where actor_account_id=p_actor_account_id and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was used for a different adjustment.','replayed',false);
    end if;
    return jsonb_build_object(
      'httpStatus',200,'code','ok','adjustmentId',v_existing.id,'entitlementId',v_existing.entitlement_id,
      'operation',v_existing.operation,'status',v_existing.status,'replayed',true
    );
  end if;

  if p_abuse_decision_id is null then
    return jsonb_build_object('httpStatus',400,'code','abuse_decision_required','message','A current abuse-control decision is required.','replayed',false);
  end if;
  select * into v_abuse from security.abuse_decisions where id=p_abuse_decision_id for share;
  if not found or v_abuse.actor_account_id<>p_actor_account_id or v_abuse.subject_account_id<>p_subject_account_id
     or v_abuse.context_code<>'manual_entitlement_adjustment' then
    return jsonb_build_object('httpStatus',409,'code','abuse_decision_mismatch','message','Abuse-control decision does not match this adjustment.','replayed',false);
  end if;
  if v_abuse.final_action='Deny' then
    return jsonb_build_object('httpStatus',403,'code','entitlement_adjust_abuse_denied','message','Adjustment was denied by an explainable abuse rule.','reasonCodes',v_abuse.reason_codes,'replayed',false);
  end if;

  v_is_direct_founder:=commerce.manual_entitlement_actor_may_skip_approval(p_actor_account_id);
  if not v_is_direct_founder or v_abuse.final_action='RequireApproval' then
    if p_approval_request_id is null or p_approval_expected_version is null then
      return jsonb_build_object('httpStatus',409,'code','entitlement_adjust_approval_required','message','An approved manual entitlement request is required.','replayed',false);
    end if;
    v_approval:=admin.consume_approval_request(
      p_actor_account_id,p_approval_request_id,p_approval_expected_version,
      'commerce.entitlement.adjust.'||lower(v_operation),p_correlation_id
    );
    if v_approval->>'requestType'<>'manual_entitlement_adjustment'
       or v_approval->>'targetType'<>'account'
       or v_approval->>'targetId'<>p_subject_account_id::text then
      raise exception using errcode='42501',message='Approval target does not match entitlement adjustment.';
    end if;
  elsif p_approval_request_id is not null then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_unexpected_approval','message','Direct Founder execution must not silently consume an unrelated approval.','replayed',false);
  end if;

  if v_operation='Grant' then
    if p_entitlement_id is not null then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_target_invalid','message','Grant creates a new entitlement and must not include entitlementId.','replayed',false);
    end if;
    if p_feature_id is null and p_offer_id is null then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_feature_required','message','Grant requires a feature or offer target.','replayed',false);
    end if;
    if p_offer_id is not null then
      select oe.feature_id into v_feature_id
      from commerce.offer_entitlements oe join commerce.offers o on o.id=oe.offer_id
      where oe.offer_id=p_offer_id and o.status in ('Published','Hidden')
      order by oe.feature_id limit 1;
      if v_feature_id is null then
        return jsonb_build_object('httpStatus',409,'code','entitlement_offer_has_no_feature','message','Offer has no entitlement feature to grant.','replayed',false);
      end if;
      if (select count(*) from commerce.offer_entitlements where offer_id=p_offer_id)<>1 then
        return jsonb_build_object('httpStatus',409,'code','entitlement_offer_multi_feature_requires_batch','message','Multi-feature offers require the batch grant contract and are not partially granted.','replayed',false);
      end if;
    else
      v_feature_id:=p_feature_id;
      if not exists(select 1 from commerce.features where id=v_feature_id) then
        return jsonb_build_object('httpStatus',404,'code','entitlement_feature_not_found','message','Feature was not found.','replayed',false);
      end if;
    end if;
    if p_exact_expires_at_utc is not null and p_exact_expires_at_utc<=now() then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_expiry_invalid','message','Grant expiry must be in the future.','replayed',false);
    end if;
    v_new_expiry:=coalesce(
      p_exact_expires_at_utc,
      case when p_add_days is not null then now()+make_interval(days=>p_add_days)
           when p_add_months is not null then now()+make_interval(months=>p_add_months)
           else null end
    );
    v_source_key:='manual:'||p_correlation_id::text;
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc,expires_at_utc,version
    ) values(p_subject_account_id,null,v_feature_id,'ADMIN_GRANT',v_source_key,'Active',now(),v_new_expiry,1)
    returning * into v_ent;
    v_before:='{}'::jsonb;
    v_event_type:='Granted';
  else
    if p_entitlement_id is null then
      return jsonb_build_object('httpStatus',400,'code','entitlement_id_required','message','Existing entitlementId is required.','replayed',false);
    end if;
    select * into v_ent from commerce.entitlements where id=p_entitlement_id for update;
    if not found then
      return jsonb_build_object('httpStatus',404,'code','entitlement_not_found','message','Entitlement was not found.','replayed',false);
    end if;
    if v_ent.grantee_account_id is distinct from p_subject_account_id then
      return jsonb_build_object('httpStatus',409,'code','entitlement_subject_mismatch','message','Entitlement does not belong to the target account.','replayed',false);
    end if;
    v_before:=jsonb_build_object('status',v_ent.status,'expiresAtUtc',v_ent.expires_at_utc,'version',v_ent.version,'featureId',v_ent.feature_id);
    if v_operation='Revoke' then
      if v_ent.status='Revoked' then
        return jsonb_build_object('httpStatus',409,'code','entitlement_already_revoked','message','Entitlement is already revoked.','replayed',false);
      end if;
      update commerce.entitlements set status='Revoked',version=version+1,updated_at_utc=now() where id=v_ent.id returning * into v_ent;
      v_event_type:='Revoked';
    else
      if v_ent.status<>'Active' then
        return jsonb_build_object('httpStatus',409,'code','entitlement_not_active','message','Only active entitlements can be extended or reduced.','replayed',false);
      end if;
      if p_exact_expires_at_utc is null and p_add_days is null and p_add_months is null then
        return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_expiry_required','message','Extend or Reduce requires an expiry change.','replayed',false);
      end if;
      v_new_expiry:=coalesce(
        p_exact_expires_at_utc,
        case
          when p_add_days is not null then coalesce(v_ent.expires_at_utc,now())+make_interval(days=>p_add_days)
          when p_add_months is not null then coalesce(v_ent.expires_at_utc,now())+make_interval(months=>p_add_months)
        end
      );
      if v_operation='Extend' and v_ent.expires_at_utc is not null and v_new_expiry<=v_ent.expires_at_utc then
        return jsonb_build_object('httpStatus',400,'code','entitlement_extend_not_later','message','Extended expiry must be later than current expiry.','replayed',false);
      end if;
      if v_operation='Reduce' and (v_ent.expires_at_utc is null or v_new_expiry>=v_ent.expires_at_utc or v_new_expiry<=now()) then
        return jsonb_build_object('httpStatus',400,'code','entitlement_reduce_invalid','message','Reduced expiry must remain in the future and be earlier than current expiry.','replayed',false);
      end if;
      update commerce.entitlements set expires_at_utc=v_new_expiry,version=version+1,updated_at_utc=now() where id=v_ent.id returning * into v_ent;
      v_event_type:='Renewed';
    end if;
  end if;

  v_after:=jsonb_build_object('status',v_ent.status,'expiresAtUtc',v_ent.expires_at_utc,'version',v_ent.version,'featureId',v_ent.feature_id);
  insert into commerce.entitlement_events(entitlement_id,event_type,provider_event_key,occurred_at_utc,metadata_json)
  values(v_ent.id,v_event_type,'manual-adjustment:'||p_actor_account_id::text||':'||p_idempotency_key,now(),
    jsonb_build_object('operation',v_operation,'correlationId',p_correlation_id,'approvalRequestId',p_approval_request_id,'abuseDecisionId',p_abuse_decision_id));

  insert into commerce.manual_entitlement_adjustments(
    subject_account_id,beneficiary_person_id,entitlement_id,feature_id,offer_id,operation,status,
    approval_request_id,actor_account_id,reason,before_json,after_json,correlation_id,idempotency_key,request_hash
  ) values(
    p_subject_account_id,v_ent.beneficiary_person_id,v_ent.id,v_ent.feature_id,p_offer_id,v_operation,'Executed',
    p_approval_request_id,p_actor_account_id,trim(p_reason),v_before,v_after,p_correlation_id,p_idempotency_key,p_request_hash
  ) returning id into v_adjustment_id;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,'commerce.entitlement.adjust.'||lower(v_operation),'entitlement',v_ent.id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('adjustmentId',v_adjustment_id,'subjectAccountId',p_subject_account_id,'operation',v_operation,'approvalRequestId',p_approval_request_id,'abuseDecisionId',p_abuse_decision_id));

  perform security.record_abuse_event(p_subject_account_id,'manual_entitlement_adjustment',p_idempotency_key,'executed');

  return jsonb_build_object(
    'httpStatus',case when v_operation='Grant' then 201 else 200 end,'code','ok','adjustmentId',v_adjustment_id,
    'entitlementId',v_ent.id,'operation',v_operation,'status',v_ent.status,'expiresAtUtc',v_ent.expires_at_utc,
    'version',v_ent.version,'replayed',false
  );
exception
  when unique_violation then
    raise;
end $$;

revoke all on function commerce.manual_entitlement_actor_may_skip_approval(uuid,timestamptz) from public,anon,authenticated;
revoke all on function commerce.execute_manual_entitlement_adjustment(uuid,uuid,uuid,uuid,uuid,character varying,timestamptz,integer,integer,character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying) from public,anon,authenticated;
grant execute on function commerce.manual_entitlement_actor_may_skip_approval(uuid,timestamptz) to lifemate_admin_runtime;
grant execute on function commerce.execute_manual_entitlement_adjustment(uuid,uuid,uuid,uuid,uuid,character varying,timestamptz,integer,integer,character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying) to lifemate_admin_runtime;

comment on table commerce.manual_entitlement_adjustments is 'Immutable business ledger for manual entitlement operations. It does not rewrite payment/order/subscription history.';
comment on function commerce.execute_manual_entitlement_adjustment(uuid,uuid,uuid,uuid,uuid,character varying,timestamptz,integer,integer,character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying) is 'Executes one manual entitlement mutation. Non-Founder execution consumes an approved #491 request in the same transaction.';

commit;
