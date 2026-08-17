begin;

alter table marketing.campaign_publish_executions
  add column if not exists scheduled_for_utc timestamptz,
  add column if not exists schedule_timezone varchar(64),
  add column if not exists cancelled_at_utc timestamptz,
  add column if not exists retry_of_execution_id uuid references marketing.campaign_publish_executions(id) on delete set null;

alter table marketing.campaign_publish_executions
  drop constraint if exists campaign_publish_executions_status_check;
alter table marketing.campaign_publish_executions
  add constraint campaign_publish_executions_status_check
  check (status in ('Scheduled','Queued','Processing','Published','Failed','OutcomeUnknown','Cancelled'));

alter table marketing.campaign_publish_executions
  drop constraint if exists marketing_campaign_publish_schedule_state_check;
alter table marketing.campaign_publish_executions
  add constraint marketing_campaign_publish_schedule_state_check
  check (
    (status <> 'Scheduled' or scheduled_for_utc is not null)
    and (status <> 'Cancelled' or cancelled_at_utc is not null)
    and (schedule_timezone is null or length(schedule_timezone) between 1 and 64)
  );

alter table marketing.campaign_publish_execution_events
  drop constraint if exists campaign_publish_execution_events_event_type_check;
alter table marketing.campaign_publish_execution_events
  add constraint campaign_publish_execution_events_event_type_check
  check (event_type in ('Scheduled','Queued','Processing','Published','Failed','OutcomeUnknown','Cancelled'));

drop index if exists marketing.uq_marketing_campaign_publish_revision_guard;
create unique index uq_marketing_campaign_publish_revision_guard
  on marketing.campaign_publish_executions(campaign_id, provider_code, content_revision)
  where status in ('Scheduled','Queued','Processing','Published','OutcomeUnknown');

create index if not exists ix_marketing_campaign_publish_schedule
  on marketing.campaign_publish_executions(scheduled_for_utc, id)
  where status='Scheduled';

create or replace view admin.marketing_content_calendar_v1
with (security_invoker=false)
as
select
  e.id as execution_id,
  e.campaign_id,
  c.name as campaign_name,
  c.status as campaign_status,
  e.provider_code,
  e.content_revision,
  cc.approval_state,
  e.status as publish_status,
  e.scheduled_for_utc,
  e.schedule_timezone,
  e.requested_at_utc,
  e.started_at_utc,
  e.completed_at_utc,
  e.cancelled_at_utc,
  e.failure_code,
  e.provider_post_ref,
  e.retry_of_execution_id
from marketing.campaign_publish_executions e
join marketing.campaigns c on c.id=e.campaign_id
left join marketing.campaign_content cc on cc.campaign_id=e.campaign_id;

create or replace view admin.marketing_content_approval_queue_v1
with (security_invoker=false)
as
select
  c.id as campaign_id,
  c.name as campaign_name,
  c.status as campaign_status,
  c.channel_code as provider_code,
  cc.content_revision,
  cc.approval_state,
  cc.updated_at_utc,
  cc.approved_at_utc,
  left(coalesce(cc.publish_text,''),240) as publish_text_preview
from marketing.campaigns c
join marketing.campaign_content cc on cc.campaign_id=c.id
where c.status not in ('Completed','Cancelled')
order by
  case cc.approval_state when 'Pending' then 0 when 'Revoked' then 1 else 2 end,
  cc.updated_at_utc desc,
  c.id;

revoke all on admin.marketing_content_calendar_v1 from public;
revoke all on admin.marketing_content_approval_queue_v1 from public;
grant select on admin.marketing_content_calendar_v1 to lifemate_admin_runtime;
grant select on admin.marketing_content_approval_queue_v1 to lifemate_admin_runtime;

