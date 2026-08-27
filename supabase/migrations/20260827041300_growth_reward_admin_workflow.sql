begin;

alter table growth.advocacy_submissions
  add column if not exists version bigint not null default 1 check (version >= 1);

alter table growth.reward_events
  add column if not exists approval_request_id uuid references admin.approval_requests(id) on delete restrict,
  add column if not exists issued_by_account_id uuid,
  add column if not exists correlation_id uuid,
  add column if not exists idempotency_key varchar(180),
  add column if not exists request_hash varchar(128) check (request_hash is null or request_hash ~ '^[0-9a-f]{64,128}$'),
  add column if not exists fulfillment_state varchar(24) not null default 'NotStarted'
    check (fulfillment_state in ('NotStarted','PendingFulfillment','Fulfilled','Rejected')),
  add column if not exists fulfillment_metadata_json jsonb not null default '{}'::jsonb
    check (jsonb_typeof(fulfillment_metadata_json)='object');

create unique index if not exists uq_growth_reward_events_actor_idempotency
  on growth.reward_events(issued_by_account_id,idempotency_key)
  where issued_by_account_id is not null and idempotency_key is not null;

insert into admin.approval_policies(
  request_type,display_name,request_permission,approval_permission,execution_permission,
  self_approval_allowed,default_expiry_minutes,status
) values(
  'growth_reward_issue','Growth reward issuance','growth.rewards.write','growth.rewards.write','growth.rewards.write',
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
select 'growth_reward_issue',r.code
from admin.roles r
where r.code in ('founder','super_admin')
on conflict do nothing;

create or replace function growth.reward_source_is_valid(
  p_beneficiary_account_id uuid,
  p_source_kind varchar,
  p_source_id uuid
) returns boolean
language plpgsql
security definer
stable
set search_path=pg_catalog,growth,commerce,marketing,pg_temp
as $$
begin
  if p_source_kind='Referral' then
    return exists(
      select 1 from growth.referral_attributions a
      where a.id=p_source_id
        and p_beneficiary_account_id in (a.referrer_account_id,a.referred_account_id)
        and a.status in ('Attributed','Qualified','Rewarded')
    );
  elsif p_source_kind='Advocacy' then
    return exists(
      select 1 from growth.advocacy_submissions s
      where s.id=p_source_id and s.account_id=p_beneficiary_account_id
        and s.status in ('Verified','Rewarded')
    );
  elsif p_source_kind='Gift' then
    return exists(
      select 1 from commerce.gift_intents g
      where g.id=p_source_id
        and p_beneficiary_account_id in (g.purchaser_account_id,g.recipient_account_id)
        and g.status in ('Paid','Fulfilled')
    );
  end if;
  return false;
end $$;
revoke all on function growth.reward_source_is_valid(uuid,varchar,uuid) from public,anon,authenticated;

create or replace function growth.preview_reward_issue(
  p_beneficiary_account_id uuid,
  p_source_kind varchar,
  p_source_id uuid,
  p_reward_rule_id uuid,
  p_expected_rule_version bigint,
  p_provenance_hash varchar
) returns jsonb
language plpgsql
security definer
stable
set search_path=pg_catalog,growth,identity,pg_temp
as $$
declare
  v_rule growth.reward_rules%rowtype;
  v_count bigint;
begin
  if p_beneficiary_account_id is null or p_source_id is null or p_reward_rule_id is null
     or p_source_kind not in ('Referral','Advocacy','Gift','Campaign')
     or p_expected_rule_version is null or p_expected_rule_version<1
     or p_provenance_hash is null or p_provenance_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_issue_invalid','message','Reward issuance fields are invalid.');
  end if;
  if not exists(select 1 from identity.accounts where id=p_beneficiary_account_id and status='Active') then
    return jsonb_build_object('httpStatus',404,'code','reward_beneficiary_unavailable','message','Reward beneficiary is unavailable.');
  end if;
  select * into v_rule from growth.reward_rules where id=p_reward_rule_id;
  if not found or v_rule.status<>'Active' then
    return jsonb_build_object('httpStatus',404,'code','reward_rule_unavailable','message','Reward rule is unavailable.');
  end if;
  if v_rule.version<>p_expected_rule_version then
    return jsonb_build_object('httpStatus',409,'code','reward_rule_version_conflict','message','Reward rule changed; refresh before issuing.','currentVersion',v_rule.version);
  end if;
  if v_rule.trigger_kind<>p_source_kind then
    return jsonb_build_object('httpStatus',409,'code','reward_source_rule_mismatch','message','Reward source does not match the selected rule.');
  end if;
  if p_source_kind='Campaign' or not growth.reward_source_is_valid(p_beneficiary_account_id,p_source_kind,p_source_id) then
    return jsonb_build_object('httpStatus',409,'code','reward_source_not_eligible','message','Reward source is not eligible for issuance.');
  end if;
  if exists(
    select 1 from growth.reward_events e
    where e.beneficiary_account_id=p_beneficiary_account_id and e.source_kind=p_source_kind
      and e.source_id=p_source_id and e.reward_rule_id=p_reward_rule_id
      and e.status<>'Rejected'
  ) then
    return jsonb_build_object('httpStatus',409,'code','reward_already_recorded','message','This reward was already recorded.');
  end if;
  if v_rule.max_issues_per_account is not null then
    select count(*) into v_count from growth.reward_events e
    where e.beneficiary_account_id=p_beneficiary_account_id
      and e.reward_rule_id=p_reward_rule_id and e.status in ('Pending','Issued');
    if v_count>=v_rule.max_issues_per_account then
      return jsonb_build_object('httpStatus',409,'code','reward_account_limit_reached','message','Reward account limit has been reached.');
    end if;
  end if;
  return jsonb_build_object(
    'httpStatus',200,'code','ok',
    'before',jsonb_build_object('rewardEventId',null,'status','Absent'),
    'delta',jsonb_build_object(
      'beneficiaryAccountId',p_beneficiary_account_id,'sourceKind',p_source_kind,'sourceId',p_source_id,
      'rewardRuleId',v_rule.id,'rewardRuleVersion',v_rule.version,'rewardKind',v_rule.reward_kind,
      'provenanceHash',lower(p_provenance_hash)
    ),
    'after',jsonb_build_object('status','Pending','rewardKind',v_rule.reward_kind,'ruleVersion',v_rule.version)
  );
end $$;
revoke all on function growth.preview_reward_issue(uuid,varchar,uuid,uuid,bigint,varchar) from public,anon,authenticated;
grant execute on function growth.preview_reward_issue(uuid,varchar,uuid,uuid,bigint,varchar) to lifemate_admin_runtime;

create or replace function growth.upsert_reward_rule(
  p_actor_account_id uuid,
  p_rule_id uuid,
  p_code varchar,
  p_trigger_kind varchar,
  p_reward_kind varchar,
  p_reward_config jsonb,
  p_max_issues_per_account integer,
  p_status varchar,
  p_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,admin,pg_temp
as $$
declare
  v_operation constant varchar:='growth.reward_rule.upsert';
  v_existing admin.idempotency_keys%rowtype;
  v_rule growth.reward_rules%rowtype;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_code is null or lower(trim(p_code)) !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_trigger_kind not in ('Referral','Advocacy','Gift','Campaign')
     or p_reward_kind not in ('Discount','GiftEntitlement','RaffleEligibility','CharityImpact')
     or coalesce(jsonb_typeof(p_reward_config),'null')<>'object'
     or p_status not in ('Draft','Active','Paused','Retired')
     or (p_max_issues_per_account is not null and p_max_issues_per_account not between 1 and 100000)
     or p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_rule_invalid','message','Reward rule fields are invalid.','replayed',false);
  end if;
  if p_reward_kind='GiftEntitlement' and (
      coalesce(p_reward_config->>'targetType','') not in ('Product','Offer')
      or coalesce(p_reward_config->>'targetId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or coalesce(p_reward_config->>'expiresAtUtc','')=''
    ) then
    return jsonb_build_object('httpStatus',400,'code','gift_entitlement_reward_config_invalid','message','Gift entitlement reward config is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for another request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if p_rule_id is null then
    insert into growth.reward_rules(code,trigger_kind,reward_kind,reward_config,max_issues_per_account,status)
    values(lower(trim(p_code)),p_trigger_kind,p_reward_kind,p_reward_config,p_max_issues_per_account,p_status)
    returning * into v_rule;
    v_response:=jsonb_build_object('httpStatus',201,'code','ok','id',v_rule.id,'version',v_rule.version,'status',v_rule.status,'replayed',false);
  else
    select * into v_rule from growth.reward_rules where id=p_rule_id for update;
    if not found then
      v_response:=jsonb_build_object('httpStatus',404,'code','reward_rule_not_found','message','Reward rule was not found.','replayed',false);
    elsif p_expected_version is null or v_rule.version<>p_expected_version then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_rule_version_conflict','message','Reward rule changed; refresh before updating.','currentVersion',v_rule.version,'replayed',false);
    else
      update growth.reward_rules set
        code=lower(trim(p_code)),trigger_kind=p_trigger_kind,reward_kind=p_reward_kind,
        reward_config=p_reward_config,max_issues_per_account=p_max_issues_per_account,status=p_status,
        version=version+1,updated_at_utc=now()
      where id=p_rule_id returning * into v_rule;
      v_response:=jsonb_build_object('httpStatus',200,'code','ok','id',v_rule.id,'version',v_rule.version,'status',v_rule.status,'replayed',false);
    end if;
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'growth_reward_rule',coalesce(v_rule.id,p_rule_id)::text,
    case when (v_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('code',v_response->>'code','ruleCode',lower(trim(p_code)),'rewardKind',p_reward_kind,'triggerKind',p_trigger_kind));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
exception when unique_violation then
  raise exception using errcode='23505',message='Reward rule code already exists.';
end $$;
revoke all on function growth.upsert_reward_rule(uuid,uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;
grant execute on function growth.upsert_reward_rule(uuid,uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

create or replace function growth.review_advocacy_submission(
  p_actor_account_id uuid,
  p_submission_id uuid,
  p_expected_version bigint,
  p_decision varchar,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,admin,pg_temp
as $$
declare
  v_operation constant varchar:='growth.advocacy.review';
  v_existing admin.idempotency_keys%rowtype;
  v_submission growth.advocacy_submissions%rowtype;
  v_next varchar;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if lower(trim(coalesce(p_decision,''))) not in ('verify','reject') or p_expected_version is null or p_expected_version<1
     or p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','advocacy_review_invalid','message','Advocacy review fields are invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key conflict.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  select * into v_submission from growth.advocacy_submissions where id=p_submission_id for update;
  if not found then
    v_response:=jsonb_build_object('httpStatus',404,'code','advocacy_submission_not_found','message','Advocacy submission was not found.','replayed',false);
  elsif v_submission.version<>p_expected_version then
    v_response:=jsonb_build_object('httpStatus',409,'code','advocacy_version_conflict','message','Advocacy submission changed; refresh before review.','currentVersion',v_submission.version,'replayed',false);
  elsif v_submission.status<>'PendingReview' then
    v_response:=jsonb_build_object('httpStatus',409,'code','advocacy_state_conflict','message','Only pending advocacy submissions may be reviewed.','replayed',false);
  else
    v_next:=case lower(trim(p_decision)) when 'verify' then 'Verified' else 'Rejected' end;
    update growth.advocacy_submissions set status=v_next,reviewed_by_account_id=p_actor_account_id,
      reviewed_at_utc=now(),version=version+1,updated_at_utc=now()
    where id=p_submission_id returning * into v_submission;
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','id',v_submission.id,'status',v_submission.status,'version',v_submission.version,'replayed',false);
  end if;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'growth_advocacy_submission',p_submission_id::text,
    case when (v_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('code',v_response->>'code','decision',lower(trim(p_decision))));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;
revoke all on function growth.review_advocacy_submission(uuid,uuid,bigint,varchar,varchar,uuid,varchar,varchar) from public,anon,authenticated;
grant execute on function growth.review_advocacy_submission(uuid,uuid,bigint,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

create or replace function growth.execute_reward_issue(
  p_actor_account_id uuid,
  p_beneficiary_account_id uuid,
  p_source_kind varchar,
  p_source_id uuid,
  p_reward_rule_id uuid,
  p_expected_rule_version bigint,
  p_provenance_hash varchar,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,growth,admin,commerce,identity,pg_temp
as $$
declare
  v_operation constant varchar:='growth.reward.issue';
  v_existing admin.idempotency_keys%rowtype;
  v_existing_event growth.reward_events%rowtype;
  v_rule growth.reward_rules%rowtype;
  v_preview jsonb;
  v_approval jsonb;
  v_event growth.reward_events%rowtype;
  v_ids uuid[];
  v_expiry timestamptz;
  v_response jsonb;
  v_fulfillment varchar:='Fulfilled';
  v_status varchar:='Issued';
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_issue_invalid','message','Reward issuance metadata is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key conflict.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_preview:=growth.preview_reward_issue(p_beneficiary_account_id,p_source_kind,p_source_id,p_reward_rule_id,p_expected_rule_version,p_provenance_hash);
  if coalesce((v_preview->>'httpStatus')::int,500)>=400 then
    v_response:=v_preview||jsonb_build_object('replayed',false);
  else
    select * into v_rule from growth.reward_rules where id=p_reward_rule_id for update;
    v_approval:=admin.consume_approval_request(p_actor_account_id,p_approval_request_id,p_approval_expected_version,v_operation,p_correlation_id);
    if v_approval->>'requestType'<>'growth_reward_issue'
       or v_approval->>'targetType'<>'account'
       or v_approval->>'targetId'<>p_beneficiary_account_id::text
       or coalesce(v_approval->'delta','{}'::jsonb)<>coalesce(v_preview->'delta','{}'::jsonb) then
      raise exception using errcode='55000',message='Reward approval snapshot no longer matches the requested issuance.';
    end if;

    if v_rule.reward_kind='GiftEntitlement' then
      v_expiry:=(v_rule.reward_config->>'expiresAtUtc')::timestamptz;
      if v_expiry<=now() then raise exception using errcode='55000',message='Gift entitlement reward has expired.'; end if;
      select commerce.apply_manual_entitlement_grant_guarded(
        p_actor_account_id,p_beneficiary_account_id,v_rule.reward_config->>'targetType',
        (v_rule.reward_config->>'targetId')::uuid,v_expiry,gen_random_uuid()
      ) into v_ids;
    elsif v_rule.reward_kind='Discount' then
      -- There is no account-bound discount fulfillment primitive yet. Keep the
      -- reward truthfully pending instead of fabricating an issued/redeemable code.
      v_status:='Pending';
      v_fulfillment:='PendingFulfillment';
    end if;

    insert into growth.reward_events(
      beneficiary_account_id,source_kind,source_id,reward_rule_id,reward_rule_version,reward_kind,status,
      provenance_hash,reward_reference_hash,approval_request_id,issued_by_account_id,correlation_id,
      idempotency_key,request_hash,fulfillment_state,fulfillment_metadata_json,issued_at_utc
    ) values(
      p_beneficiary_account_id,p_source_kind,p_source_id,v_rule.id,v_rule.version,v_rule.reward_kind,v_status,
      lower(p_provenance_hash),case when v_ids is null then null else encode(digest(array_to_string(v_ids,','),'sha256'),'hex') end,
      p_approval_request_id,p_actor_account_id,p_correlation_id,p_idempotency_key,p_request_hash,v_fulfillment,
      case when v_ids is null then '{}'::jsonb else jsonb_build_object('entitlementCount',cardinality(v_ids)) end,
      case when v_status='Issued' then now() else null end
    ) returning * into v_event;

    if p_source_kind='Advocacy' and v_status='Issued' then
      update growth.advocacy_submissions set status='Rewarded',version=version+1,updated_at_utc=now() where id=p_source_id and status='Verified';
    elsif p_source_kind='Referral' and v_status='Issued' then
      update growth.referral_attributions set status='Rewarded',rewarded_at_utc=now(),rule_version=v_rule.version where id=p_source_id and status in ('Attributed','Qualified');
    end if;

    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,v_operation,'growth_reward_event',v_event.id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('beneficiaryAccountId',p_beneficiary_account_id,'sourceKind',p_source_kind,'rewardKind',v_rule.reward_kind,'status',v_event.status,'fulfillmentState',v_event.fulfillment_state));
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','rewardEventId',v_event.id,'status',v_event.status,'rewardKind',v_event.reward_kind,'fulfillmentState',v_event.fulfillment_state,'replayed',false);
  end if;

  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;
revoke all on function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated;
grant execute on function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

comment on function growth.execute_reward_issue(uuid,uuid,varchar,uuid,uuid,bigint,varchar,uuid,bigint,varchar,uuid,varchar,varchar)
is 'Reviewed reward issuance. Consumes the canonical approval snapshot transactionally; GiftEntitlement reuses the guarded #492 entitlement primitive and Discount remains PendingFulfillment until an account-bound canonical fulfillment primitive exists.';

commit;
