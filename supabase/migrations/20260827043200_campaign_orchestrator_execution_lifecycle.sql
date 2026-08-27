begin;

create or replace function messaging.confirm_campaign_execution(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_expected_version bigint,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,admin,pg_temp
as $$
declare v_row messaging.campaign_executions%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  select * into v_row from messaging.campaign_executions where id=p_execution_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','campaign_execution_not_found','message','Campaign execution was not found.'); end if;
  if p_expected_version is null or p_expected_version<>v_row.version then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_version_conflict','message','Campaign execution changed.');
  end if;
  if not v_row.requires_second_confirmation or v_row.status<>'ApprovalPending' then
    return jsonb_build_object('httpStatus',409,'code','campaign_confirmation_not_required','message','This execution is not awaiting confirmation.');
  end if;
  if v_row.created_by_account_id=p_actor_account_id then
    return jsonb_build_object('httpStatus',409,'code','campaign_self_confirmation_denied','message','A second actor must confirm this execution.');
  end if;
  update messaging.campaign_executions
  set status='Prepared',confirmed_by_account_id=p_actor_account_id,confirmed_at_utc=now(),version=version+1,updated_at_utc=now()
  where id=p_execution_id returning * into v_row;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'marketing.campaign.confirm','campaign_execution',p_execution_id::text,'Succeeded',p_correlation_id,true,
    jsonb_build_object('version',v_row.version,'creatorAccountIdHash',encode(digest(v_row.created_by_account_id::text,'sha256'),'hex')));
  return jsonb_build_object('httpStatus',200,'code','ok','executionId',v_row.id,'status',v_row.status,'version',v_row.version);
end $$;

create or replace function messaging.schedule_campaign_execution(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_expected_version bigint,
  p_scheduled_at_utc timestamptz,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,admin,pg_temp
as $$
declare v_row messaging.campaign_executions%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  if p_scheduled_at_utc is null or p_scheduled_at_utc<now()-interval '1 minute' or p_scheduled_at_utc>now()+interval '30 days' then
    return jsonb_build_object('httpStatus',400,'code','campaign_schedule_invalid','message','Schedule time is outside the allowed window.');
  end if;
  select * into v_row from messaging.campaign_executions where id=p_execution_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','campaign_execution_not_found','message','Campaign execution was not found.'); end if;
  if p_expected_version is null or p_expected_version<>v_row.version then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_version_conflict','message','Campaign execution changed.');
  end if;
  if v_row.status<>'Prepared' then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_not_prepared','message','Campaign execution is not prepared for scheduling.');
  end if;
  if v_row.requires_second_confirmation and v_row.confirmed_at_utc is null then
    return jsonb_build_object('httpStatus',409,'code','campaign_confirmation_required','message','Second confirmation is required before scheduling.');
  end if;
  update messaging.campaign_executions
  set status='Scheduled',scheduled_at_utc=p_scheduled_at_utc,version=version+1,updated_at_utc=now()
  where id=p_execution_id returning * into v_row;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'marketing.campaign.schedule','campaign_execution',p_execution_id::text,'Succeeded',p_correlation_id,false,
    jsonb_build_object('scheduledAtUtc',p_scheduled_at_utc,'version',v_row.version));
  return jsonb_build_object('httpStatus',200,'code','ok','executionId',v_row.id,'status',v_row.status,'scheduledAtUtc',v_row.scheduled_at_utc,'version',v_row.version);
end $$;

create or replace function messaging.cancel_campaign_execution(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,admin,pg_temp
as $$
declare v_row messaging.campaign_executions%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000 then
    return jsonb_build_object('httpStatus',400,'code','campaign_cancel_reason_invalid','message','A cancellation reason is required.');
  end if;
  select * into v_row from messaging.campaign_executions where id=p_execution_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','campaign_execution_not_found','message','Campaign execution was not found.'); end if;
  if p_expected_version is null or p_expected_version<>v_row.version then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_version_conflict','message','Campaign execution changed.');
  end if;
  if v_row.status not in ('Prepared','ApprovalPending','Scheduled') then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_not_cancellable','message','Campaign execution can no longer be cancelled safely.');
  end if;
  update messaging.campaign_executions set status='Cancelled',version=version+1,updated_at_utc=now()
  where id=p_execution_id returning * into v_row;
  update messaging.delivery_jobs set status='Cancelled',updated_at_utc=now()
  where execution_id=p_execution_id and status='Pending';
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'marketing.campaign.cancel','campaign_execution',p_execution_id::text,'Succeeded',trim(p_reason),p_correlation_id,false,
    jsonb_build_object('version',v_row.version));
  return jsonb_build_object('httpStatus',200,'code','ok','executionId',v_row.id,'status','Cancelled','version',v_row.version);
end $$;

