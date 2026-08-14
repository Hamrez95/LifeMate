-- Scale-06: bounded durable outbox behavior, priority scheduling, poison-message
-- handling, idempotent consumer receipts, queue observability and recovery.

alter table integration.outbox_messages
  add column if not exists priority smallint not null default 50,
  add column if not exists max_attempts smallint not null default 10,
  add column if not exists max_age_seconds integer not null default 86400,
  add column if not exists coalesce_key character varying(220),
  add column if not exists last_attempt_at_utc timestamp with time zone,
  add column if not exists last_error_at_utc timestamp with time zone,
  add column if not exists dead_lettered_at_utc timestamp with time zone;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='ck_outbox_priority') then
    alter table integration.outbox_messages
      add constraint ck_outbox_priority check(priority between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_outbox_max_attempts') then
    alter table integration.outbox_messages
      add constraint ck_outbox_max_attempts check(max_attempts between 1 and 25);
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_outbox_max_age') then
    alter table integration.outbox_messages
      add constraint ck_outbox_max_age check(max_age_seconds between 60 and 2592000);
  end if;
end
$$;

-- Policy defaults. Lower numeric priority is claimed first.
update integration.outbox_messages
set priority = case
      when event_type='identity.session_revoke_requested' then 5
      when event_type='identity.account_deletion_requested' then 10
      when event_type like 'notification.%' then 40
      when event_type='care.adherence_projection_refresh_requested' then 60
      when event_type like 'analytics.%' then 80
      when event_type like 'maintenance.%' then 90
      else 70 end,
    max_attempts = case
      when event_type in ('identity.session_revoke_requested','identity.account_deletion_requested') then 12
      when event_type='care.adherence_projection_refresh_requested' then 8
      else 6 end,
    max_age_seconds = case
      when event_type='identity.account_deletion_requested' then 604800
      when event_type='identity.session_revoke_requested' then 86400
      when event_type='care.adherence_projection_refresh_requested' then 21600
      when event_type like 'notification.%' then 86400
      when event_type like 'analytics.%' then 21600
      when event_type like 'maintenance.%' then 86400
      else 86400 end,
    coalesce_key = case
      when event_type='care.adherence_projection_refresh_requested'
        and aggregate_id is not null
        and nullif(payload_json->>'summaryDate','') is not null
      then 'adherence:'||aggregate_id::text||':'||(payload_json->>'summaryDate')
      else coalesce_key end;

create index if not exists ix_outbox_priority_claim
  on integration.outbox_messages(priority,available_at_utc,created_at_utc,id)
  where status in ('Pending','Failed');
create index if not exists ix_outbox_coalesce_active
  on integration.outbox_messages(coalesce_key,status,created_at_utc)
  where coalesce_key is not null and status in ('Pending','Failed','Processing');
create index if not exists ix_outbox_deadletter_created
  on integration.outbox_messages(dead_lettered_at_utc desc,id)
  where status='DeadLetter';

-- Best-effort projections are coalesced while pending. The existing pending row
-- is locked and refreshed so the API transaction never waits for optional work
-- and a stalled worker cannot create an unbounded stream of duplicate projection
-- messages. If a prior message is already Processing, one follow-up is allowed.
create or replace function integration.apply_outbox_delivery_policy()
returns trigger
language plpgsql
set search_path = integration, pg_temp
as $$
declare
  v_pending_id uuid;
begin
  new.priority := case
    when new.event_type='identity.session_revoke_requested' then 5
    when new.event_type='identity.account_deletion_requested' then 10
    when new.event_type like 'notification.%' then 40
    when new.event_type='care.adherence_projection_refresh_requested' then 60
    when new.event_type like 'analytics.%' then 80
    when new.event_type like 'maintenance.%' then 90
    else 70 end;
  new.max_attempts := case
    when new.event_type in ('identity.session_revoke_requested','identity.account_deletion_requested') then 12
    when new.event_type='care.adherence_projection_refresh_requested' then 8
    else 6 end;
  new.max_age_seconds := case
    when new.event_type='identity.account_deletion_requested' then 604800
    when new.event_type='identity.session_revoke_requested' then 86400
    when new.event_type='care.adherence_projection_refresh_requested' then 21600
    when new.event_type like 'analytics.%' then 21600
    else 86400 end;

  if new.event_type='care.adherence_projection_refresh_requested'
     and new.aggregate_id is not null
     and nullif(new.payload_json->>'summaryDate','') is not null then
    new.coalesce_key := 'adherence:'||new.aggregate_id::text||':'||(new.payload_json->>'summaryDate');
    perform pg_advisory_xact_lock(hashtextextended(new.coalesce_key,0));

    select id into v_pending_id
    from integration.outbox_messages
    where coalesce_key=new.coalesce_key
      and status in ('Pending','Failed')
    order by created_at_utc,id
    limit 1
    for update;

    if v_pending_id is not null then
      update integration.outbox_messages
      set payload_json=new.payload_json,
          priority=least(priority,new.priority),
          available_at_utc=least(available_at_utc,new.available_at_utc),
          last_error_code=null,
          last_error_at_utc=null
      where id=v_pending_id;
      return null;
    end if;
  end if;

  return new;
end
$$;

drop trigger if exists trg_apply_outbox_delivery_policy on integration.outbox_messages;
create trigger trg_apply_outbox_delivery_policy
before insert on integration.outbox_messages
for each row execute function integration.apply_outbox_delivery_policy();

create table if not exists integration.outbox_consumer_receipts(
  message_id uuid not null references integration.outbox_messages(id) on delete cascade,
  consumer_name character varying(120) not null,
  event_type character varying(160) not null,
  completed_at_utc timestamp with time zone not null default now(),
  primary key(message_id,consumer_name)
);

alter table integration.outbox_consumer_receipts enable row level security;
alter table integration.outbox_consumer_receipts force row level security;
drop policy if exists lifemate_worker_runtime_access on integration.outbox_consumer_receipts;
create policy lifemate_worker_runtime_access
  on integration.outbox_consumer_receipts for all to lifemate_worker_runtime
  using(true) with check(true);

grant select,insert on integration.outbox_consumer_receipts to lifemate_worker_runtime;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on integration.outbox_consumer_receipts from %I',v_role);
    end if;
  end loop;
end
$$;

-- PostgreSQL cannot CREATE OR REPLACE a function when its OUT/RETURNS TABLE
-- row shape changes. Drop the previous signature inside this migration and
-- recreate it immediately below; worker EXECUTE grants are restored later.
drop function if exists integration.claim_outbox_messages_for_events(
  character varying, integer, character varying[]
);

create or replace function integration.claim_outbox_messages_for_events(
    p_worker_id character varying,
    p_batch_size integer,
    p_event_types character varying[]
) returns table(
    id uuid,
    aggregate_type character varying,
    aggregate_id uuid,
    event_type character varying,
    payload_json jsonb,
    attempt_count integer,
    priority smallint,
    max_attempts smallint,
    max_age_seconds integer,
    created_at_utc timestamp with time zone
)
language plpgsql
set search_path = integration, pg_temp
as $$
begin
  if nullif(trim(p_worker_id),'') is null then raise exception 'worker_id_required'; end if;
  if p_batch_size < 1 or p_batch_size > 50 then raise exception 'invalid_batch_size'; end if;
  if p_event_types is null or cardinality(p_event_types)=0 then raise exception 'event_types_required'; end if;

  -- Recover abandoned claims without waiting for a manual intervention.
  update integration.outbox_messages m
  set status='Failed',locked_at_utc=null,locked_by=null,
      available_at_utc=now(),last_error_code='stale_worker_lock',last_error_at_utc=now()
  where m.status='Processing'
    and m.event_type=any(p_event_types)
    and m.locked_at_utc < now()-interval '10 minutes'
    and m.created_at_utc + make_interval(secs=>m.max_age_seconds) > now();

  -- Old work is poison for the live queue. Preserve it as DeadLetter evidence
  -- rather than repeatedly retrying work whose business value has expired.
  update integration.outbox_messages m
  set status='DeadLetter',locked_at_utc=null,locked_by=null,
      last_error_code='message_expired',last_error_at_utc=now(),
      dead_lettered_at_utc=coalesce(dead_lettered_at_utc,now())
  where m.status in ('Pending','Failed','Processing')
    and m.event_type=any(p_event_types)
    and m.created_at_utc + make_interval(secs=>m.max_age_seconds) <= now()
    and (m.status <> 'Processing' or m.locked_at_utc < now()-interval '10 minutes');

  return query
  with candidates as (
    select m.id
    from integration.outbox_messages m
    where m.status in ('Pending','Failed')
      and m.event_type=any(p_event_types)
      and m.available_at_utc<=now()
      and m.created_at_utc + make_interval(secs=>m.max_age_seconds)>now()
    order by m.priority,m.available_at_utc,m.created_at_utc,m.id
    for update skip locked
    limit p_batch_size
  )
  update integration.outbox_messages m
  set status='Processing',locked_at_utc=now(),locked_by=p_worker_id,
      attempt_count=m.attempt_count+1,last_attempt_at_utc=now()
  from candidates c
  where m.id=c.id
  returning m.id,m.aggregate_type,m.aggregate_id,m.event_type,m.payload_json,
            m.attempt_count,m.priority,m.max_attempts,m.max_age_seconds,m.created_at_utc;
end
$$;

create or replace function integration.fail_outbox_message_safely(
    p_message_id uuid,
    p_worker_id character varying,
    p_error_code character varying,
    p_retry_seconds integer,
    p_permanent boolean default false
) returns boolean
language plpgsql
set search_path = integration, pg_temp
as $$
declare
  v_attempts integer;
  v_max_attempts integer;
  v_created_at timestamp with time zone;
  v_max_age integer;
  v_dead boolean;
begin
  if p_retry_seconds < 1 or p_retry_seconds > 86400 then
    raise exception 'invalid_retry_seconds';
  end if;

  select attempt_count,max_attempts,created_at_utc,max_age_seconds
  into v_attempts,v_max_attempts,v_created_at,v_max_age
  from integration.outbox_messages
  where id=p_message_id and status='Processing' and locked_by=p_worker_id
  for update;
  if not found then return false; end if;

  v_dead := p_permanent
    or v_attempts>=v_max_attempts
    or v_created_at + make_interval(secs=>v_max_age)<=now();

  update integration.outbox_messages
  set status=case when v_dead then 'DeadLetter' else 'Failed' end,
      available_at_utc=case when v_dead then available_at_utc else now()+make_interval(secs=>p_retry_seconds) end,
      locked_at_utc=null,locked_by=null,
      last_error_code=left(coalesce(nullif(trim(p_error_code),''),'worker_error'),80),
      last_error_at_utc=now(),
      dead_lettered_at_utc=case when v_dead then coalesce(dead_lettered_at_utc,now()) else null end
  where id=p_message_id;
  return true;
end
$$;

create or replace function integration.outbox_consumer_receipt_exists(
  p_message_id uuid,p_consumer_name character varying
) returns boolean
language sql stable
set search_path=integration,pg_temp
as $$
  select exists(
    select 1 from integration.outbox_consumer_receipts
    where message_id=p_message_id and consumer_name=p_consumer_name
  )
$$;

create or replace function integration.record_outbox_consumer_receipt(
  p_message_id uuid,p_consumer_name character varying,p_event_type character varying
) returns boolean
language plpgsql
set search_path=integration,pg_temp
as $$
begin
  if nullif(trim(p_consumer_name),'') is null then raise exception 'consumer_name_required'; end if;
  insert into integration.outbox_consumer_receipts(message_id,consumer_name,event_type)
  values(p_message_id,left(p_consumer_name,120),left(p_event_type,160))
  on conflict(message_id,consumer_name) do nothing;
  return true;
end
$$;

create or replace function integration.outbox_queue_metrics(
  p_event_types character varying[]
) returns table(
  ready_count bigint,
  processing_count bigint,
  dead_letter_count bigint,
  oldest_ready_age_seconds bigint,
  highest_attempt_count integer
)
language sql stable
set search_path=integration,pg_temp
as $$
  select
    count(*) filter(where status in ('Pending','Failed') and available_at_utc<=now())::bigint,
    count(*) filter(where status='Processing')::bigint,
    count(*) filter(where status='DeadLetter')::bigint,
    coalesce(extract(epoch from (now()-min(created_at_utc) filter(where status in ('Pending','Failed') and available_at_utc<=now())))::bigint,0),
    coalesce(max(attempt_count) filter(where status<>'Processed'),0)::integer
  from integration.outbox_messages
  where p_event_types is null or event_type=any(p_event_types)
$$;

create or replace function integration.prune_outbox_history(
  p_processed_retention_days integer default 7,
  p_dead_letter_retention_days integer default 30,
  p_batch_size integer default 500
) returns integer
language plpgsql
set search_path=integration,pg_temp
as $$
declare v_deleted integer;
begin
  if p_processed_retention_days<1 or p_processed_retention_days>90 then raise exception 'invalid_processed_retention'; end if;
  if p_dead_letter_retention_days<7 or p_dead_letter_retention_days>180 then raise exception 'invalid_deadletter_retention'; end if;
  if p_batch_size<1 or p_batch_size>2000 then raise exception 'invalid_prune_batch'; end if;
  with doomed as (
    select id from integration.outbox_messages
    where (status='Processed' and processed_at_utc<now()-make_interval(days=>p_processed_retention_days))
       or (status='DeadLetter' and dead_lettered_at_utc<now()-make_interval(days=>p_dead_letter_retention_days))
    order by coalesce(processed_at_utc,dead_lettered_at_utc),id
    limit p_batch_size
  )
  delete from integration.outbox_messages m using doomed d where m.id=d.id;
  get diagnostics v_deleted=row_count;
  return v_deleted;
end
$$;

-- Manual operator recovery. Intentionally not granted to the worker role.
create or replace function integration.requeue_dead_letter_outbox_message(
  p_message_id uuid,p_reason character varying
) returns boolean
language plpgsql
set search_path=integration,pg_temp
as $$
begin
  if nullif(trim(p_reason),'') is null or length(p_reason)>80 then raise exception 'requeue_reason_required'; end if;
  update integration.outbox_messages
  set status='Failed',attempt_count=0,available_at_utc=now(),locked_at_utc=null,locked_by=null,
      last_error_code='manual_requeue:'||left(regexp_replace(trim(p_reason),'[^a-zA-Z0-9_-]+','_','g'),60),
      last_error_at_utc=now(),dead_lettered_at_utc=null,
      created_at_utc=now()
  where id=p_message_id and status='DeadLetter';
  return found;
end
$$;

-- Account-deletion finalization is replay-safe if a worker completed the domain
-- transaction but lost the acknowledgement before completing the outbox row.
create or replace function identity.finalize_account_deletion(p_request_id uuid)
returns boolean
language plpgsql
set search_path = identity, core, ecosystem, security, consent, commerce, lifemate, pg_temp
as $$
declare
  v_account_id uuid;
  v_status character varying;
  v_self_person_id uuid;
begin
  select account_id,status into v_account_id,v_status
  from identity.account_deletion_requests
  where id=p_request_id
  for update;
  if not found then return false; end if;
  if v_status='Completed' then return true; end if;
  if v_status not in ('Requested','Processing') then return false; end if;

  update identity.account_deletion_requests
  set status='Processing',processing_started_at_utc=coalesce(processing_started_at_utc,now())
  where id=p_request_id;

  select person_id into v_self_person_id from core.account_person_links
  where account_id=v_account_id and link_type='Self'
  order by created_at_utc limit 1;

  delete from identity.contact_points where account_id=v_account_id;
  delete from identity.external_identities where account_id=v_account_id;
  update core.account_person_links set status='Revoked',revoked_at_utc=coalesce(revoked_at_utc,now())
    where account_id=v_account_id and status='Active';
  if v_self_person_id is not null then
    update core.person_profiles set display_name='Deleted LifeMate User',avatar_key=null,
      profile_photo_path=null,updated_at_utc=now() where person_id=v_self_person_id;
    update core.persons set status='Deleted',updated_at_utc=now() where id=v_self_person_id;
  end if;
  update lifemate.user_profiles set display_name='Deleted LifeMate User',phone_number=null,
    email=null,profile_photo_path=null,updated_at_utc=now() where user_id=v_account_id;
  update ecosystem.app_enrollments set status='Left' where account_id=v_account_id and status<>'Left';
  update identity.accounts set status='Deleted',updated_at_utc=now() where id=v_account_id;
  update identity.account_deletion_requests set status='Completed',completed_at_utc=coalesce(completed_at_utc,now())
    where id=p_request_id;
  return true;
end
$$;

revoke execute on function integration.apply_outbox_delivery_policy() from public;
revoke execute on function integration.claim_outbox_messages_for_events(character varying,integer,character varying[]) from public;
revoke execute on function integration.fail_outbox_message_safely(uuid,character varying,character varying,integer,boolean) from public;
revoke execute on function integration.outbox_consumer_receipt_exists(uuid,character varying) from public;
revoke execute on function integration.record_outbox_consumer_receipt(uuid,character varying,character varying) from public;
revoke execute on function integration.outbox_queue_metrics(character varying[]) from public;
revoke execute on function integration.prune_outbox_history(integer,integer,integer) from public;
revoke execute on function integration.requeue_dead_letter_outbox_message(uuid,character varying) from public;
revoke execute on function identity.finalize_account_deletion(uuid) from public;

grant execute on function integration.claim_outbox_messages_for_events(character varying,integer,character varying[]) to lifemate_worker_runtime;
grant execute on function integration.fail_outbox_message_safely(uuid,character varying,character varying,integer,boolean) to lifemate_worker_runtime;
grant execute on function integration.outbox_consumer_receipt_exists(uuid,character varying) to lifemate_worker_runtime;
grant execute on function integration.record_outbox_consumer_receipt(uuid,character varying,character varying) to lifemate_worker_runtime;
grant execute on function integration.outbox_queue_metrics(character varying[]) to lifemate_worker_runtime;
grant execute on function integration.prune_outbox_history(integer,integer,integer) to lifemate_worker_runtime;
grant execute on function identity.finalize_account_deletion(uuid) to lifemate_worker_runtime;
