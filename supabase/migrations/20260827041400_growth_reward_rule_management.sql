begin;

create or replace function admin.upsert_growth_reward_rule(
  p_actor_account_id uuid,
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
set search_path=pg_catalog,admin,growth,extensions,pg_temp
as $$
declare
  v_operation constant varchar := 'growth.reward_rule.upsert';
  v_existing_idempotency admin.idempotency_keys%rowtype;
  v_existing growth.reward_rules%rowtype;
  v_row growth.reward_rules%rowtype;
  v_side text;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_trigger_kind not in ('Referral','Advocacy','Gift','Campaign')
     or p_reward_kind not in ('Discount','GiftEntitlement','RaffleEligibility','CharityImpact')
     or p_reward_config is null or jsonb_typeof(p_reward_config)<>'object'
     or octet_length(p_reward_config::text)>4096
     or (p_max_issues_per_account is not null and p_max_issues_per_account not between 1 and 100000)
     or p_status not in ('Draft','Active','Paused','Retired')
     or p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_correlation_id is null
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_rule_request_invalid','message','Reward rule request is invalid.','replayed',false);
  end if;

  v_side:=coalesce(p_reward_config->>'beneficiarySide','');
  if (p_trigger_kind='Referral' and v_side not in ('Referrer','Referred'))
     or (p_trigger_kind='Gift' and v_side not in ('Purchaser','Recipient'))
     or (p_trigger_kind='Advocacy' and v_side not in ('','Owner')) then
    return jsonb_build_object('httpStatus',400,'code','reward_rule_beneficiary_invalid','message','Reward beneficiary semantics are invalid.','replayed',false);
  end if;
  -- Campaign reward source/beneficiary semantics are owned by #495/#191 and are
  -- not active until a canonical per-account campaign eligibility fact exists.
  if p_trigger_kind='Campaign' and p_status='Active' then
    return jsonb_build_object('httpStatus',409,'code','campaign_reward_source_unavailable','message','Campaign rewards cannot be activated until canonical campaign eligibility is available.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing_idempotency from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
  for update;
  if found then
    if v_existing_idempotency.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing_idempotency.status='Completed' and v_existing_idempotency.response_json is not null then
      return v_existing_idempotency.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  perform pg_advisory_xact_lock(hashtextextended('growth.reward_rule:'||p_code,0));
  select * into v_existing from growth.reward_rules where code=p_code for update;
  if found then
    if p_expected_version is null or p_expected_version<>v_existing.version then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_rule_version_conflict','message','Reward rule changed.','replayed',false);
    else
      update growth.reward_rules set
        trigger_kind=p_trigger_kind,reward_kind=p_reward_kind,reward_config=p_reward_config,
        max_issues_per_account=p_max_issues_per_account,status=p_status,
        version=version+1,updated_at_utc=now()
      where id=v_existing.id returning * into v_row;
    end if;
  else
    if p_expected_version is not null and p_expected_version<>0 then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_rule_version_conflict','message','Reward rule does not exist at the expected version.','replayed',false);
    else
      insert into growth.reward_rules(
        code,trigger_kind,reward_kind,reward_config,max_issues_per_account,status,version
      ) values(
        p_code,p_trigger_kind,p_reward_kind,p_reward_config,p_max_issues_per_account,p_status,1
      ) returning * into v_row;
    end if;
  end if;

  if v_response is null then
    v_response:=jsonb_build_object(
      'httpStatus',case when v_existing.id is null then 201 else 200 end,
      'code','ok','ruleId',v_row.id,'ruleCode',v_row.code,'triggerKind',v_row.trigger_kind,
      'rewardKind',v_row.reward_kind,'status',v_row.status,'version',v_row.version,
      'maxIssuesPerAccount',v_row.max_issues_per_account,'replayed',false
    );
  end if;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,
    request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,v_operation,'growth_reward_rule',p_code,
    case when coalesce((v_response->>'httpStatus')::integer,500)<400 then 'Succeeded' else 'Denied' end,
    trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object(
      'code',v_response->>'code','triggerKind',p_trigger_kind,'rewardKind',p_reward_kind,
      'status',p_status,'version',coalesce(v_row.version,v_existing.version)
    )
  );
  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.upsert_growth_reward_rule(uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function admin.upsert_growth_reward_rule(uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

comment on function admin.upsert_growth_reward_rule(uuid,varchar,varchar,varchar,jsonb,integer,varchar,bigint,varchar,uuid,varchar,varchar) is
  'Audited optimistic-concurrency mutation for bounded growth reward rules. Campaign rules cannot be Active before a canonical campaign reward source exists.';

commit;
