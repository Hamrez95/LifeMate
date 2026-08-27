begin;

create or replace function messaging.prepare_campaign_execution(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_snapshot_id uuid,
  p_campaign_updated_at_utc timestamptz,
  p_channels varchar[],
  p_sms_provider varchar,
  p_sms_currency varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,marketing,audience,consent,identity,admin,pg_temp
as $$
declare
  v_campaign marketing.campaigns%rowtype;
  v_snapshot audience.segment_snapshots%rowtype;
  v_execution uuid;
  v_audience integer;
  v_eligible_sms integer:=0;
  v_eligible_push integer:=0;
  v_opt_sms integer:=0;
  v_opt_push integer:=0;
  v_cost_per_sms bigint;
  v_cost bigint;
  v_currency varchar(3);
  v_second boolean:=false;
  v_message_sms uuid;
  v_message_push uuid;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  if p_channels is null or cardinality(p_channels)<1 or cardinality(p_channels)>2
     or exists(select 1 from unnest(p_channels) c where c not in ('SMS','Push'))
     or cardinality(array(select distinct c from unnest(p_channels) c))<>cardinality(p_channels) then
    return jsonb_build_object('httpStatus',400,'code','campaign_channels_invalid','message','Campaign channels are invalid.');
  end if;

  select * into v_campaign from marketing.campaigns where id=p_campaign_id for share;
  if not found then return jsonb_build_object('httpStatus',404,'code','campaign_not_found','message','Campaign was not found.'); end if;
  if v_campaign.updated_at_utc<>p_campaign_updated_at_utc then
    return jsonb_build_object('httpStatus',409,'code','campaign_version_conflict','message','Campaign changed before execution preparation.');
  end if;
  if v_campaign.status not in ('Ready','Active') then
    return jsonb_build_object('httpStatus',409,'code','campaign_not_sendable','message','Campaign is not ready to send.');
  end if;

  select * into v_snapshot from audience.segment_snapshots where id=p_snapshot_id for share;
  if not found then return jsonb_build_object('httpStatus',404,'code','audience_snapshot_not_found','message','Audience snapshot was not found.'); end if;
  v_audience:=v_snapshot.member_count;
  -- First production-safe ceiling. Raise only from measured capacity evidence.
  if v_audience>10000 then
    return jsonb_build_object('httpStatus',409,'code','campaign_audience_too_large','message','Audience exceeds the currently evidenced execution ceiling.');
  end if;

  if 'SMS'=any(p_channels) then
    select id into v_message_sms from messaging.campaign_messages
    where campaign_id=p_campaign_id and channel='SMS' and status='Active';
    if v_message_sms is null then return jsonb_build_object('httpStatus',409,'code','campaign_sms_message_missing','message','Active SMS content is required.'); end if;
  end if;
  if 'Push'=any(p_channels) then
    select id into v_message_push from messaging.campaign_messages
    where campaign_id=p_campaign_id and channel='Push' and status='Active';
    if v_message_push is null then return jsonb_build_object('httpStatus',409,'code','campaign_push_message_missing','message','Active Push content is required.'); end if;
  end if;

  select coalesce((value_json #>> '{}')::boolean,false) into v_second
  from messaging.campaign_policies where policy_key='second_confirmation.enabled' and status='Active';
  v_second:=coalesce(v_second,false);

  create temporary table tmp_campaign_eligibility(
    account_id uuid primary key,
    sms_allowed boolean not null,
    sms_reachable boolean not null,
    push_allowed boolean not null,
    push_reachable boolean not null
  ) on commit drop;

  insert into tmp_campaign_eligibility(account_id,sms_allowed,sms_reachable,push_allowed,push_reachable)
  select
    m.account_id,
    case when 'SMS'=any(p_channels) then consent.account_allows_optional_purpose(m.account_id,'promotional_sms','GLOBAL') else false end,
    case when 'SMS'=any(p_channels) then exists(
      select 1 from identity.contact_points cp
      where cp.account_id=m.account_id and cp.kind='Phone' and cp.status='Verified' and cp.verified_at_utc is not null
    ) else false end,
    case when 'Push'=any(p_channels) then consent.account_allows_optional_purpose(m.account_id,'promotional_push','GLOBAL') else false end,
    case when 'Push'=any(p_channels) then exists(
      select 1 from messaging.push_registrations pr
      where pr.account_id=m.account_id
        and pr.product_code=v_campaign.product_code
        and pr.status='Active'
    ) else false end
  from audience.segment_snapshot_members m
  where m.snapshot_id=p_snapshot_id;

  if 'SMS'=any(p_channels) then
    select count(*) filter(where sms_allowed and sms_reachable),
           count(*) filter(where not sms_allowed)
    into v_eligible_sms,v_opt_sms from tmp_campaign_eligibility;
  end if;

  if 'Push'=any(p_channels) then
    select count(*) filter(where push_allowed and push_reachable),
           count(*) filter(where not push_allowed)
    into v_eligible_push,v_opt_push from tmp_campaign_eligibility;
  end if;

  if 'SMS'=any(p_channels) and p_sms_provider is not null and p_sms_currency is not null then
    select pp.cost_minor,pp.currency into v_cost_per_sms,v_currency
    from messaging.provider_pricing pp
    where pp.provider=p_sms_provider and pp.channel='SMS' and pp.currency=p_sms_currency and pp.status='Active'
      and pp.effective_from_utc<=now() and (pp.effective_to_utc is null or pp.effective_to_utc>now())
    order by pp.effective_from_utc desc limit 1;
    if v_cost_per_sms is not null then
      if v_eligible_sms>0 and v_cost_per_sms>9223372036854775807/v_eligible_sms then
        return jsonb_build_object('httpStatus',409,'code','campaign_cost_overflow','message','Estimated SMS cost exceeds supported bounds.');
      end if;
      v_cost:=v_cost_per_sms*v_eligible_sms;
    end if;
  end if;

  -- Persist the execution only after all bounded eligibility/cost validation has
  -- succeeded. Controlled 4xx exits above therefore cannot leave partial jobs.
  insert into messaging.campaign_executions(
    campaign_id,audience_snapshot_id,campaign_updated_at_utc,status,audience_count,
    eligible_sms_count,eligible_push_count,opted_out_sms_count,opted_out_push_count,
    estimated_sms_cost_minor,estimated_sms_cost_currency,
    requires_second_confirmation,created_by_account_id
  ) values(
    p_campaign_id,p_snapshot_id,p_campaign_updated_at_utc,
    case when v_second then 'ApprovalPending' else 'Prepared' end,v_audience,
    v_eligible_sms,v_eligible_push,v_opt_sms,v_opt_push,v_cost,v_currency,
    v_second,p_actor_account_id
  ) returning id into v_execution;

  if 'SMS'=any(p_channels) then
    insert into messaging.delivery_jobs(execution_id,account_id,channel,message_id,status,suppression_reason)
    select v_execution,e.account_id,'SMS',v_message_sms,
      case when e.sms_allowed and e.sms_reachable then 'Pending' else 'Suppressed' end,
      case when e.sms_allowed and e.sms_reachable then null
           when not e.sms_allowed then 'OptedOut' else 'NoReachableAddress' end
    from tmp_campaign_eligibility e;
  end if;

  if 'Push'=any(p_channels) then
    insert into messaging.delivery_jobs(execution_id,account_id,channel,message_id,status,suppression_reason)
    select v_execution,e.account_id,'Push',v_message_push,
      case when e.push_allowed and e.push_reachable then 'Pending' else 'Suppressed' end,
      case when e.push_allowed and e.push_reachable then null
           when not e.push_allowed then 'OptedOut' else 'NoReachableAddress' end
    from tmp_campaign_eligibility e;
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'marketing.campaign.prepare','campaign_execution',v_execution::text,'Succeeded',p_correlation_id,false,
    jsonb_build_object('campaignId',p_campaign_id,'snapshotId',p_snapshot_id,'audienceCount',v_audience,'eligibleSms',v_eligible_sms,'eligiblePush',v_eligible_push,'requiresSecondConfirmation',v_second));

  return jsonb_build_object(
    'httpStatus',201,'code','ok','executionId',v_execution,
    'status',case when v_second then 'ApprovalPending' else 'Prepared' end,
    'audienceCount',v_audience,'eligibleSmsCount',v_eligible_sms,'eligiblePushCount',v_eligible_push,
    'optedOutSmsCount',v_opt_sms,'optedOutPushCount',v_opt_push,
    'estimatedSmsCostMinor',v_cost,'estimatedSmsCostCurrency',v_currency,
    'requiresSecondConfirmation',v_second
  );
exception when others then
  -- Temporary eligibility state is transaction-local. Any database failure rolls
  -- the preparation transaction back rather than leaving a partial execution.
  raise;
end $$;

revoke all on function messaging.prepare_campaign_execution(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid) from public;
grant execute on function messaging.prepare_campaign_execution(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid) to lifemate_admin_runtime;

commit;
