begin;

-- Trial configuration is a Commerce policy, not an entitlement grant. Creating or
-- changing a policy never reprices, migrates, or grants an existing subscription.
create table if not exists commerce.trial_policies (
  plan_id uuid primary key references commerce.plans(id) on delete restrict,
  duration_days smallint not null check (duration_days between 1 and 365),
  eligibility_rule character varying(48) not null
    check (eligibility_rule in ('NoPriorTrialForProduct')),
  status character varying(24) not null default 'Disabled'
    check (status in ('Active','Disabled')),
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

alter table commerce.trial_policies enable row level security;
alter table commerce.trial_policies force row level security;
drop policy if exists trial_policies_no_direct_access on commerce.trial_policies;
create policy trial_policies_no_direct_access
  on commerce.trial_policies
  for all
  using (false)
  with check (false);

insert into admin.permissions(code, domain, risk_level, role_assignable, description) values
('commerce.trial.write','commerce','HIGH_RISK',true,'Configure versioned trial duration and lifecycle through the audited server workflow')
on conflict (code) do update set
  domain=excluded.domain, risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable, description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id, permission_code)
select r.id, 'commerce.trial.write'
from admin.roles r where r.code in ('founder','super_admin','product')
on conflict do nothing;

create or replace function admin.configure_commerce_trial_policy(
  p_actor_account_id uuid, p_plan_id uuid, p_duration_days smallint,
  p_eligibility_rule character varying, p_status character varying, p_expected_version integer, p_reason character varying,
  p_correlation_id uuid, p_idempotency_key character varying, p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, commerce, pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.trial.configure';
  v_existing admin.idempotency_keys%rowtype;
  v_policy commerce.trial_policies%rowtype;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id, 'commerce.trial.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_duration_days is null or p_duration_days not between 1 and 365 or p_eligibility_rule <> 'NoPriorTrialForProduct' or p_status not in ('Active','Disabled')
     or p_expected_version is null or p_expected_version < 0 then
    return jsonb_build_object('httpStatus',400,'code','trial_policy_invalid','message','Trial policy fields are invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','trial_request_invalid','message','Trial request metadata is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key, 0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash <> p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json || jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
    values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  perform pg_advisory_xact_lock(hashtextextended('commerce.trial:' || p_plan_id::text, 0));
  if not exists(select 1 from commerce.plans pl join commerce.products pr on pr.id=pl.product_id where pl.id=p_plan_id and pl.status='Active' and pr.status='Active') then
    v_response:=jsonb_build_object('httpStatus',409,'code','commerce_plan_inactive','message','Trial policy requires an active plan on an active product.','replayed',false);
  else
    select * into v_policy from commerce.trial_policies where plan_id=p_plan_id for update;
    if not found then
      if p_expected_version <> 0 then
        v_response:=jsonb_build_object('httpStatus',409,'code','trial_version_conflict','message','Trial policy version does not match.','replayed',false);
      else
        insert into commerce.trial_policies(plan_id,duration_days,eligibility_rule,status,version) values(p_plan_id,p_duration_days,p_eligibility_rule,p_status,1);
        v_response:=jsonb_build_object('httpStatus',201,'code','ok','planId',p_plan_id,'durationDays',p_duration_days,'eligibilityRule',p_eligibility_rule,'status',p_status,'version',1,'replayed',false);
      end if;
    elsif v_policy.version <> p_expected_version then
      v_response:=jsonb_build_object('httpStatus',409,'code','trial_version_conflict','message','Trial policy version does not match.','replayed',false);
    else
      update commerce.trial_policies set duration_days=p_duration_days,eligibility_rule=p_eligibility_rule,status=p_status,version=version+1,updated_at_utc=now() where plan_id=p_plan_id returning * into v_policy;
      v_response:=jsonb_build_object('httpStatus',200,'code','ok','planId',p_plan_id,'durationDays',v_policy.duration_days,'eligibilityRule',v_policy.eligibility_rule,'status',v_policy.status,'version',v_policy.version,'replayed',false);
    end if;
  end if;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'commerce_trial_policy',p_plan_id::text,
    case when (v_response->>'httpStatus')::integer < 400 then 'Succeeded' else 'Denied' end,
    trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('code',v_response->>'code','durationDays',p_duration_days,'eligibilityRule',p_eligibility_rule,'status',p_status,'expectedVersion',p_expected_version));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.configure_commerce_trial_policy(uuid,uuid,smallint,character varying,character varying,integer,character varying,uuid,character varying,character varying) from public;
grant execute on function admin.configure_commerce_trial_policy(uuid,uuid,smallint,character varying,character varying,integer,character varying,uuid,character varying,character varying) to lifemate_admin_runtime;

commit;
