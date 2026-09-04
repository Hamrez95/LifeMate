begin;

insert into admin.roles(code,display_name,rank,status,is_system) values
('sales','Sales',125,'Active',true)
on conflict(code) do update set
  display_name=excluded.display_name,
  status=case when admin.roles.status='Disabled' then admin.roles.status else 'Active' end,
  is_system=true,
  updated_at_utc=now();

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('commerce.entitlement.adjust.read','commerce','SENSITIVE',true,'Read manual entitlement adjustment history'),
('commerce.entitlement.adjust.request','commerce','HIGH_RISK',true,'Request manual entitlement Grant/Extend/Reduce/Revoke'),
('commerce.entitlement.adjust.approve','commerce','HIGH_RISK',true,'Approve manual entitlement adjustments'),
('commerce.entitlement.adjust.execute','commerce','HIGH_RISK',true,'Execute approved manual entitlement adjustments')
on conflict(code) do update set
  domain=excluded.domain,risk_level=excluded.risk_level,role_assignable=excluded.role_assignable,
  description=excluded.description,updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.permission_code
from admin.roles r
join (values
  ('support','commerce.entitlement.adjust.read'),('support','commerce.entitlement.adjust.request'),
  ('sales','commerce.entitlement.adjust.read'),('sales','commerce.entitlement.adjust.request'),
  ('sales','commerce.entitlement.adjust.approve'),('sales','commerce.entitlement.adjust.execute'),
  ('founder','commerce.entitlement.adjust.read'),('founder','commerce.entitlement.adjust.request'),
  ('founder','commerce.entitlement.adjust.approve'),('founder','commerce.entitlement.adjust.execute'),
  ('super_admin','commerce.entitlement.adjust.read'),('super_admin','commerce.entitlement.adjust.request'),
  ('super_admin','commerce.entitlement.adjust.execute')
) p(role_code,permission_code) on p.role_code=r.code
on conflict do nothing;

insert into admin.approval_policies(
  request_type,display_name,request_permission,approval_permission,execution_permission,
  self_approval_allowed,default_expiry_minutes,status,version
) values(
  'manual_entitlement_adjustment','Manual entitlement adjustment',
  'commerce.entitlement.adjust.request','commerce.entitlement.adjust.approve','commerce.entitlement.adjust.execute',
  false,1440,'Active',1
)
on conflict(request_type) do update set
  display_name=excluded.display_name,
  request_permission=excluded.request_permission,
  approval_permission=excluded.approval_permission,
  execution_permission=excluded.execution_permission,
  self_approval_allowed=false,
  status='Active',
  updated_at_utc=now();

insert into admin.approval_policy_approver_roles(request_type,role_code) values
('manual_entitlement_adjustment','sales'),
('manual_entitlement_adjustment','founder')
on conflict do nothing;

alter table commerce.entitlements
  add column if not exists version bigint not null default 1 check(version>=1);

alter table commerce.entitlement_events
  drop constraint if exists entitlement_events_event_type_check;
alter table commerce.entitlement_events
  add constraint entitlement_events_event_type_check
  check(event_type in ('Granted','Renewed','Adjusted','Expired','Cancelled','Revoked','Refunded','Chargeback','TrialStarted','TrialConverted'));

