begin;

alter table growth.referral_attributions
  add column if not exists version bigint not null default 1 check (version >= 1);
alter table growth.advocacy_submissions
  add column if not exists version bigint not null default 1 check (version >= 1);
alter table growth.reward_events
  add column if not exists version bigint not null default 1 check (version >= 1),
  add column if not exists reward_config_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(reward_config_snapshot)='object'),
  add column if not exists approval_request_id uuid references admin.approval_requests(id) on delete restrict,
  add column if not exists fulfilled_by_account_id uuid,
  add column if not exists fulfillment_correlation_id uuid;

create or replace function growth.snapshot_reward_event_config()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,growth,pg_temp
as $$
declare v_rule growth.reward_rules%rowtype;
begin
  select * into v_rule from growth.reward_rules where id=new.reward_rule_id;
  if not found or v_rule.version<>new.reward_rule_version or v_rule.reward_kind<>new.reward_kind then
    raise exception using errcode='55000',message='Reward rule snapshot is unavailable.';
  end if;
  new.reward_config_snapshot:=v_rule.reward_config;
  return new;
end $$;
revoke all on function growth.snapshot_reward_event_config() from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
drop trigger if exists trg_growth_reward_event_snapshot on growth.reward_events;
create trigger trg_growth_reward_event_snapshot
before insert on growth.reward_events
for each row execute function growth.snapshot_reward_event_config();

