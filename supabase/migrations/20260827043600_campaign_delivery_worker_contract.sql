begin;

alter table messaging.campaign_executions
  add column if not exists sms_provider varchar(40);

alter table messaging.campaign_executions
  drop constraint if exists campaign_executions_sms_provider_check;
alter table messaging.campaign_executions
  add constraint campaign_executions_sms_provider_check
  check (sms_provider is null or sms_provider ~ '^[a-z0-9][a-z0-9_.-]{1,39}$');

alter table messaging.delivery_jobs
  drop constraint if exists delivery_jobs_status_check;
alter table messaging.delivery_jobs
  add constraint delivery_jobs_status_check
  check (status in ('Pending','InFlight','Delivered','Failed','OutcomeUnknown','Suppressed','Cancelled'));

alter table messaging.delivery_events
  drop constraint if exists delivery_events_event_type_check;
alter table messaging.delivery_events
  add constraint delivery_events_event_type_check
  check (event_type in ('Queued','Attempted','Delivered','Failed','OutcomeUnknown','Suppressed','Opened','Clicked','Converted'));

-- V2 composes the already-reviewed preparation function in the same database
-- transaction, then persists the provider selection required by the worker.
-- Any failure in this wrapper rolls back the nested preparation as well.
create or replace function messaging.prepare_campaign_execution_v2(
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
set search_path=pg_catalog,messaging,pg_temp
as $$
declare
  v_result jsonb;
  v_execution_id uuid;
begin
  if 'SMS'=any(coalesce(p_channels,array[]::varchar[])) then
    if p_sms_provider is null or p_sms_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$' then
      return jsonb_build_object(
        'httpStatus',400,
        'code','campaign_sms_provider_required',
        'message','An approved SMS provider is required for SMS delivery.'
      );
    end if;
  elsif p_sms_provider is not null then
    return jsonb_build_object(
      'httpStatus',400,
      'code','campaign_sms_provider_unexpected',
      'message','SMS provider must only be supplied for an SMS execution.'
    );
  end if;

  v_result:=messaging.prepare_campaign_execution(
    p_actor_account_id,
    p_campaign_id,
    p_snapshot_id,
    p_campaign_updated_at_utc,
    p_channels,
    p_sms_provider,
    p_sms_currency,
    p_correlation_id
  );

  if coalesce((v_result->>'httpStatus')::integer,500)<>201 then
    return v_result;
  end if;

  v_execution_id:=(v_result->>'executionId')::uuid;
  update messaging.campaign_executions
  set sms_provider=case when 'SMS'=any(p_channels) then lower(p_sms_provider) else null end,
      updated_at_utc=now()
  where id=v_execution_id;

  if not found then raise exception 'campaign_execution_provider_bind_failed'; end if;
  return v_result || jsonb_build_object('smsProvider',case when 'SMS'=any(p_channels) then lower(p_sms_provider) else null end);
end $$;

-- Worker-only projection. It exposes encrypted endpoint envelopes and bounded
-- message content, never plaintext phone numbers or push tokens.
create or replace function messaging.resolve_campaign_delivery_job(p_job_id uuid)
returns table(
  job_id uuid,
  account_id uuid,
  channel varchar,
  provider varchar,
  product_code varchar,
  message_title varchar,
  message_body varchar,
  endpoint_hash varchar,
  endpoint_ciphertext_b64 text,
  endpoint_nonce_b64 varchar,
  endpoint_key_version smallint
)
language plpgsql
security definer
set search_path=pg_catalog,messaging,marketing,identity,pg_temp
as $$
declare
  v_job messaging.delivery_jobs%rowtype;
  v_execution messaging.campaign_executions%rowtype;
  v_product varchar(64);
  v_title varchar(160);
  v_body varchar(2000);
begin
  select * into v_job
  from messaging.delivery_jobs
  where id=p_job_id
  for share;
  if not found or v_job.status<>'InFlight' then return; end if;

  select * into v_execution
  from messaging.campaign_executions
  where id=v_job.execution_id;
  if not found or v_execution.status<>'Sending' then return; end if;

  select c.product_code into v_product
  from marketing.campaigns c where c.id=v_execution.campaign_id;
  select m.title,m.body into v_title,v_body
  from messaging.campaign_messages m
  where m.id=v_job.message_id and m.status='Active';
  if v_product is null or v_body is null then return; end if;

  if v_job.channel='SMS' then
    return query
    select
      v_job.id,
      v_job.account_id,
      v_job.channel,
      v_execution.sms_provider,
      v_product,
      v_title,
      v_body,
      cp.normalized_value_hash,
      encode(cp.encrypted_value,'base64'),
      cp.encryption_nonce_b64,
      cp.encryption_key_version
    from identity.contact_points cp
    where cp.account_id=v_job.account_id
      and cp.kind='Phone'
      and cp.status='Verified'
      and cp.verified_at_utc is not null
      and cp.encrypted_value is not null
      and cp.encryption_nonce_b64 is not null
      and cp.encryption_key_version is not null
    order by cp.updated_at_utc desc,cp.id desc
    limit 1;
    return;
  end if;

  if v_job.channel='Push' then
    return query
    select
      v_job.id,
      v_job.account_id,
      v_job.channel,
      pr.provider,
      v_product,
      v_title,
      v_body,
      pr.token_hash,
      encode(pr.token_ciphertext,'base64'),
      pr.token_nonce_b64,
      pr.encryption_key_version
    from messaging.push_registrations pr
    where pr.account_id=v_job.account_id
      and pr.product_code=v_product
      and pr.status='Active'
    order by pr.last_seen_at_utc desc,pr.id desc
    limit 1;
  end if;
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
  if p_result not in ('Delivered','Failed','OutcomeUnknown')
     or p_provider is null or p_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$'
     or p_occurred_at_utc is null or p_occurred_at_utc>now()+interval '5 minutes' then
    raise exception 'delivery_result_invalid';
  end if;
  if p_result='Delivered' and (p_provider_reference_hash is null or p_provider_reference_hash !~ '^[0-9a-f]{64,128}$') then
    raise exception 'delivery_provider_evidence_required';
  end if;
  if p_result in ('Failed','OutcomeUnknown') and (p_reason_code is null or p_reason_code !~ '^[a-z0-9][a-z0-9_.-]{1,79}$') then
    raise exception 'delivery_failure_reason_required';
  end if;

  select * into v_job from messaging.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'delivery_job_not_found'; end if;
  if v_job.status in ('Delivered','OutcomeUnknown','Cancelled','Suppressed') then
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
  elsif p_result='OutcomeUnknown' then
    -- External side effect may already exist. Never retry automatically.
    update messaging.delivery_jobs
    set status='OutcomeUnknown',provider=p_provider,next_attempt_at_utc=null,updated_at_utc=now()
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
      where j.execution_id=e.id and j.status in ('Failed','OutcomeUnknown')
    ) then 'Failed'
    else 'Completed' end,
    updated_at_utc=now()
  where e.id=v_job.execution_id;

  return jsonb_build_object('status',p_result,'replayed',false,'nextAttemptAtUtc',v_next);
end $$;

revoke all on function messaging.prepare_campaign_execution_v2(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid) from public;
revoke all on function messaging.resolve_campaign_delivery_job(uuid) from public;
revoke all on function messaging.record_campaign_delivery_result(uuid,varchar,varchar,varchar,varchar,timestamptz) from public;
grant execute on function messaging.prepare_campaign_execution_v2(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid) to lifemate_admin_runtime;
grant execute on function messaging.resolve_campaign_delivery_job(uuid) to lifemate_worker_runtime;
grant execute on function messaging.record_campaign_delivery_result(uuid,varchar,varchar,varchar,varchar,timestamptz) to lifemate_worker_runtime;

commit;