create table if not exists commerce.manual_entitlement_adjustments(
  id uuid primary key default gen_random_uuid(),
  subject_account_id uuid not null references identity.accounts(id) on delete restrict,
  target_type character varying(16) not null check(target_type in ('Product','Offer')),
  target_id uuid not null,
  entitlement_id uuid references commerce.entitlements(id) on delete restrict,
  operation character varying(16) not null check(operation in ('Grant','Extend','Reduce','Revoke')),
  schedule_mode character varying(24) not null check(schedule_mode in ('ExactExpiry','AddDays','AddMonths','Immediate')),
  schedule_amount integer,
  exact_expires_at_utc timestamptz,
  reference_at_utc timestamptz not null,
  affected_entitlement_ids uuid[] not null default '{}'::uuid[],
  before_json jsonb not null check(jsonb_typeof(before_json)='object' and octet_length(before_json::text)<=32768),
  after_json jsonb not null check(jsonb_typeof(after_json)='object' and octet_length(after_json::text)<=32768),
  approval_request_id uuid references admin.approval_requests(id) on delete restrict,
  abuse_decision_id uuid references security.abuse_decisions(id) on delete restrict,
  actor_account_id uuid not null,
  reason character varying(1000) not null check(length(trim(reason)) between 10 and 1000),
  correlation_id uuid not null,
  idempotency_key character varying(180) not null,
  request_hash character varying(128) not null,
  created_at_utc timestamptz not null default now(),
  unique(actor_account_id,idempotency_key)
);
create index if not exists ix_manual_entitlement_adjustments_subject
  on commerce.manual_entitlement_adjustments(subject_account_id,created_at_utc desc,id desc);

alter table commerce.manual_entitlement_adjustments enable row level security;
alter table commerce.manual_entitlement_adjustments force row level security;
revoke all on commerce.manual_entitlement_adjustments from public,anon,authenticated;
grant select,insert on commerce.manual_entitlement_adjustments to lifemate_admin_runtime;
drop policy if exists manual_entitlement_adjustments_admin_read on commerce.manual_entitlement_adjustments;
drop policy if exists manual_entitlement_adjustments_admin_insert on commerce.manual_entitlement_adjustments;
create policy manual_entitlement_adjustments_admin_read on commerce.manual_entitlement_adjustments
  for select to lifemate_admin_runtime using(true);
create policy manual_entitlement_adjustments_admin_insert on commerce.manual_entitlement_adjustments
  for insert to lifemate_admin_runtime with check(true);

create or replace function admin.account_has_active_role(
  p_account_id uuid,p_role_code character varying,p_at timestamptz default now()
) returns boolean
language sql stable
set search_path=admin,pg_temp
as $$
  select exists(
    select 1 from admin.members m
    join admin.member_roles mr on mr.account_id=m.account_id
    join admin.roles r on r.id=mr.role_id
    where m.account_id=p_account_id and m.status='Active' and r.status='Active'
      and r.code=p_role_code and mr.revoked_at_utc is null and mr.starts_at_utc<=p_at
      and (mr.expires_at_utc is null or mr.expires_at_utc>p_at)
  )
$$;

create or replace function commerce.manual_adjustment_target_features(
  p_target_type character varying,p_target_id uuid
) returns table(feature_id uuid)
language sql stable
set search_path=commerce,pg_temp
as $$
  select pf.feature_id from commerce.product_features pf
  where p_target_type='Product' and pf.product_id=p_target_id
  union
  select oe.feature_id from commerce.offer_entitlements oe
  where p_target_type='Offer' and oe.offer_id=p_target_id
$$;

create or replace function commerce.manual_adjustment_self_person(p_account_id uuid)
returns uuid
language sql stable
set search_path=core,pg_temp
as $$
  select l.person_id from core.account_person_links l
  where l.account_id=p_account_id and l.link_type='Self' and l.status='Active'
  order by l.created_at_utc,l.person_id limit 1
$$;

create or replace function commerce.preview_manual_entitlement_adjustment(
  p_subject_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_entitlement_id uuid,
  p_expected_entitlement_version bigint,
  p_operation character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz,
  p_reference_at_utc timestamptz
) returns jsonb
language plpgsql stable
set search_path=commerce,identity,core,pg_temp
as $$
declare
  v_operation character varying(16):=initcap(lower(trim(coalesce(p_operation,''))));
  v_target_type character varying(16):=initcap(lower(trim(coalesce(p_target_type,''))));
  v_mode character varying(24):=initcap(lower(trim(coalesce(p_schedule_mode,''))));
  v_reference timestamptz:=coalesce(p_reference_at_utc,now());
  v_ent commerce.entitlements%rowtype;
  v_self_person uuid;
  v_features uuid[];
  v_current_expiry timestamptz;
  v_effective_expiry timestamptz;
  v_before jsonb;
  v_after jsonb;