create or replace function growth.validate_reward_rule_fulfillment_config()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,growth,pg_temp
as $$
declare v_days integer;
begin
  if new.reward_kind='GiftEntitlement' then
    if coalesce(new.reward_config->>'targetType','') not in ('Product','Offer')
       or coalesce(new.reward_config->>'targetId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(new.reward_config->>'durationDays','') !~ '^[0-9]{1,4}$' then
      raise exception using errcode='22023',message='Gift entitlement reward configuration is invalid.';
    end if;
    v_days:=(new.reward_config->>'durationDays')::integer;
    if v_days not between 1 and 3650 then
      raise exception using errcode='22023',message='Gift entitlement reward duration is invalid.';
    end if;
  elsif new.reward_kind='Discount' and new.status='Active' then
    if coalesce(new.reward_config->>'promotionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception using errcode='22023',message='Discount reward must reference a canonical promotion.';
    end if;
  end if;
  return new;
end $$;
revoke all on function growth.validate_reward_rule_fulfillment_config() from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
drop trigger if exists trg_growth_reward_rule_fulfillment_config on growth.reward_rules;
create trigger trg_growth_reward_rule_fulfillment_config
before insert or update of reward_kind,reward_config,status on growth.reward_rules
for each row execute function growth.validate_reward_rule_fulfillment_config();

insert into admin.approval_policies(
  request_type,display_name,request_permission,approval_permission,execution_permission,
  self_approval_allowed,default_expiry_minutes,status
) values(
  'growth_reward_fulfillment','Growth reward fulfillment','growth.rewards.write','growth.rewards.write','growth.rewards.write',
  false,1440,'Active'
)
on conflict (request_type) do update set
  display_name=excluded.display_name,
  request_permission=excluded.request_permission,
  approval_permission=excluded.approval_permission,
  execution_permission=excluded.execution_permission,
  self_approval_allowed=false,
  status='Active',
  version=admin.approval_policies.version+1,
  updated_at_utc=now();

insert into admin.approval_policy_approver_roles(request_type,role_code)
select 'growth_reward_fulfillment',r.code from admin.roles r
where r.code in ('founder','super_admin')
on conflict do nothing;

create or replace function admin.review_growth_reward_source(
  p_actor_account_id uuid,
  p_source_kind varchar,
  p_source_id uuid,
  p_expected_version bigint,
  p_decision varchar,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,growth,extensions,pg_temp
as $$
declare
  v_operation constant varchar:='growth.reward_source.review';
  v_existing admin.idempotency_keys%rowtype;
  v_status varchar;
  v_version bigint;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_source_kind not in ('Referral','Advocacy') or p_source_id is null
     or p_expected_version is null or p_expected_version<1
     or lower(trim(coalesce(p_decision,''))) not in ('approve','reject')
     or p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_correlation_id is null or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_source_review_invalid','message','Reward source review request is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key conflict.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still processing.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if p_source_kind='Referral' then
    select status,version into v_status,v_version from growth.referral_attributions where id=p_source_id for update;
    if not found then
      v_response:=jsonb_build_object('httpStatus',404,'code','reward_source_not_found','message','Referral source was not found.','replayed',false);
    elsif v_version<>p_expected_version then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_source_version_conflict','message','Referral source changed; refresh before review.','currentVersion',v_version,'replayed',false);
    elsif v_status not in ('Attributed','PendingReview') then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_source_state_conflict','message','Referral source is not reviewable.','currentStatus',v_status,'replayed',false);
    else
      update growth.referral_attributions set
        status=case when lower(trim(p_decision))='approve' then 'Qualified' else 'Rejected' end,
        qualified_at_utc=case when lower(trim(p_decision))='approve' then now() else qualified_at_utc end,
        version=version+1
      where id=p_source_id returning status,version into v_status,v_version;
    end if;
  else
    select status,version into v_status,v_version from growth.advocacy_submissions where id=p_source_id for update;
    if not found then
      v_response:=jsonb_build_object('httpStatus',404,'code','reward_source_not_found','message','Advocacy source was not found.','replayed',false);
    elsif v_version<>p_expected_version then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_source_version_conflict','message','Advocacy source changed; refresh before review.','currentVersion',v_version,'replayed',false);
    elsif v_status<>'PendingReview' then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_source_state_conflict','message','Advocacy source is not reviewable.','currentStatus',v_status,'replayed',false);
    else
      update growth.advocacy_submissions set
        status=case when lower(trim(p_decision))='approve' then 'Verified' else 'Rejected' end,
        reviewed_by_account_id=p_actor_account_id,reviewed_at_utc=now(),updated_at_utc=now(),version=version+1
      where id=p_source_id returning status,version into v_status,v_version;
    end if;
  end if;

  if v_response is null then
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','sourceKind',p_source_kind,'sourceId',p_source_id,'status',v_status,'version',v_version,'replayed',false);
  end if;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'growth_reward_source',p_source_kind||':'||p_source_id::text,
    case when (v_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('code',v_response->>'code','decision',lower(trim(p_decision)),'expectedVersion',p_expected_version));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;
revoke all on function admin.review_growth_reward_source(uuid,varchar,uuid,bigint,varchar,varchar,uuid,varchar,varchar) from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function admin.review_growth_reward_source(uuid,varchar,uuid,bigint,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

create or replace function admin.preview_growth_reward_fulfillment(
  p_reward_event_id uuid,
  p_expected_version bigint
) returns jsonb
language plpgsql
security definer
stable
set search_path=pg_catalog,admin,growth,extensions,pg_temp
as $$
declare v_event growth.reward_events%rowtype;
begin
  select * into v_event from growth.reward_events where id=p_reward_event_id;
  if not found then return jsonb_build_object('httpStatus',404,'code','reward_event_not_found','message','Reward event was not found.'); end if;
  if p_expected_version is null or v_event.version<>p_expected_version then
    return jsonb_build_object('httpStatus',409,'code','reward_event_version_conflict','message','Reward event changed; refresh before fulfillment.','currentVersion',v_event.version);
  end if;
  if v_event.status<>'Pending' then return jsonb_build_object('httpStatus',409,'code','reward_event_state_conflict','message','Only pending rewards may be fulfilled.'); end if;
  if v_event.reward_kind in ('Discount','CharityImpact') then
    return jsonb_build_object('httpStatus',409,'code','reward_fulfillment_adapter_unavailable','message','This reward kind has no canonical fulfillment adapter yet.');
  end if;
  return jsonb_build_object(
    'httpStatus',200,'code','ok',
    'before',jsonb_build_object('rewardEventId',v_event.id,'status',v_event.status,'version',v_event.version),
    'delta',jsonb_build_object(
      'rewardEventId',v_event.id,'beneficiaryAccountId',v_event.beneficiary_account_id,
      'rewardKind',v_event.reward_kind,'ruleVersion',v_event.reward_rule_version,
      'configHash',encode(extensions.digest(v_event.reward_config_snapshot::text,'sha256'),'hex')
    ),
    'after',jsonb_build_object('rewardEventId',v_event.id,'status','Issued','version',v_event.version+1)
  );
end $$;
revoke all on function admin.preview_growth_reward_fulfillment(uuid,bigint) from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function admin.preview_growth_reward_fulfillment(uuid,bigint) to lifemate_admin_runtime;

create or replace function admin.execute_growth_reward_fulfillment(
  p_actor_account_id uuid,
  p_reward_event_id uuid,
  p_expected_version bigint,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,growth,commerce,extensions,pg_temp
as $$
declare
  v_operation constant varchar:='growth.reward.fulfill';
  v_existing admin.idempotency_keys%rowtype;
  v_event growth.reward_events%rowtype;
  v_preview jsonb;
  v_approval jsonb;
  v_ids uuid[];
  v_expiry timestamptz;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_reward_event_id is null or p_expected_version is null or p_expected_version<1
     or p_approval_request_id is null or p_approval_expected_version is null or p_approval_expected_version<1
     or p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_correlation_id is null or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_fulfillment_invalid','message','Reward fulfillment request is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key conflict.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still processing.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_event from growth.reward_events where id=p_reward_event_id for update;
  if not found then
    v_response:=jsonb_build_object('httpStatus',404,'code','reward_event_not_found','message','Reward event was not found.','replayed',false);
  elsif v_event.version<>p_expected_version then
    v_response:=jsonb_build_object('httpStatus',409,'code','reward_event_version_conflict','message','Reward event changed; refresh before fulfillment.','currentVersion',v_event.version,'replayed',false);
  elsif v_event.status<>'Pending' then
    v_response:=jsonb_build_object('httpStatus',409,'code','reward_event_state_conflict','message','Only pending rewards may be fulfilled.','replayed',false);
  elsif v_event.reward_kind in ('Discount','CharityImpact') then
    v_response:=jsonb_build_object('httpStatus',409,'code','reward_fulfillment_adapter_unavailable','message','This reward kind has no canonical fulfillment adapter yet.','replayed',false);
  else
    v_preview:=admin.preview_growth_reward_fulfillment(v_event.id,v_event.version);
    v_approval:=admin.consume_approval_request(p_actor_account_id,p_approval_request_id,p_approval_expected_version,v_operation,p_correlation_id);
    if v_approval->>'requestType'<>'growth_reward_fulfillment'
       or v_approval->>'targetType'<>'growth_reward_event'
       or v_approval->>'targetId'<>v_event.id::text
       or coalesce(v_approval->'delta','{}'::jsonb)<>coalesce(v_preview->'delta','{}'::jsonb) then
      raise exception using errcode='55000',message='Reward approval snapshot no longer matches fulfillment.';
    end if;

    if v_event.reward_kind='GiftEntitlement' then
      if not admin.account_has_permission(p_actor_account_id,'commerce.entitlement.adjust.execute') then
        raise exception using errcode='42501',message='Reward executor lacks canonical entitlement authority.';
      end if;
      v_expiry:=now()+make_interval(days=>(v_event.reward_config_snapshot->>'durationDays')::integer);
      select commerce.apply_manual_entitlement_grant_guarded(
        p_actor_account_id,v_event.beneficiary_account_id,v_event.reward_config_snapshot->>'targetType',
        (v_event.reward_config_snapshot->>'targetId')::uuid,v_expiry,v_event.id
      ) into v_ids;
    end if;

    update growth.reward_events set
      status='Issued',issued_at_utc=now(),version=version+1,
      approval_request_id=p_approval_request_id,fulfilled_by_account_id=p_actor_account_id,
      fulfillment_correlation_id=p_correlation_id,
      reward_reference_hash=case when v_ids is null then encode(extensions.digest('raffle:'||id::text,'sha256'),'hex')
        else encode(extensions.digest(array_to_string(v_ids,','),'sha256'),'hex') end
    where id=v_event.id returning * into v_event;
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,v_operation,'growth_reward_event',v_event.id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('rewardKind',v_event.reward_kind,'beneficiaryAccountIdHash',encode(extensions.digest(v_event.beneficiary_account_id::text,'sha256'),'hex'),'version',v_event.version));
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','rewardEventId',v_event.id,'status',v_event.status,'version',v_event.version,'replayed',false);
  end if;

  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;
revoke all on function admin.execute_growth_reward_fulfillment(uuid,uuid,bigint,uuid,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function admin.execute_growth_reward_fulfillment(uuid,uuid,bigint,uuid,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

comment on function admin.execute_growth_reward_fulfillment(uuid,uuid,bigint,uuid,bigint,varchar,uuid,varchar,varchar) is
  'Consumes a canonical non-self approval in the same transaction as fulfillment. GiftEntitlement reuses #492 guarded entitlement authority; Discount and CharityImpact fail closed until canonical adapters exist.';

commit;
