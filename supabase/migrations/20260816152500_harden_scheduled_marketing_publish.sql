begin;

create or replace function admin.request_marketing_campaign_publish(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = admin, marketing, integration, pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.publish:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_execution_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.social.publish') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required high-risk marketing permission is not granted.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
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

  select * into v_campaign from marketing.campaigns where id=p_campaign_id for update;
  select * into v_content from marketing.campaign_content where campaign_id=p_campaign_id for update;

  if v_campaign.id is null then
    v_response := jsonb_build_object('httpStatus',404,'code','marketing_campaign_not_found','message','Campaign was not found.','replayed',false);
  elsif v_campaign.status not in ('Ready','Active') then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_not_publishable','message','Campaign lifecycle is not publishable.','replayed',false);
  elsif v_content.campaign_id is null or v_content.approval_state<>'Approved' or v_content.approved_revision is distinct from v_content.content_revision then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_approval_required','message','The current content revision requires human approval.','replayed',false);
  elsif v_campaign.channel_code is null then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_channel_missing','message','Campaign channel is not configured.','replayed',false);
  elsif not exists(select 1 from marketing.channel_connections c where c.provider_code=v_campaign.channel_code and c.operator_status='Enabled') then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_channel_disabled','message','Campaign channel is disabled or unavailable.','replayed',false);
  elsif not admin.marketing_channel_credential_available(v_campaign.channel_code) then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_channel_setup_required','message','Campaign channel credential is not available.','replayed',false);
  elsif exists(
    select 1 from marketing.campaign_publish_executions e
    where e.campaign_id=p_campaign_id and e.provider_code=v_campaign.channel_code
      and e.content_revision=v_content.content_revision
      and e.status in ('Scheduled','Queued','Processing','Published','OutcomeUnknown')
  ) then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_publish_duplicate_guard','message','This approved content revision already has a protected publish execution.','replayed',false);
  else
    v_execution_id := gen_random_uuid();
    insert into marketing.campaign_publish_executions(
      id,campaign_id,provider_code,content_revision,status,requested_by_admin_account_id,request_id,correlation_id
    ) values(v_execution_id,p_campaign_id,v_campaign.channel_code,v_content.content_revision,'Queued',p_actor_account_id,p_idempotency_key,p_correlation_id);
    insert into marketing.campaign_publish_execution_events(execution_id,event_type)
    values(v_execution_id,'Queued');
    insert into integration.outbox_messages(
      aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
    ) values(
      'marketing_campaign',p_campaign_id,'marketing.campaign_publish_requested',
      'marketing-publish:'||v_execution_id::text,
      jsonb_build_object('executionId',v_execution_id),'Pending',now()
    );
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,'marketing.campaign.publish.request','marketing_campaign',p_campaign_id::text,'Succeeded',trim(p_reason),p_correlation_id,p_idempotency_key,false,jsonb_build_object('executionId',v_execution_id,'providerCode',v_campaign.channel_code,'contentRevision',v_content.content_revision,'providerConnectivity','NotVerified'));
    v_response := jsonb_build_object('httpStatus',202,'code','ok','campaignId',p_campaign_id,'executionId',v_execution_id,'publishStatus','Queued','providerConnectivity','NotVerified','replayed',false);
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(p_actor_account_id,'marketing.campaign.publish.request','marketing_campaign',p_campaign_id::text,'Denied',coalesce(v_response->>'message','Campaign publish request denied'),p_correlation_id,p_idempotency_key,false,jsonb_build_object('code',v_response->>'code'));
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function marketing.claim_campaign_publish_execution(p_execution_id uuid)
returns table(
  execution_id uuid,
  campaign_id uuid,
  provider_code varchar,
  publish_text varchar,
  asset_refs jsonb,
  credential_secret_name varchar
)
language plpgsql
security definer
set search_path = marketing, admin, pg_temp
as $$
declare
  v_execution marketing.campaign_publish_executions%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_secret_name varchar;
  v_failure varchar;
begin
  select * into v_execution
  from marketing.campaign_publish_executions
  where id=p_execution_id
  for update;

  if not found then return; end if;

  -- Preserve the original duplicate-side-effect hardening. A second claim of an
  -- already Processing execution is ambiguous and must never publish again.
  if v_execution.status='Processing' then
    update marketing.campaign_publish_executions
      set status='OutcomeUnknown',failure_code='previous_attempt_outcome_unknown',completed_at_utc=now()
      where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type,code)
      values(p_execution_id,'OutcomeUnknown','previous_attempt_outcome_unknown');
    return;
  end if;

  if v_execution.status='Scheduled' then
    if v_execution.scheduled_for_utc is null or v_execution.scheduled_for_utc>now() then return; end if;
    update marketing.campaign_publish_executions set status='Queued' where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type)
      values(p_execution_id,'Queued');
    v_execution.status := 'Queued';
  end if;

  if v_execution.status<>'Queued' then return; end if;

  select * into v_campaign from marketing.campaigns where id=v_execution.campaign_id;
  select * into v_content from marketing.campaign_content where campaign_id=v_execution.campaign_id;
  select credential_secret_name into v_secret_name
  from marketing.channel_connections
  where provider_code=v_execution.provider_code and operator_status='Enabled';

  if v_campaign.status not in ('Ready','Active') then
    v_failure := 'campaign_not_publishable';
  elsif v_content.approval_state<>'Approved'
     or v_content.approved_revision is distinct from v_execution.content_revision
     or v_content.content_revision is distinct from v_execution.content_revision then
    v_failure := 'approval_changed';
  elsif v_secret_name is null
     or not admin.marketing_channel_credential_available(v_execution.provider_code) then
    v_failure := 'provider_not_configured';
  end if;

  if v_failure is not null then
    update marketing.campaign_publish_executions
      set status='Failed',completed_at_utc=now(),failure_code=v_failure
      where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type,code)
      values(p_execution_id,'Failed',v_failure);
    return;
  end if;

  update marketing.campaign_publish_executions
    set status='Processing',started_at_utc=now(),failure_code=null
    where id=p_execution_id;
  insert into marketing.campaign_publish_execution_events(execution_id,event_type)
    values(p_execution_id,'Processing');

  return query
  select v_execution.id,v_execution.campaign_id,v_execution.provider_code,
         v_content.publish_text,v_content.asset_refs,v_secret_name;
end
$$;

revoke all on function admin.request_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) from public;
revoke all on function marketing.claim_campaign_publish_execution(uuid) from public;
grant execute on function admin.request_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function marketing.claim_campaign_publish_execution(uuid) to lifemate_worker_runtime;

comment on function marketing.claim_campaign_publish_execution(uuid) is
  'Claims immediate or due scheduled publish executions while preserving fail-closed OutcomeUnknown behavior for ambiguous repeated Processing claims.';

commit;