begin
  if v_target_type not in ('Product','Offer') or v_operation not in ('Grant','Extend','Reduce','Revoke')
     or v_mode not in ('ExactExpiry','AddDays','AddMonths','Immediate') then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjustment_invalid','message','Adjustment type is invalid.');
  end if;
  if not exists(select 1 from identity.accounts where id=p_subject_account_id and status='Active') then
    return jsonb_build_object('httpStatus',404,'code','entitlement_subject_not_found','message','Target account is not active.');
  end if;
  select array_agg(feature_id order by feature_id) into v_features
  from commerce.manual_adjustment_target_features(v_target_type,p_target_id);
  if coalesce(cardinality(v_features),0)=0 then
    return jsonb_build_object('httpStatus',404,'code','entitlement_target_not_found','message','Product or offer has no canonical feature mapping.');
  end if;

  if v_operation='Grant' then
    if p_entitlement_id is not null or p_expected_entitlement_version is not null then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_existing_invalid','message','Grant does not accept an existing entitlement.');
    end if;
    if v_mode='Immediate' then
      return jsonb_build_object('httpStatus',400,'code','entitlement_grant_schedule_invalid','message','Grant requires ExactExpiry, AddDays or AddMonths.');
    end if;
    if v_mode='ExactExpiry' then
      if p_exact_expires_at_utc is null or p_exact_expires_at_utc<=v_reference then
        return jsonb_build_object('httpStatus',400,'code','entitlement_expiry_invalid','message','Exact expiry must be after reference time.');
      end if;
      v_effective_expiry:=p_exact_expires_at_utc;
    elsif v_mode='AddDays' then
      if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>3650 then
        return jsonb_build_object('httpStatus',400,'code','entitlement_days_invalid','message','AddDays amount is invalid.');
      end if;
      v_effective_expiry:=v_reference+make_interval(days=>p_schedule_amount);
    else
      if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>120 then
        return jsonb_build_object('httpStatus',400,'code','entitlement_months_invalid','message','AddMonths amount is invalid.');
      end if;
      v_effective_expiry:=v_reference+make_interval(months=>p_schedule_amount);
    end if;
    v_before:=jsonb_build_object('subjectAccountId',p_subject_account_id,'targetType',v_target_type,'targetId',p_target_id,'entitlementId',null);
    v_after:=jsonb_build_object('status','Active','featureIds',to_jsonb(v_features),'expiresAtUtc',v_effective_expiry);
  else
    if p_entitlement_id is null or p_expected_entitlement_version is null or p_expected_entitlement_version<1 then
      return jsonb_build_object('httpStatus',400,'code','entitlement_version_required','message','Existing adjustments require entitlementId and expectedEntitlementVersion.');
    end if;
    v_self_person:=commerce.manual_adjustment_self_person(p_subject_account_id);
    select * into v_ent from commerce.entitlements e
    where e.id=p_entitlement_id
      and (e.grantee_account_id=p_subject_account_id or (v_self_person is not null and e.beneficiary_person_id=v_self_person));
    if not found then
      return jsonb_build_object('httpStatus',404,'code','entitlement_not_found','message','Entitlement was not found for this account.');
    end if;
    if v_ent.version<>p_expected_entitlement_version then
      return jsonb_build_object('httpStatus',409,'code','entitlement_version_conflict','message','Entitlement changed; refresh before adjusting.','currentVersion',v_ent.version);
    end if;
    if v_ent.feature_id<>all(v_features) then
      return jsonb_build_object('httpStatus',409,'code','entitlement_target_mismatch','message','Entitlement feature is not part of the selected product/offer.');
    end if;
    if v_ent.source='FREE' then
      return jsonb_build_object('httpStatus',409,'code','free_entitlement_not_adjustable','message','Free baseline entitlement cannot be manually reduced, extended or revoked.');
    end if;
    if v_ent.status<>'Active' or v_ent.starts_at_utc>v_reference or (v_ent.expires_at_utc is not null and v_ent.expires_at_utc<=v_reference) then
      return jsonb_build_object('httpStatus',409,'code','entitlement_not_active','message','Only an active entitlement can be adjusted.');
    end if;
    v_current_expiry:=v_ent.expires_at_utc;
    if v_operation='Revoke' then
      if v_mode<>'Immediate' then return jsonb_build_object('httpStatus',400,'code','revoke_schedule_invalid','message','Revoke requires Immediate mode.'); end if;
      v_effective_expiry:=v_reference;
    elsif v_operation='Reduce' then
      if v_mode<>'ExactExpiry' or p_exact_expires_at_utc is null or p_exact_expires_at_utc<=v_reference then
        return jsonb_build_object('httpStatus',400,'code','reduce_expiry_invalid','message','Reduce requires a future exact expiry.');
      end if;
      if v_current_expiry is not null and p_exact_expires_at_utc>=v_current_expiry then
        return jsonb_build_object('httpStatus',409,'code','reduce_not_smaller','message','Reduced expiry must be earlier than current expiry.');
      end if;
      v_effective_expiry:=p_exact_expires_at_utc;
    elsif v_operation='Extend' then
      if v_current_expiry is null then return jsonb_build_object('httpStatus',409,'code','entitlement_indefinite','message','An indefinite entitlement cannot be extended.'); end if;
      if v_mode='ExactExpiry' then v_effective_expiry:=p_exact_expires_at_utc;
      elsif v_mode='AddDays' then
        if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>3650 then return jsonb_build_object('httpStatus',400,'code','entitlement_days_invalid','message','AddDays amount is invalid.'); end if;
        v_effective_expiry:=v_current_expiry+make_interval(days=>p_schedule_amount);
      elsif v_mode='AddMonths' then
        if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>120 then return jsonb_build_object('httpStatus',400,'code','entitlement_months_invalid','message','AddMonths amount is invalid.'); end if;
        v_effective_expiry:=v_current_expiry+make_interval(months=>p_schedule_amount);
      else return jsonb_build_object('httpStatus',400,'code','extend_schedule_invalid','message','Extend requires an expiry schedule.'); end if;
      if v_effective_expiry is null or v_effective_expiry<=v_current_expiry then return jsonb_build_object('httpStatus',409,'code','extend_not_larger','message','Extended expiry must be later than current expiry.'); end if;
    else
      return jsonb_build_object('httpStatus',400,'code','operation_invalid','message','Operation is invalid.');
    end if;
    v_before:=jsonb_build_object('entitlementId',v_ent.id,'featureId',v_ent.feature_id,'source',v_ent.source,'status',v_ent.status,'expiresAtUtc',v_ent.expires_at_utc,'version',v_ent.version);
    v_after:=jsonb_build_object('entitlementId',v_ent.id,'featureId',v_ent.feature_id,'status',case when v_operation='Revoke' then 'Revoked' else 'Active' end,'expiresAtUtc',v_effective_expiry,'version',v_ent.version+1);
  end if;

  return jsonb_build_object(
    'httpStatus',200,'code','ok','before',v_before,
    'delta',jsonb_build_object('operation',v_operation,'targetType',v_target_type,'targetId',p_target_id,'scheduleMode',v_mode,'scheduleAmount',p_schedule_amount,'exactExpiresAtUtc',p_exact_expires_at_utc,'referenceAtUtc',v_reference),
    'after',v_after
  );
end $$;

revoke all on function admin.account_has_active_role(uuid,character varying,timestamptz) from public;
revoke all on function commerce.manual_adjustment_target_features(character varying,uuid) from public;
revoke all on function commerce.manual_adjustment_self_person(uuid) from public;
revoke all on function commerce.preview_manual_entitlement_adjustment(uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz) from public;
grant execute on function commerce.preview_manual_entitlement_adjustment(uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz) to lifemate_admin_runtime;

commit;