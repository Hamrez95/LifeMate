begin;

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
  if not found then
    return jsonb_build_object('httpStatus',404,'code','campaign_execution_not_found','message','Campaign execution was not found.');
  end if;
  if p_expected_version is null or p_expected_version<>v_row.version then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_version_conflict','message','Campaign execution changed.');
  end if;
  if v_row.status<>'Prepared' then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_not_prepared','message','Campaign execution is not prepared for scheduling.');
  end if;
  if v_row.requires_second_confirmation and v_row.confirmed_at_utc is null then
    return jsonb_build_object('httpStatus',409,'code','campaign_confirmation_required','message','Second confirmation is required before scheduling.');
  end if;
  if not exists(
    select 1 from messaging.delivery_jobs j
    where j.execution_id=p_execution_id and j.status='Pending'
  ) then
    return jsonb_build_object('httpStatus',409,'code','campaign_no_eligible_recipients','message','No eligible recipients remain for this campaign.');
  end if;

  update messaging.campaign_executions
  set status='Scheduled',scheduled_at_utc=p_scheduled_at_utc,version=version+1,updated_at_utc=now()
  where id=p_execution_id returning * into v_row;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'marketing.campaign.schedule','campaign_execution',p_execution_id::text,
    'Succeeded',p_correlation_id,false,
    jsonb_build_object('scheduledAtUtc',p_scheduled_at_utc,'version',v_row.version)
  );

  return jsonb_build_object(
    'httpStatus',200,'code','ok','executionId',v_row.id,'status',v_row.status,
    'scheduledAtUtc',v_row.scheduled_at_utc,'version',v_row.version
  );
end $$;

revoke all on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid)
  from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid)
  to lifemate_admin_runtime;

comment on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid)
is 'Schedules only a prepared, version-matched execution that still has at least one sendable delivery job.';

commit;
