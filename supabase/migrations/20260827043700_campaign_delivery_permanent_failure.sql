begin;

alter table messaging.delivery_jobs
  drop constraint if exists delivery_jobs_status_check;
alter table messaging.delivery_jobs
  add constraint delivery_jobs_status_check
  check (status in ('Pending','InFlight','Delivered','Failed','PermanentFailed','OutcomeUnknown','Suppressed','Cancelled'));

alter table messaging.delivery_events
  drop constraint if exists delivery_events_event_type_check;
alter table messaging.delivery_events
  add constraint delivery_events_event_type_check
  check (event_type in ('Queued','Attempted','Delivered','Failed','PermanentFailed','OutcomeUnknown','Suppressed','Opened','Clicked','Converted'));

create or replace function messaging.record_campaign_delivery_result_v2(
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
  if p_result not in ('Delivered','Failed','PermanentFailed','OutcomeUnknown')
     or p_provider is null or p_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$'
     or p_occurred_at_utc is null or p_occurred_at_utc>now()+interval '5 minutes' then
    raise exception 'delivery_result_invalid';
  end if;
  if p_result='Delivered' and (p_provider_reference_hash is null or p_provider_reference_hash !~ '^[0-9a-f]{64,128}$') then
    raise exception 'delivery_provider_evidence_required';
  end if;
  if p_result in ('Failed','PermanentFailed','OutcomeUnknown')
     and (p_reason_code is null or p_reason_code !~ '^[a-z0-9][a-z0-9_.-]{1,79}$') then
    raise exception 'delivery_failure_reason_required';
  end if;

  select * into v_job from messaging.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'delivery_job_not_found'; end if;
  if v_job.status in ('Delivered','PermanentFailed','OutcomeUnknown','Cancelled','Suppressed') then
    if v_job.status=p_result and (p_result<>'Delivered' or v_job.provider_reference_hash=lower(p_provider_reference_hash)) then
      return jsonb_build_object('status',v_job.status,'replayed',true);
    end if;
    raise exception 'delivery_terminal_conflict';
  end if;
  if v_job.status<>'InFlight' then raise exception 'delivery_job_not_in_flight'; end if;

  if p_result='Delivered' then
    update messaging.delivery_jobs
    set status='Delivered',provider=p_provider,provider_reference_hash=lower(p_provider_reference_hash),
        next_attempt_at_utc=null,updated_at_utc=now()
    where id=p_job_id;
  elsif p_result in ('PermanentFailed','OutcomeUnknown') then
    -- Both are terminal. OutcomeUnknown may already have caused an external side
    -- effect; PermanentFailed is a definitive provider rejection. Neither is
    -- automatically retried.
    update messaging.delivery_jobs
    set status=p_result,provider=p_provider,next_attempt_at_utc=null,updated_at_utc=now()
    where id=p_job_id;
  else
    v_next:=case when v_job.attempt_count>=5 then null
      else now()+make_interval(secs=>least(3600,30*(2^greatest(v_job.attempt_count-1,0))::integer)) end;
    update messaging.delivery_jobs
    set status='Failed',provider=p_provider,next_attempt_at_utc=v_next,updated_at_utc=now()
    where id=p_job_id;
  end if;

  insert into messaging.delivery_events(
    delivery_job_id,event_type,provider,provider_event_reference_hash,reason_code,occurred_at_utc
  ) values(
    p_job_id,p_result,p_provider,
    case when p_result='Delivered' then lower(p_provider_reference_hash) else null end,
    p_reason_code,p_occurred_at_utc
  );

  update messaging.campaign_executions e
  set status=case
    when exists(
      select 1 from messaging.delivery_jobs j
      where j.execution_id=e.id
        and (j.status in ('Pending','InFlight') or (j.status='Failed' and j.attempt_count<5))
    ) then e.status
    when exists(
      select 1 from messaging.delivery_jobs j
      where j.execution_id=e.id and j.status in ('Failed','PermanentFailed','OutcomeUnknown')
    ) then 'Failed'
    else 'Completed' end,
    updated_at_utc=now()
  where e.id=v_job.execution_id;

  return jsonb_build_object('status',p_result,'replayed',false,'nextAttemptAtUtc',v_next);
end $$;

revoke all on function messaging.record_campaign_delivery_result_v2(uuid,varchar,varchar,varchar,varchar,timestamptz) from public;
grant execute on function messaging.record_campaign_delivery_result_v2(uuid,varchar,varchar,varchar,varchar,timestamptz) to lifemate_worker_runtime;

commit;
