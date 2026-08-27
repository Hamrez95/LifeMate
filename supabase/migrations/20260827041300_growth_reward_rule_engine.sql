begin;

-- #494 reviewed reward engine. A reward event is an auditable eligibility/
-- issuance request, not proof that an external discount, entitlement, raffle or
-- charity side-effect has already happened. Side effects stay Pending until a
-- purpose-specific canonical executor records real evidence.
create or replace function admin.create_growth_reward_event(
  p_actor_account_id uuid,
  p_beneficiary_account_id uuid,
  p_source_kind varchar,
  p_source_id uuid,
  p_rule_code varchar,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,admin,growth,commerce,security,extensions,pg_temp
as $$
declare
  v_operation constant varchar := 'growth.reward.create';
  v_existing admin.idempotency_keys%rowtype;
  v_rule growth.reward_rules%rowtype;
  v_event growth.reward_events%rowtype;
  v_side text;
  v_source_ok boolean:=false;
  v_abuse jsonb;
  v_abuse_action text;
  v_abuse_id uuid;
  v_issued_count integer;
  v_provenance varchar(128);
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'growth.rewards.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_beneficiary_account_id is null or p_source_id is null
     or p_source_kind not in ('Referral','Advocacy','Gift')
     or p_rule_code is null or p_rule_code !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_correlation_id is null
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','reward_request_invalid','message','Reward request is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key
  for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_rule from growth.reward_rules
  where code=p_rule_code and status='Active' and trigger_kind=p_source_kind
  for share;
  if not found then
    v_response:=jsonb_build_object('httpStatus',404,'code','reward_rule_unavailable','message','The reward rule is unavailable.','replayed',false);
  else
    -- Beneficiary semantics are explicit in rule configuration. Never infer who
    -- receives a reward from a relationship or campaign label.
    v_side:=coalesce(v_rule.reward_config->>'beneficiarySide','');
    if p_source_kind='Referral' then
      if v_side not in ('Referrer','Referred') then
        v_response:=jsonb_build_object('httpStatus',409,'code','reward_rule_configuration_invalid','message','Referral beneficiary semantics are not configured.','replayed',false);
      else
        perform 1 from growth.referral_attributions ra where ra.id=p_source_id for update;
        if found then
          select exists(
            select 1 from growth.referral_attributions ra
            where ra.id=p_source_id and ra.status in ('Qualified','Rewarded')
              and p_beneficiary_account_id=case when v_side='Referrer' then ra.referrer_account_id else ra.referred_account_id end
          ) into v_source_ok;
        end if;
      end if;
    elsif p_source_kind='Advocacy' then
      if v_side not in ('Owner','') then
        v_response:=jsonb_build_object('httpStatus',409,'code','reward_rule_configuration_invalid','message','Advocacy beneficiary semantics are invalid.','replayed',false);
      else
        perform 1 from growth.advocacy_submissions a where a.id=p_source_id for update;
        if found then
          select exists(
            select 1 from growth.advocacy_submissions a
            where a.id=p_source_id and a.status in ('Verified','Rewarded')
              and a.account_id=p_beneficiary_account_id
          ) into v_source_ok;
        end if;
      end if;
    elsif p_source_kind='Gift' then
      if v_side not in ('Purchaser','Recipient') then
        v_response:=jsonb_build_object('httpStatus',409,'code','reward_rule_configuration_invalid','message','Gift beneficiary semantics are not configured.','replayed',false);
      else
        perform 1 from commerce.gift_intents g where g.id=p_source_id for update;
        if found then
          select exists(
            select 1 from commerce.gift_intents g
            where g.id=p_source_id and g.status='Fulfilled'
              and p_beneficiary_account_id=case when v_side='Purchaser' then g.purchaser_account_id else g.recipient_account_id end
          ) into v_source_ok;
        end if;
      end if;
    end if;

    if v_response is null and not v_source_ok then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_source_not_eligible','message','The source is not eligible for this reward.','replayed',false);
    end if;
  end if;

  if v_response is null then
    select count(*)::integer into v_issued_count from growth.reward_events
    where beneficiary_account_id=p_beneficiary_account_id
      and reward_rule_id=v_rule.id and status<>'Rejected';
    if v_rule.max_issues_per_account is not null and v_issued_count>=v_rule.max_issues_per_account then
      v_response:=jsonb_build_object('httpStatus',409,'code','reward_issue_limit_reached','message','The reward issue limit has been reached.','replayed',false);
    end if;
  end if;

  if v_response is null then
    v_abuse:=security.evaluate_abuse_rules(
      p_actor_account_id,p_beneficiary_account_id,'reward.issue',
      p_source_kind||':'||p_source_id::text||':'||v_rule.code,
      array['reviewed_source']::varchar[],p_idempotency_key,p_request_hash
    );
    if coalesce((v_abuse->>'httpStatus')::integer,500)>=400 then
      v_response:=v_abuse || jsonb_build_object('replayed',false);
    else
      v_abuse_action:=v_abuse->>'action';
      v_abuse_id:=nullif(v_abuse->>'decisionId','')::uuid;
      if v_abuse_action='Deny' then
        v_response:=jsonb_build_object('httpStatus',429,'code','reward_rate_limited','message','The reward is not available right now.','replayed',false);
      elsif v_abuse_action='RequireApproval' then
        v_response:=jsonb_build_object('httpStatus',409,'code','reward_additional_review_required','message','The reward requires additional review.','replayed',false);
      end if;
    end if;
  end if;

  if v_response is null then
    v_provenance:=encode(extensions.digest(
      p_source_kind||':'||p_source_id::text||':'||v_rule.id::text||':'||v_rule.version::text||':'||p_beneficiary_account_id::text,
      'sha256'
    ),'hex');
    insert into growth.reward_events(
      beneficiary_account_id,source_kind,source_id,reward_rule_id,reward_rule_version,
      reward_kind,status,provenance_hash,abuse_decision_id
    ) values(
      p_beneficiary_account_id,p_source_kind,p_source_id,v_rule.id,v_rule.version,
      v_rule.reward_kind,'Pending',v_provenance,v_abuse_id
    )
    on conflict(source_kind,source_id,reward_rule_id,beneficiary_account_id) do nothing
    returning * into v_event;

    if v_event.id is null then
      select * into v_event from growth.reward_events
      where source_kind=p_source_kind and source_id=p_source_id
        and reward_rule_id=v_rule.id and beneficiary_account_id=p_beneficiary_account_id;
    end if;
    v_response:=jsonb_build_object(
      'httpStatus',201,'code','ok','rewardEventId',v_event.id,
      'rewardKind',v_event.reward_kind,'status',v_event.status,
      'ruleVersion',v_event.reward_rule_version,'replayed',false
    );
    perform security.record_abuse_event(
      p_actor_account_id,'reward.issue',p_source_kind||':'||p_source_id::text,'reward_event_created'
    );
  end if;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,
    request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,v_operation,'growth_reward_source',p_source_kind||':'||p_source_id::text,
    case when coalesce((v_response->>'httpStatus')::integer,500)<400 then 'Succeeded' else 'Denied' end,
    trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object(
      'code',v_response->>'code','beneficiaryAccountIdHash',
      encode(extensions.digest(p_beneficiary_account_id::text,'sha256'),'hex'),
      'ruleCode',p_rule_code,'sourceKind',p_source_kind
    )
  );
  update admin.idempotency_keys
  set status='Completed',response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function admin.create_growth_reward_event(uuid,uuid,varchar,uuid,varchar,varchar,uuid,varchar,varchar) from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function admin.create_growth_reward_event(uuid,uuid,varchar,uuid,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

comment on function admin.create_growth_reward_event(uuid,uuid,varchar,uuid,varchar,varchar,uuid,varchar,varchar) is
  'Creates an audited Pending reward event from an explicitly eligible reviewed source. It never claims that discount, entitlement, raffle or charity side effects have already occurred.';

commit;
