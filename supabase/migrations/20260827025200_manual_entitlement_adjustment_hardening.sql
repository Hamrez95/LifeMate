begin;

-- Canonical #492 manual entitlement workflow. This migration deliberately extends
-- the existing commerce entitlements/event ledger and #491 approval + #503 abuse
-- foundations. It never rewrites subscription, order, transaction or payment facts.

insert into admin.roles(code,display_name,rank,status,is_system)
values('sales','Sales',125,'Active',true)
on conflict(code) do update set
  display_name=excluded.display_name,
  status=case when admin.roles.status='Disabled' then admin.roles.status else 'Active' end,
  is_system=true,
  updated_at_utc=now();

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('commerce.entitlement.adjust.read','commerce','SENSITIVE',true,'Read manual entitlement adjustment history'),
('commerce.entitlement.adjust.request','commerce','HIGH_RISK',true,'Request a manual entitlement adjustment'),
('commerce.entitlement.adjust.approve','commerce','HIGH_RISK',true,'Approve or reject a manual entitlement adjustment'),
('commerce.entitlement.adjust.execute','commerce','HIGH_RISK',true,'Execute a manual entitlement adjustment under Founder-direct or approved policy')
on conflict(code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.permission_code
from admin.roles r
join (values
  ('support','commerce.entitlement.adjust.read'),
  ('support','commerce.entitlement.adjust.request'),
  ('sales','commerce.entitlement.adjust.read'),
  ('sales','commerce.entitlement.adjust.request'),
  ('sales','commerce.entitlement.adjust.approve'),
  ('sales','commerce.entitlement.adjust.execute'),
  ('founder','commerce.entitlement.adjust.read'),
  ('founder','commerce.entitlement.adjust.request'),
  ('founder','commerce.entitlement.adjust.approve'),
  ('founder','commerce.entitlement.adjust.execute'),
  ('super_admin','commerce.entitlement.adjust.read')
) p(role_code,permission_code) on p.role_code=r.code
on conflict do nothing;

insert into admin.approval_policies(
  request_type,display_name,request_permission,approval_permission,execution_permission,
  self_approval_allowed,default_expiry_minutes,status,version
) values(
  'commerce.entitlement.adjustment','Manual entitlement adjustment',
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
('commerce.entitlement.adjustment','sales'),
('commerce.entitlement.adjustment','founder')
on conflict do nothing;

create table if not exists commerce.entitlement_adjustments (
  id uuid primary key default gen_random_uuid(),
  target_account_id uuid not null references identity.accounts(id) on delete restrict,
  target_type character varying(16) not null check (target_type in ('Product','Offer')),
  target_id uuid not null,
  action character varying(16) not null check (action in ('Grant','Extend','Reduce','Revoke')),
  schedule_mode character varying(24) not null check (schedule_mode in ('ExactExpiry','AddDays','AddMonths','Immediate')),
  schedule_amount integer,
  exact_expires_at_utc timestamptz,
  before_json jsonb not null check (jsonb_typeof(before_json)='object' and octet_length(before_json::text)<=32768),
  after_json jsonb not null check (jsonb_typeof(after_json)='object' and octet_length(after_json::text)<=32768),
  approval_request_id uuid references admin.approval_requests(id) on delete restrict,
  abuse_decision_id uuid references security.abuse_decisions(id) on delete restrict,
  executed_by_account_id uuid not null,
  reason character varying(1000) not null check (length(trim(reason)) between 10 and 1000),
  correlation_id uuid not null,
  idempotency_key character varying(180) not null,
  request_hash character varying(128) not null,
  executed_at_utc timestamptz not null default now(),
  unique(executed_by_account_id,idempotency_key)
);
create index if not exists ix_commerce_entitlement_adjustments_account
  on commerce.entitlement_adjustments(target_account_id,executed_at_utc desc,id desc);

alter table commerce.entitlement_adjustments enable row level security;
alter table commerce.entitlement_adjustments force row level security;
revoke all on table commerce.entitlement_adjustments from public,anon,authenticated;
grant select on table commerce.entitlement_adjustments to lifemate_admin_runtime;
drop policy if exists entitlement_adjustments_admin_runtime on commerce.entitlement_adjustments;
create policy entitlement_adjustments_admin_runtime
  on commerce.entitlement_adjustments for select to lifemate_admin_runtime using (true);

alter table commerce.entitlement_events
  drop constraint if exists entitlement_events_event_type_check;
alter table commerce.entitlement_events
  add constraint entitlement_events_event_type_check
  check (event_type in ('Granted','Renewed','Adjusted','Expired','Cancelled','Revoked','Refunded','Chargeback','TrialStarted','TrialConverted'));

create or replace function admin.account_has_active_role(
  p_account_id uuid,
  p_role_code character varying,
  p_at timestamptz default now()
) returns boolean
language sql
stable
security definer
set search_path=pg_catalog,admin,pg_temp
as $$
  select exists(
    select 1
    from admin.members m
    join admin.member_roles mr on mr.account_id=m.account_id
    join admin.roles r on r.id=mr.role_id
    where m.account_id=p_account_id
      and m.status='Active'
      and r.status='Active'
      and r.code=p_role_code
      and mr.revoked_at_utc is null
      and mr.starts_at_utc<=p_at
      and (mr.expires_at_utc is null or mr.expires_at_utc>p_at)
  )
$$;

create or replace function commerce.entitlement_adjustment_target_features(
  p_target_type character varying,
  p_target_id uuid
) returns table(feature_id uuid)
language sql
stable
security definer
set search_path=pg_catalog,commerce,pg_temp
as $$
  select pf.feature_id
  from commerce.product_features pf
  join commerce.products p on p.id=pf.product_id
  where p_target_type='Product' and pf.product_id=p_target_id and p.lifecycle_status in ('Published','Hidden')
  union
  select oe.feature_id
  from commerce.offer_entitlements oe
  join commerce.offers o on o.id=oe.offer_id
  where p_target_type='Offer' and oe.offer_id=p_target_id and o.status in ('Published','Hidden')
$$;

create or replace function commerce.entitlement_adjustment_snapshot(
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,commerce,pg_temp
as $$
  with tf as (
    select feature_id from commerce.entitlement_adjustment_target_features(p_target_type,p_target_id)
  ), rows as (
    select f.id as feature_id,f.code,
      count(e.id) filter (
        where e.source<>'FREE' and e.status='Active' and e.starts_at_utc<=now()
          and (e.expires_at_utc is null or e.expires_at_utc>now())
      ) as adjustable_active_count,
      count(e.id) filter (
        where e.source='FREE' and e.status='Active' and e.starts_at_utc<=now()
          and (e.expires_at_utc is null or e.expires_at_utc>now())
      ) as free_active_count,
      bool_or(e.expires_at_utc is null) filter (
        where e.source<>'FREE' and e.status='Active' and e.starts_at_utc<=now()
          and (e.expires_at_utc is null or e.expires_at_utc>now())
      ) as has_adjustable_indefinite,
      max(e.expires_at_utc) filter (
        where e.source<>'FREE' and e.status='Active' and e.starts_at_utc<=now()
          and e.expires_at_utc>now()
      ) as max_adjustable_expires_at_utc
    from tf
    join commerce.features f on f.id=tf.feature_id
    left join commerce.entitlements e on e.feature_id=f.id and e.grantee_account_id=p_account_id
    group by f.id,f.code
  )
  select jsonb_build_object(
    'targetType',p_target_type,
    'targetId',p_target_id,
    'accountId',p_account_id,
    'features',coalesce(jsonb_agg(jsonb_build_object(
      'featureId',feature_id,
      'featureCode',code,
      'adjustableActiveCount',adjustable_active_count,
      'freeActiveCount',free_active_count,
      'hasAdjustableIndefinite',coalesce(has_adjustable_indefinite,false),
      'maxAdjustableExpiresAtUtc',max_adjustable_expires_at_utc
    ) order by code),'[]'::jsonb)
  ) from rows
$$;

create or replace function commerce.preview_entitlement_adjustment(
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_action character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,commerce,identity,pg_temp
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_feature_count integer;
  v_active_count bigint;
  v_has_indefinite boolean;
  v_max_expiry timestamptz;
  v_result_expiry timestamptz;
begin
  if p_target_type not in ('Product','Offer') or p_action not in ('Grant','Extend','Reduce','Revoke')
     or p_schedule_mode not in ('ExactExpiry','AddDays','AddMonths','Immediate') then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjustment_invalid','message','Adjustment type is invalid.');
  end if;
  if not exists(select 1 from identity.accounts where id=p_account_id and status='Active') then
    return jsonb_build_object('httpStatus',404,'code','entitlement_account_not_found','message','Target account is not active.');
  end if;
  select count(*) into v_feature_count from commerce.entitlement_adjustment_target_features(p_target_type,p_target_id);
  if v_feature_count=0 then
    return jsonb_build_object('httpStatus',404,'code','entitlement_target_not_found','message','Product/offer has no canonical feature mapping.');
  end if;

  v_before:=commerce.entitlement_adjustment_snapshot(p_account_id,p_target_type,p_target_id);
  select
    coalesce(sum((x->>'adjustableActiveCount')::bigint),0),
    coalesce(bool_or((x->>'hasAdjustableIndefinite')::boolean),false),
    max(nullif(x->>'maxAdjustableExpiresAtUtc','')::timestamptz)
  into v_active_count,v_has_indefinite,v_max_expiry
  from jsonb_array_elements(v_before->'features') x;

  if p_action='Revoke' then
    if p_schedule_mode<>'Immediate' then
      return jsonb_build_object('httpStatus',400,'code','entitlement_revoke_mode_invalid','message','Revoke requires Immediate mode.');
    end if;
    if v_active_count=0 then
      return jsonb_build_object('httpStatus',409,'code','entitlement_nothing_to_revoke','message','No paid/manual entitlement is available to revoke.');
    end if;
    v_result_expiry:=now();
  elsif p_action='Reduce' then
    if p_schedule_mode<>'ExactExpiry' or p_exact_expires_at_utc is null or p_exact_expires_at_utc<=now() then
      return jsonb_build_object('httpStatus',400,'code','entitlement_reduce_expiry_invalid','message','Reduce requires a future exact expiry.');
    end if;
    if v_active_count=0 then
      return jsonb_build_object('httpStatus',409,'code','entitlement_nothing_to_reduce','message','No paid/manual entitlement is available to reduce.');
    end if;
    if not v_has_indefinite and (v_max_expiry is null or p_exact_expires_at_utc>=v_max_expiry) then
      return jsonb_build_object('httpStatus',409,'code','entitlement_reduce_not_smaller','message','Reduced expiry must be earlier than the current adjustable expiry.');
    end if;
    v_result_expiry:=p_exact_expires_at_utc;
  elsif p_schedule_mode='ExactExpiry' then
    if p_exact_expires_at_utc is null or p_exact_expires_at_utc<=now() then
      return jsonb_build_object('httpStatus',400,'code','entitlement_expiry_invalid','message','Exact expiry must be in the future.');
    end if;
    v_result_expiry:=p_exact_expires_at_utc;
  elsif p_schedule_mode='AddDays' then
    if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>3650 then
      return jsonb_build_object('httpStatus',400,'code','entitlement_days_invalid','message','AddDays amount is invalid.');
    end if;
    if p_action='Extend' and v_has_indefinite then
      return jsonb_build_object('httpStatus',409,'code','entitlement_already_indefinite','message','An indefinite entitlement cannot be extended.');
    end if;
    v_result_expiry:=coalesce(case when p_action='Extend' then v_max_expiry end,now())+make_interval(days=>p_schedule_amount);
  elsif p_schedule_mode='AddMonths' then
    if p_schedule_amount is null or p_schedule_amount<1 or p_schedule_amount>120 then
      return jsonb_build_object('httpStatus',400,'code','entitlement_months_invalid','message','AddMonths amount is invalid.');
    end if;
    if p_action='Extend' and v_has_indefinite then
      return jsonb_build_object('httpStatus',409,'code','entitlement_already_indefinite','message','An indefinite entitlement cannot be extended.');
    end if;
    v_result_expiry:=coalesce(case when p_action='Extend' then v_max_expiry end,now())+make_interval(months=>p_schedule_amount);
  else
    return jsonb_build_object('httpStatus',400,'code','entitlement_schedule_invalid','message','Schedule mode is invalid for this action.');
  end if;

  if p_action='Extend' and v_active_count=0 then
    return jsonb_build_object('httpStatus',409,'code','entitlement_nothing_to_extend','message','No paid/manual entitlement is available to extend.');
  end if;
  if p_action='Extend' and v_max_expiry is not null and v_result_expiry<=v_max_expiry then
    return jsonb_build_object('httpStatus',409,'code','entitlement_extend_not_larger','message','Extended expiry must be later than the current adjustable expiry.');
  end if;

  v_after:=jsonb_build_object(
    'accountId',p_account_id,
    'targetType',p_target_type,
    'targetId',p_target_id,
    'action',p_action,
    'effectiveExpiresAtUtc',v_result_expiry,
    'featureCount',v_feature_count
  );
  return jsonb_build_object(
    'httpStatus',200,'code','ok','before',v_before,
    'delta',jsonb_build_object(
      'action',p_action,'targetType',p_target_type,'targetId',p_target_id,'scheduleMode',p_schedule_mode,
      'scheduleAmount',p_schedule_amount,'exactExpiresAtUtc',p_exact_expires_at_utc,'effectiveExpiresAtUtc',v_result_expiry
    ),
    'after',v_after
  );
end $$;

create or replace function commerce.execute_entitlement_adjustment(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_action character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz,
  p_reason character varying,
  p_confirmed boolean,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,security,pg_temp
as $$
declare
  v_operation character varying(160):='commerce.entitlement.adjust.execute';
  v_existing admin.idempotency_keys%rowtype;
  v_preview jsonb;
  v_before jsonb;
  v_delta jsonb;
  v_after jsonb;
  v_approval jsonb;
  v_abuse jsonb;
  v_founder boolean;
  v_adjustment_id uuid:=gen_random_uuid();
  v_entitlement record;
  v_feature uuid;
  v_changed integer:=0;
  v_event_type character varying(32);
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute') then
    return jsonb_build_object('httpStatus',403,'code','entitlement_adjust_execute_denied','message','Actor cannot execute entitlement adjustments.');
  end if;
  if p_action in ('Reduce','Revoke') and coalesce(p_confirmed,false)=false then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjustment_confirmation_required','message','Reduce and Revoke require explicit confirmation.');
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjustment_metadata_invalid','message','Reason or idempotency metadata is invalid.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_account_id::text||':'||p_target_type||':'||p_target_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different adjustment.');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching adjustment is still processing.');
  end if;

  v_preview:=commerce.preview_entitlement_adjustment(
    p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,p_schedule_amount,p_exact_expires_at_utc
  );
  if coalesce((v_preview->>'httpStatus')::integer,500)>=400 then return v_preview; end if;
  v_before:=v_preview->'before';
  v_delta:=v_preview->'delta';
  v_after:=v_preview->'after';

  v_abuse:=security.evaluate_abuse_rules(
    p_actor_account_id,p_account_id,'entitlement.adjust',p_idempotency_key,
    case when p_approval_request_id is null then '{}'::varchar[] else array['approval_present']::varchar[] end,
    'abuse:'||p_idempotency_key,p_request_hash
  );
  if coalesce((v_abuse->>'httpStatus')::integer,500)>=400 then return v_abuse; end if;
  if v_abuse->>'action'='Deny' then
    return jsonb_build_object(
      'httpStatus',403,'code','entitlement_adjustment_abuse_denied',
      'message','Adjustment was denied by an explainable abuse rule.',
      'abuseDecisionId',v_abuse->>'decisionId','reasonCodes',v_abuse->'reasonCodes'
    );
  end if;

  v_founder:=admin.account_has_active_role(p_actor_account_id,'founder');
  if (not v_founder) or v_abuse->>'action'='RequireApproval' then
    if p_approval_request_id is null or p_approval_expected_version is null then
      return jsonb_build_object(
        'httpStatus',409,'code','entitlement_adjustment_approval_required',
        'message','An approved adjustment request is required.',
        'approvalRequestType',coalesce(v_abuse->>'approvalRequestType','commerce.entitlement.adjustment')
      );
    end if;
    v_approval:=admin.consume_approval_request(
      p_actor_account_id,p_approval_request_id,p_approval_expected_version,v_operation,p_correlation_id
    );
    if v_approval->>'requestType'<>'commerce.entitlement.adjustment'
       or v_approval->>'targetType'<>'commerce_entitlement_adjustment'
       or v_approval->>'targetId'<>p_account_id::text
       or v_approval->'before'<>v_before
       or v_approval->'delta'<>v_delta
       or v_approval->'after'<>v_after then
      raise exception using errcode='22023',message='Approval payload does not match the current entitlement adjustment.';
    end if;
    if v_abuse->>'action'='RequireApproval'
       and coalesce(v_abuse->>'approvalRequestType','commerce.entitlement.adjustment')<>'commerce.entitlement.adjustment' then
      raise exception using errcode='22023',message='Abuse rule requires an incompatible approval policy.';
    end if;
  elsif p_approval_request_id is not null then
    return jsonb_build_object('httpStatus',400,'code','entitlement_adjustment_unexpected_approval','message','Founder-direct execution must not silently consume an unrelated approval.');
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  insert into commerce.entitlement_adjustments(
    id,target_account_id,target_type,target_id,action,schedule_mode,schedule_amount,exact_expires_at_utc,
    before_json,after_json,approval_request_id,abuse_decision_id,executed_by_account_id,reason,correlation_id,
    idempotency_key,request_hash
  ) values(
    v_adjustment_id,p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,p_schedule_amount,p_exact_expires_at_utc,
    v_before,v_after,p_approval_request_id,nullif(v_abuse->>'decisionId','')::uuid,p_actor_account_id,trim(p_reason),p_correlation_id,
    p_idempotency_key,p_request_hash
  );

  if p_action='Grant' then
    for v_feature in select feature_id from commerce.entitlement_adjustment_target_features(p_target_type,p_target_id) loop
      insert into commerce.entitlements(
        grantee_account_id,feature_id,source,source_key,status,starts_at_utc,expires_at_utc
      ) values(
        p_account_id,v_feature,'ADMIN_GRANT','adjustment:'||v_adjustment_id::text,'Active',now(),(v_after->>'effectiveExpiresAtUtc')::timestamptz
      ) returning * into v_entitlement;
      insert into commerce.entitlement_events(entitlement_id,event_type,provider_event_key,occurred_at_utc,metadata_json)
      values(v_entitlement.id,'Granted','admin-adjustment:'||v_adjustment_id::text||':'||v_entitlement.id::text,now(),
        jsonb_build_object('adjustmentId',v_adjustment_id,'adminAction','Grant'));
      v_changed:=v_changed+1;
    end loop;
  else
    v_event_type:=case p_action when 'Extend' then 'Renewed' when 'Reduce' then 'Adjusted' else 'Revoked' end;
    for v_entitlement in
      select e.*
      from commerce.entitlements e
      join commerce.entitlement_adjustment_target_features(p_target_type,p_target_id) tf on tf.feature_id=e.feature_id
      where e.grantee_account_id=p_account_id
        and e.source<>'FREE'
        and e.status='Active'
        and e.starts_at_utc<=now()
        and (e.expires_at_utc is null or e.expires_at_utc>now())
      for update of e
    loop
      if p_action='Extend' then
        update commerce.entitlements
        set expires_at_utc=(v_after->>'effectiveExpiresAtUtc')::timestamptz,updated_at_utc=now()
        where id=v_entitlement.id and expires_at_utc is not null
          and expires_at_utc<(v_after->>'effectiveExpiresAtUtc')::timestamptz;
      elsif p_action='Reduce' then
        update commerce.entitlements
        set expires_at_utc=(v_after->>'effectiveExpiresAtUtc')::timestamptz,updated_at_utc=now()
        where id=v_entitlement.id
          and (expires_at_utc is null or expires_at_utc>(v_after->>'effectiveExpiresAtUtc')::timestamptz);
      else
        update commerce.entitlements
        set status='Revoked',expires_at_utc=least(coalesce(expires_at_utc,now()),now()),updated_at_utc=now()
        where id=v_entitlement.id;
      end if;
      if found then
        insert into commerce.entitlement_events(entitlement_id,event_type,provider_event_key,occurred_at_utc,metadata_json)
        values(v_entitlement.id,v_event_type,'admin-adjustment:'||v_adjustment_id::text||':'||v_entitlement.id::text,now(),
          jsonb_build_object('adjustmentId',v_adjustment_id,'adminAction',p_action));
        v_changed:=v_changed+1;
      end if;
    end loop;
  end if;

  if v_changed=0 then
    raise exception using errcode='55000',message='Adjustment did not change any entitlement.';
  end if;

  perform security.record_abuse_event(p_account_id,'entitlement.adjust',p_idempotency_key,'adjustment_executed');
  v_after:=commerce.entitlement_adjustment_snapshot(p_account_id,p_target_type,p_target_id);
  update commerce.entitlement_adjustments set after_json=v_after where id=v_adjustment_id;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(
    p_actor_account_id,'commerce.entitlement.adjust.execute','entitlement_adjustment',v_adjustment_id::text,
    'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('targetAccountId',p_account_id,'targetType',p_target_type,'targetId',p_target_id,'action',p_action,'changedEntitlements',v_changed)
  );

  v_result:=jsonb_build_object(
    'httpStatus',200,'code','ok','id',v_adjustment_id,'action',p_action,'changedEntitlements',v_changed,
    'before',v_before,'after',v_after,'abuseDecisionId',v_abuse->>'decisionId','replayed',false
  );
  update admin.idempotency_keys
  set status='Completed',response_status=200,response_json=v_result,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result;
end $$;

revoke all on function admin.account_has_active_role(uuid,character varying,timestamptz) from public,anon,authenticated;
revoke all on function commerce.entitlement_adjustment_target_features(character varying,uuid) from public,anon,authenticated;
revoke all on function commerce.entitlement_adjustment_snapshot(uuid,character varying,uuid) from public,anon,authenticated;
revoke all on function commerce.preview_entitlement_adjustment(uuid,character varying,uuid,character varying,character varying,integer,timestamptz) from public,anon,authenticated;
revoke all on function commerce.execute_entitlement_adjustment(uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,character varying,boolean,uuid,bigint,uuid,character varying,character varying) from public,anon,authenticated;
grant execute on function commerce.preview_entitlement_adjustment(uuid,character varying,uuid,character varying,character varying,integer,timestamptz) to lifemate_admin_runtime;
grant execute on function commerce.execute_entitlement_adjustment(uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,character varying,boolean,uuid,bigint,uuid,character varying,character varying) to lifemate_admin_runtime;

comment on table commerce.entitlement_adjustments is 'Immutable audit-oriented business ledger for manual entitlement operations. Financial/payment history is not rewritten.';
comment on function commerce.execute_entitlement_adjustment(uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,character varying,boolean,uuid,bigint,uuid,character varying,character varying) is 'Canonical #492 mutation. FREE baseline entitlements are never reduced/revoked; non-Founder execution consumes an approved #491 request transactionally; Reduce/Revoke require explicit confirmation.';

commit;