create or replace function messaging.claim_campaign_delivery_jobs(p_limit integer default 50)
returns table(job_id uuid,execution_id uuid,account_id uuid,channel varchar,message_id uuid,attempt_count integer)
language plpgsql
security definer
set search_path=pg_catalog,messaging,pg_temp
as $$
begin
  if p_limit is null or p_limit<1 or p_limit>200 then raise exception 'delivery_claim_limit_invalid'; end if;
  update messaging.campaign_executions e set status='Sending',updated_at_utc=now()
  where e.status='Scheduled' and e.scheduled_at_utc<=now()
    and exists(select 1 from messaging.delivery_jobs j where j.execution_id=e.id and j.status in ('Pending','Failed') and j.attempt_count<5);
  return query
  with candidates as (
    select j.id from messaging.delivery_jobs j
    join messaging.campaign_executions e on e.id=j.execution_id
    where e.status='Sending'
      and j.status in ('Pending','Failed') and j.attempt_count<5
      and (j.next_attempt_at_utc is null or j.next_attempt_at_utc<=now())
    order by coalesce(j.next_attempt_at_utc,j.created_at_utc),j.id
    for update of j skip locked
    limit p_limit
  ), claimed as (
    update messaging.delivery_jobs j set status='InFlight',attempt_count=j.attempt_count+1,updated_at_utc=now()
    from candidates c where j.id=c.id
    returning j.*
  )
  select c.id,c.execution_id,c.account_id,c.channel,c.message_id,c.attempt_count from claimed c;
end $$;

create or replace function messaging.record_campaign_delivery_result(
  p_job_id uuid,
  p_result varchar,
  p_provider varchar,
  p_provider_reference_hash varchar,
  p_reason_code varchar,
  p_occurred_at_utc timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,pg_temp
as $$
declare v_job messaging.delivery_jobs%rowtype; v_next timestamptz;
begin
  if p_result not in ('Delivered','Failed') or p_provider is null or p_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$'
     or p_occurred_at_utc is null or p_occurred_at_utc>now()+interval '5 minutes' then
    raise exception 'delivery_result_invalid';
  end if;
  if p_result='Delivered' and (p_provider_reference_hash is null or p_provider_reference_hash !~ '^[0-9a-f]{64,128}$') then
    raise exception 'delivery_provider_evidence_required';
  end if;
  if p_result='Failed' and (p_reason_code is null or p_reason_code !~ '^[a-z0-9][a-z0-9_.-]{1,79}$') then
    raise exception 'delivery_failure_reason_required';
  end if;
  select * into v_job from messaging.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'delivery_job_not_found'; end if;
  if v_job.status in ('Delivered','Cancelled','Suppressed') then
    if v_job.status=p_result and (p_result<>'Delivered' or v_job.provider_reference_hash=p_provider_reference_hash) then
      return jsonb_build_object('status',v_job.status,'replayed',true);
    end if;
    raise exception 'delivery_terminal_conflict';
  end if;
  if v_job.status<>'InFlight' then raise exception 'delivery_job_not_in_flight'; end if;

  if p_result='Delivered' then
    update messaging.delivery_jobs set status='Delivered',provider=p_provider,provider_reference_hash=lower(p_provider_reference_hash),next_attempt_at_utc=null,updated_at_utc=now()
    where id=p_job_id;
  else
    v_next:=case when v_job.attempt_count>=5 then null else now()+make_interval(secs=>least(3600,30*(2^greatest(v_job.attempt_count-1,0))::integer)) end;
    update messaging.delivery_jobs set status='Failed',provider=p_provider,next_attempt_at_utc=v_next,updated_at_utc=now()
    where id=p_job_id;
  end if;
  insert into messaging.delivery_events(delivery_job_id,event_type,provider,provider_event_reference_hash,reason_code,occurred_at_utc)
  values(p_job_id,p_result,p_provider,case when p_result='Delivered' then lower(p_provider_reference_hash) else null end,p_reason_code,p_occurred_at_utc);

  update messaging.campaign_executions e
  set status=case
    when exists(select 1 from messaging.delivery_jobs j where j.execution_id=e.id and j.status in ('Pending','InFlight') or (j.execution_id=e.id and j.status='Failed' and j.attempt_count<5)) then e.status
    when exists(select 1 from messaging.delivery_jobs j where j.execution_id=e.id and j.status='Failed') then 'Failed'
    else 'Completed' end,
    updated_at_utc=now()
  where e.id=v_job.execution_id;
  return jsonb_build_object('status',p_result,'replayed',false,'nextAttemptAtUtc',v_next);
end $$;

revoke all on function messaging.confirm_campaign_execution(uuid,uuid,bigint,uuid) from public;
revoke all on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid) from public;
revoke all on function messaging.cancel_campaign_execution(uuid,uuid,bigint,varchar,uuid) from public;
revoke all on function messaging.claim_campaign_delivery_jobs(integer) from public;
revoke all on function messaging.record_campaign_delivery_result(uuid,varchar,varchar,varchar,varchar,timestamptz) from public;
grant execute on function messaging.confirm_campaign_execution(uuid,uuid,bigint,uuid) to lifemate_admin_runtime;
grant execute on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid) to lifemate_admin_runtime;
grant execute on function messaging.cancel_campaign_execution(uuid,uuid,bigint,varchar,uuid) to lifemate_admin_runtime;
grant execute on function messaging.claim_campaign_delivery_jobs(integer) to lifemate_worker_runtime;
grant execute on function messaging.record_campaign_delivery_result(uuid,varchar,varchar,varchar,varchar,timestamptz) to lifemate_worker_runtime;

commit;