create or replace function admin.schedule_marketing_campaign_publish(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_scheduled_local timestamp without time zone,
  p_schedule_timezone varchar,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=admin,marketing,integration,pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.publish.schedule:' || p_campaign_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_execution_id uuid;
  v_scheduled_for timestamptz;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.social.publish')
     or not admin.account_has_permission(p_actor_account_id,'marketing.campaign.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','Scheduling requires campaign write and high-risk social publish permissions.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','marketing_campaign_reason_invalid','message','A reason between 10 and 1000 characters is required.','replayed',false);
  end if;
  if p_scheduled_local is null or p_schedule_timezone is null or length(p_schedule_timezone)>64
     or not exists(select 1 from pg_timezone_names where name=p_schedule_timezone) then
    return jsonb_build_object('httpStatus',400,'code','marketing_schedule_timezone_invalid','message','Schedule timezone or local time is invalid.','replayed',false);
  end if;
  v_scheduled_for := p_scheduled_local at time zone p_schedule_timezone;
  if v_scheduled_for < now()+interval '1 minute' or v_scheduled_for > now()+interval '365 days' then
    return jsonb_build_object('httpStatus',400,'code','marketing_schedule_time_invalid','message','Schedule time must be between one minute and 365 days in the future.','replayed',false);
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
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_approval_required','message','The current content revision requires human approval before scheduling.','replayed',false);
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
      id,campaign_id,provider_code,content_revision,status,requested_by_admin_account_id,
      request_id,correlation_id,scheduled_for_utc,schedule_timezone
    ) values(
      v_execution_id,p_campaign_id,v_campaign.channel_code,v_content.content_revision,'Scheduled',p_actor_account_id,
      p_idempotency_key,p_correlation_id,v_scheduled_for,p_schedule_timezone
    );
    insert into marketing.campaign_publish_execution_events(execution_id,event_type)
    values(v_execution_id,'Scheduled');
    insert into integration.outbox_messages(
      aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
    ) values(
      'marketing_campaign',p_campaign_id,'marketing.campaign_publish_requested',
      'marketing-publish:'||v_execution_id::text,
      jsonb_build_object('executionId',v_execution_id),'Pending',v_scheduled_for
    );
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(
      p_actor_account_id,'marketing.campaign.publish.schedule','marketing_campaign',p_campaign_id::text,'Succeeded',trim(p_reason),
      p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('executionId',v_execution_id,'providerCode',v_campaign.channel_code,'contentRevision',v_content.content_revision,'scheduledForUtc',v_scheduled_for,'scheduleTimezone',p_schedule_timezone,'providerConnectivity','NotVerified')
    );
    v_response := jsonb_build_object(
      'httpStatus',202,'code','ok','campaignId',p_campaign_id,'executionId',v_execution_id,
      'publishStatus','Scheduled','scheduledForUtc',v_scheduled_for,'scheduleTimezone',p_schedule_timezone,
      'providerConnectivity','NotVerified','replayed',false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(
      p_actor_account_id,'marketing.campaign.publish.schedule','marketing_campaign',p_campaign_id::text,'Denied',
      coalesce(v_response->>'message','Campaign schedule denied'),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('code',v_response->>'code','scheduleTimezone',p_schedule_timezone)
    );
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.cancel_marketing_campaign_publish(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=admin,marketing,integration,pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.publish.cancel:' || p_execution_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_execution marketing.campaign_publish_executions%rowtype;
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

  select * into v_execution from marketing.campaign_publish_executions where id=p_execution_id for update;
  if not found then
    v_response := jsonb_build_object('httpStatus',404,'code','marketing_publish_execution_not_found','message','Publish execution was not found.','replayed',false);
  elsif v_execution.status <> 'Scheduled' then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_publish_not_cancellable','message','Only a scheduled execution can be cancelled before dispatch.','replayed',false);
  else
    update marketing.campaign_publish_executions
      set status='Cancelled',cancelled_at_utc=now(),completed_at_utc=now(),failure_code=null
      where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type)
      values(p_execution_id,'Cancelled');
    update integration.outbox_messages
      set available_at_utc=least(available_at_utc,now())
      where event_type='marketing.campaign_publish_requested'
        and payload_json->>'executionId'=p_execution_id::text
        and status='Pending';
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(
      p_actor_account_id,'marketing.campaign.publish.cancel','marketing_campaign',v_execution.campaign_id::text,'Succeeded',trim(p_reason),
      p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('executionId',p_execution_id,'providerCode',v_execution.provider_code,'contentRevision',v_execution.content_revision)
    );
    v_response := jsonb_build_object(
      'httpStatus',200,'code','ok','campaignId',v_execution.campaign_id,'executionId',p_execution_id,
      'publishStatus','Cancelled','replayed',false
    );
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(
      p_actor_account_id,'marketing.campaign.publish.cancel','marketing_publish_execution',p_execution_id::text,'Denied',
      coalesce(v_response->>'message','Campaign cancellation denied'),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('code',v_response->>'code')
    );
  end if;
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now()
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.retry_marketing_campaign_publish(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=admin,marketing,integration,pg_temp
as $$
declare
  v_operation varchar := 'marketing.campaign.publish.retry:' || p_execution_id::text;
  v_existing admin.idempotency_keys%rowtype;
  v_execution marketing.campaign_publish_executions%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_new_execution_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.social.publish')
     or not admin.account_has_permission(p_actor_account_id,'marketing.campaign.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','Retry requires campaign write and high-risk social publish permissions.','replayed',false);
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

  select * into v_execution from marketing.campaign_publish_executions where id=p_execution_id for update;
  if not found then
    v_response := jsonb_build_object('httpStatus',404,'code','marketing_publish_execution_not_found','message','Publish execution was not found.','replayed',false);
  elsif v_execution.status='OutcomeUnknown' then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_publish_outcome_unknown','message','OutcomeUnknown is fail-closed and can never be automatically retried.','replayed',false);
  elsif v_execution.status<>'Failed' then
    v_response := jsonb_build_object('httpStatus',409,'code','marketing_publish_not_retryable','message','Only a confirmed Failed execution can be retried.','replayed',false);
  else
    select * into v_campaign from marketing.campaigns where id=v_execution.campaign_id for update;
    select * into v_content from marketing.campaign_content where campaign_id=v_execution.campaign_id for update;
    if v_campaign.status not in ('Ready','Active') then
      v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_not_publishable','message','Campaign lifecycle is not publishable.','replayed',false);
    elsif v_content.approval_state<>'Approved' or v_content.approved_revision is distinct from v_execution.content_revision or v_content.content_revision is distinct from v_execution.content_revision then
      v_response := jsonb_build_object('httpStatus',409,'code','marketing_campaign_approval_required','message','The failed revision is no longer the currently approved revision.','replayed',false);
    elsif not exists(select 1 from marketing.channel_connections c where c.provider_code=v_execution.provider_code and c.operator_status='Enabled')
       or not admin.marketing_channel_credential_available(v_execution.provider_code) then
      v_response := jsonb_build_object('httpStatus',409,'code','marketing_channel_setup_required','message','Campaign channel is not currently ready for a retry.','replayed',false);
    elsif exists(
      select 1 from marketing.campaign_publish_executions e
      where e.campaign_id=v_execution.campaign_id and e.provider_code=v_execution.provider_code
        and e.content_revision=v_execution.content_revision and e.id<>p_execution_id
        and e.status in ('Scheduled','Queued','Processing','Published','OutcomeUnknown')
    ) then
      v_response := jsonb_build_object('httpStatus',409,'code','marketing_publish_duplicate_guard','message','This content revision already has another protected publish execution.','replayed',false);
    else
      v_new_execution_id := gen_random_uuid();
      insert into marketing.campaign_publish_executions(
        id,campaign_id,provider_code,content_revision,status,requested_by_admin_account_id,
        request_id,correlation_id,retry_of_execution_id
      ) values(
        v_new_execution_id,v_execution.campaign_id,v_execution.provider_code,v_execution.content_revision,'Queued',p_actor_account_id,
        p_idempotency_key,p_correlation_id,p_execution_id
      );
      insert into marketing.campaign_publish_execution_events(execution_id,event_type)
        values(v_new_execution_id,'Queued');
      insert into integration.outbox_messages(
        aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
      ) values(
        'marketing_campaign',v_execution.campaign_id,'marketing.campaign_publish_requested',
        'marketing-publish:'||v_new_execution_id::text,
        jsonb_build_object('executionId',v_new_execution_id),'Pending',now()
      );
      insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
      values(
        p_actor_account_id,'marketing.campaign.publish.retry','marketing_campaign',v_execution.campaign_id::text,'Succeeded',trim(p_reason),
        p_correlation_id,p_idempotency_key,false,
        jsonb_build_object('executionId',v_new_execution_id,'retryOfExecutionId',p_execution_id,'providerCode',v_execution.provider_code,'contentRevision',v_execution.content_revision,'providerConnectivity','NotVerified')
      );
      v_response := jsonb_build_object(
        'httpStatus',202,'code','ok','campaignId',v_execution.campaign_id,'executionId',v_new_execution_id,
        'retryOfExecutionId',p_execution_id,'publishStatus','Queued','providerConnectivity','NotVerified','replayed',false
      );
    end if;
  end if;

  if (v_response->>'httpStatus')::integer >= 400 then
    insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
    values(
      p_actor_account_id,'marketing.campaign.publish.retry','marketing_publish_execution',p_execution_id::text,'Denied',
      coalesce(v_response->>'message','Campaign retry denied'),p_correlation_id,p_idempotency_key,false,
      jsonb_build_object('code',v_response->>'code')
    );
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
set search_path=marketing,admin,pg_temp
as $$
declare
  v_execution marketing.campaign_publish_executions%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_secret_name varchar;
  v_failure varchar;
begin
  select * into v_execution from marketing.campaign_publish_executions where id=p_execution_id for update;
  if not found then return; end if;

  if v_execution.status='Scheduled' then
    if v_execution.scheduled_for_utc is null or v_execution.scheduled_for_utc > now() then return; end if;
    update marketing.campaign_publish_executions set status='Queued' where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type) values(p_execution_id,'Queued');
  elsif v_execution.status<>'Queued' then
    return;
  end if;

  select * into v_campaign from marketing.campaigns where id=v_execution.campaign_id;
  select * into v_content from marketing.campaign_content where campaign_id=v_execution.campaign_id;
  select credential_secret_name into v_secret_name from marketing.channel_connections
   where provider_code=v_execution.provider_code and operator_status='Enabled';

  if v_campaign.status not in ('Ready','Active') then v_failure := 'campaign_not_publishable';
  elsif v_content.approval_state<>'Approved' or v_content.approved_revision is distinct from v_execution.content_revision or v_content.content_revision is distinct from v_execution.content_revision then v_failure := 'approval_changed';
  elsif v_secret_name is null or not admin.marketing_channel_credential_available(v_execution.provider_code) then v_failure := 'provider_not_configured';
  end if;

  if v_failure is not null then
    update marketing.campaign_publish_executions set status='Failed',completed_at_utc=now(),failure_code=v_failure where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type,code) values(p_execution_id,'Failed',v_failure);
    return;
  end if;

  update marketing.campaign_publish_executions set status='Processing',started_at_utc=now(),failure_code=null where id=p_execution_id;
  insert into marketing.campaign_publish_execution_events(execution_id,event_type) values(p_execution_id,'Processing');
  return query select v_execution.id,v_execution.campaign_id,v_execution.provider_code,v_content.publish_text,v_content.asset_refs,v_secret_name;
end
$$;

revoke all on function admin.schedule_marketing_campaign_publish(uuid,uuid,timestamp without time zone,varchar,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.cancel_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.retry_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) from public;
revoke all on function marketing.claim_campaign_publish_execution(uuid) from public;

grant execute on function admin.schedule_marketing_campaign_publish(uuid,uuid,timestamp without time zone,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.cancel_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function admin.retry_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function marketing.claim_campaign_publish_execution(uuid) to lifemate_worker_runtime;

comment on view admin.marketing_content_calendar_v1 is
  'Privacy-safe marketing publishing schedule/history projection. Provider secrets are intentionally absent.';
comment on function admin.schedule_marketing_campaign_publish(uuid,uuid,timestamp without time zone,varchar,varchar,uuid,varchar,varchar) is
  'Schedules only the currently human-approved campaign content revision. Dispatch reuses the existing outbox/worker publish boundary.';
comment on function admin.retry_marketing_campaign_publish(uuid,uuid,varchar,uuid,varchar,varchar) is
  'Manual retry is allowed only for confirmed Failed executions. OutcomeUnknown remains fail-closed.';

commit;
