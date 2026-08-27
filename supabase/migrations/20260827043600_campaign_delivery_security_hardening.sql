begin;

alter table messaging.delivery_jobs
  add column if not exists planned_provider varchar(40),
  add column if not exists message_content_hash char(64),
  add column if not exists message_version bigint;

alter table messaging.delivery_jobs
  drop constraint if exists ck_delivery_jobs_planned_provider;
alter table messaging.delivery_jobs
  add constraint ck_delivery_jobs_planned_provider
  check (planned_provider is null or planned_provider ~ '^[a-z0-9][a-z0-9_.-]{1,39}$');
alter table messaging.delivery_jobs
  drop constraint if exists ck_delivery_jobs_message_content_hash;
alter table messaging.delivery_jobs
  add constraint ck_delivery_jobs_message_content_hash
  check (message_content_hash is null or message_content_hash ~ '^[0-9a-f]{64}$');
alter table messaging.delivery_jobs
  drop constraint if exists ck_delivery_jobs_message_version;
alter table messaging.delivery_jobs
  add constraint ck_delivery_jobs_message_version
  check (message_version is null or message_version>=1);

create or replace function messaging.prepare_campaign_execution_idempotent(
  p_actor_account_id uuid,
  p_campaign_id uuid,
  p_snapshot_id uuid,
  p_campaign_updated_at_utc timestamptz,
  p_channels varchar[],
  p_sms_provider varchar,
  p_sms_currency varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,marketing,admin,pg_temp
as $$
declare
  v_operation constant varchar:='marketing.campaign.prepare';
  v_existing admin.idempotency_keys%rowtype;
  v_result jsonb;
  v_execution_id uuid;
  v_product_code varchar(64);
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','message','Idempotency metadata is invalid.','replayed',false);
  end if;
  if 'SMS'=any(coalesce(p_channels,'{}'::varchar[]))
     and (p_sms_provider is null or p_sms_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$') then
    return jsonb_build_object('httpStatus',400,'code','campaign_sms_provider_required','message','A valid SMS provider is required for SMS execution.','replayed',false);
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
      return v_existing.response_json||jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still processing.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  v_result:=messaging.prepare_campaign_execution(
    p_actor_account_id,p_campaign_id,p_snapshot_id,p_campaign_updated_at_utc,
    p_channels,p_sms_provider,p_sms_currency,p_correlation_id
  );

  if coalesce((v_result->>'httpStatus')::integer,500)<400 then
    v_execution_id:=nullif(v_result->>'executionId','')::uuid;
    select product_code into v_product_code from marketing.campaigns where id=p_campaign_id;

    update messaging.delivery_jobs j
    set message_content_hash=m.content_hash,
        message_version=m.version,
        planned_provider=case
          when j.channel='SMS' then lower(p_sms_provider)
          else (
            select pr.provider
            from messaging.push_registrations pr
            where pr.account_id=j.account_id
              and pr.product_code=v_product_code
              and pr.status='Active'
            order by pr.last_seen_at_utc desc,pr.id
            limit 1
          )
        end,
        updated_at_utc=now()
    from messaging.campaign_messages m
    where j.execution_id=v_execution_id and m.id=j.message_id;

    if exists(
      select 1 from messaging.delivery_jobs
      where execution_id=v_execution_id and status='Pending'
        and (planned_provider is null or message_content_hash is null or message_version is null)
    ) then
      raise exception using errcode='55000',message='Campaign delivery binding is incomplete.';
    end if;
  end if;

  v_result:=v_result||jsonb_build_object('replayed',false);
  update admin.idempotency_keys
  set status='Completed',response_status=coalesce((v_result->>'httpStatus')::integer,500),
      response_json=v_result,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_result;
end $$;

revoke all on function messaging.prepare_campaign_execution(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid)
  from lifemate_admin_runtime;
revoke all on function messaging.prepare_campaign_execution_idempotent(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid,varchar,varchar)
  from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function messaging.prepare_campaign_execution_idempotent(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid,varchar,varchar)
  to lifemate_admin_runtime;

create or replace function messaging.resolve_campaign_delivery_job(p_job_id uuid)
returns table(
  job_id uuid,
  account_id uuid,
  channel varchar,
  provider varchar,
  product_code varchar,
  message_title varchar,
  message_body varchar,
  recipient_hash varchar,
  recipient_ciphertext_b64 text,
  recipient_nonce_b64 varchar,
  recipient_key_version smallint
)
language plpgsql
security definer
set search_path=pg_catalog,messaging,marketing,consent,identity,pg_temp
as $$
declare
  v_job messaging.delivery_jobs%rowtype;
  v_execution messaging.campaign_executions%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_message messaging.campaign_messages%rowtype;
  v_preference varchar(80);
  v_contact record;
  v_push messaging.push_registrations%rowtype;
begin
  select * into v_job from messaging.delivery_jobs where id=p_job_id for update;
  if not found or v_job.status<>'InFlight' then return; end if;
  select * into v_execution from messaging.campaign_executions where id=v_job.execution_id for share;
  if not found or v_execution.status<>'Sending' then
    update messaging.delivery_jobs set status='Cancelled',updated_at_utc=now() where id=v_job.id;
    return;
  end if;
  select * into v_campaign from marketing.campaigns where id=v_execution.campaign_id;
  select * into v_message from messaging.campaign_messages where id=v_job.message_id;

  if v_message.id is null or v_job.message_content_hash is null or v_job.message_version is null
     or v_message.content_hash<>v_job.message_content_hash or v_message.version<>v_job.message_version then
    update messaging.delivery_jobs
    set status='Failed',attempt_count=5,next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    insert into messaging.delivery_events(delivery_job_id,event_type,reason_code,occurred_at_utc)
    values(v_job.id,'Failed','message_snapshot_conflict',now());
    return;
  end if;

  v_preference:=case when v_job.channel='SMS' then 'promotional_sms' else 'promotional_push' end;
  if not consent.account_allows_optional_purpose(v_job.account_id,v_preference,'GLOBAL') then
    update messaging.delivery_jobs
    set status='Suppressed',suppression_reason='OptedOut',next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    insert into messaging.delivery_events(delivery_job_id,event_type,reason_code,occurred_at_utc)
    values(v_job.id,'Suppressed','late_opt_out',now());
    return;
  end if;

  if not exists(select 1 from identity.accounts where id=v_job.account_id and status='Active') then
    update messaging.delivery_jobs
    set status='Suppressed',suppression_reason='InactiveAccount',next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    insert into messaging.delivery_events(delivery_job_id,event_type,reason_code,occurred_at_utc)
    values(v_job.id,'Suppressed','inactive_account',now());
    return;
  end if;

  if v_job.channel='SMS' then
    select cp.normalized_value_hash,
           encode(cp.encrypted_value,'base64') as ciphertext_b64,
           cp.encryption_nonce_b64,cp.encryption_key_version
    into v_contact
    from identity.contact_points cp
    where cp.account_id=v_job.account_id and cp.kind='Phone' and cp.status='Verified'
      and cp.verified_at_utc is not null and cp.encrypted_value is not null
      and cp.encryption_nonce_b64 is not null and cp.encryption_key_version is not null
    order by cp.updated_at_utc desc,cp.id
    limit 1;
    if v_contact.normalized_value_hash is null then
      update messaging.delivery_jobs set status='Suppressed',suppression_reason='NoReachableAddress',next_attempt_at_utc=null,updated_at_utc=now() where id=v_job.id;
      insert into messaging.delivery_events(delivery_job_id,event_type,reason_code,occurred_at_utc)
      values(v_job.id,'Suppressed','phone_unavailable',now());
      return;
    end if;
    return query select
      v_job.id,v_job.account_id,v_job.channel,v_job.planned_provider,v_campaign.product_code,
      v_message.title,v_message.body,v_contact.normalized_value_hash::varchar,
      v_contact.ciphertext_b64::text,v_contact.encryption_nonce_b64::varchar,
      v_contact.encryption_key_version::smallint;
    return;
  end if;

  select * into v_push from messaging.push_registrations pr
  where pr.account_id=v_job.account_id and pr.product_code=v_campaign.product_code
    and pr.provider=v_job.planned_provider and pr.status='Active'
  order by pr.last_seen_at_utc desc,pr.id
  limit 1;
  if v_push.id is null then
    update messaging.delivery_jobs set status='Suppressed',suppression_reason='NoReachableAddress',next_attempt_at_utc=null,updated_at_utc=now() where id=v_job.id;
    insert into messaging.delivery_events(delivery_job_id,event_type,reason_code,occurred_at_utc)
    values(v_job.id,'Suppressed','push_token_unavailable',now());
    return;
  end if;
  return query select
    v_job.id,v_job.account_id,v_job.channel,v_push.provider,v_campaign.product_code,
    v_message.title,v_message.body,v_push.token_hash,
    encode(v_push.token_ciphertext,'base64')::text,v_push.token_nonce_b64,
    v_push.encryption_key_version;
end $$;

revoke all on function messaging.resolve_campaign_delivery_job(uuid)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_edge_runtime;
grant execute on function messaging.resolve_campaign_delivery_job(uuid) to lifemate_worker_runtime;

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
declare
  v_job messaging.delivery_jobs%rowtype;
  v_next timestamptz;
  v_terminal_failure boolean;
begin
  if p_result not in ('Delivered','Failed') or p_provider is null or p_provider !~ '^[a-z0-9][a-z0-9_.-]{1,39}$'
     or p_occurred_at_utc is null or p_occurred_at_utc>now()+interval '5 minutes' then
    raise exception 'delivery_result_invalid';
  end if;
  if p_result='Delivered' and (p_provider_reference_hash is null or p_provider_reference_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'delivery_provider_evidence_required';
  end if;
  if p_result='Failed' and (p_reason_code is null or p_reason_code !~ '^[a-z0-9][a-z0-9_.-]{1,79}$') then
    raise exception 'delivery_failure_reason_required';
  end if;
  select * into v_job from messaging.delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'delivery_job_not_found'; end if;
  if v_job.status in ('Delivered','Cancelled','Suppressed') then
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
  else
    v_terminal_failure:=p_reason_code in ('provider_permanent_failure','provider_outcome_unknown');
    v_next:=case when v_terminal_failure or v_job.attempt_count>=5 then null
                 else now()+make_interval(secs=>least(3600,30*(2^greatest(v_job.attempt_count-1,0))::integer)) end;
    update messaging.delivery_jobs
    set status='Failed',provider=p_provider,
        attempt_count=case when v_terminal_failure then 5 else attempt_count end,
        next_attempt_at_utc=v_next,updated_at_utc=now()
    where id=p_job_id;
  end if;
  insert into messaging.delivery_events(delivery_job_id,event_type,provider,provider_event_reference_hash,reason_code,occurred_at_utc)
  values(p_job_id,p_result,p_provider,case when p_result='Delivered' then lower(p_provider_reference_hash) else null end,p_reason_code,p_occurred_at_utc);

  update messaging.campaign_executions e
  set status=case
    when exists(
      select 1 from messaging.delivery_jobs j
      where j.execution_id=e.id
        and (j.status in ('Pending','InFlight') or (j.status='Failed' and j.attempt_count<5))
    ) then e.status
    when exists(select 1 from messaging.delivery_jobs j where j.execution_id=e.id and j.status='Failed') then 'Failed'
    else 'Completed' end,
    updated_at_utc=now()
  where e.id=v_job.execution_id;
  return jsonb_build_object('status',p_result,'replayed',false,'nextAttemptAtUtc',v_next);
end $$;

revoke all on function messaging.record_campaign_delivery_result(uuid,varchar,varchar,varchar,varchar,timestamptz)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_edge_runtime;
grant execute on function messaging.record_campaign_delivery_result(uuid,varchar,varchar,varchar,varchar,timestamptz)
  to lifemate_worker_runtime;

comment on function messaging.resolve_campaign_delivery_job(uuid)
is 'Worker-only late-binding boundary. Re-checks promotional opt-in, active account, message version/hash and current encrypted recipient reachability immediately before provider send.';
comment on function messaging.prepare_campaign_execution_idempotent(uuid,uuid,uuid,timestamptz,varchar[],varchar,varchar,uuid,varchar,varchar)
is 'Replay-safe campaign preparation wrapper. Binds immutable audience/campaign/message facts and planned providers before scheduling.';

commit;
