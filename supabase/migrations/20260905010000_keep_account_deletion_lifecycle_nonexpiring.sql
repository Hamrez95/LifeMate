-- Account deletion is a privacy-critical lifecycle operation. It must not become
-- permanently stranded merely because the worker/scheduler was unavailable
-- longer than a generic outbox TTL. Attempts remain bounded by max_attempts;
-- only age-based expiry is disabled for the two ordered deletion events.

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
    attempt_count integer
)
language plpgsql
set search_path = integration, pg_temp
as $$
begin
  if nullif(trim(p_worker_id),'') is null then raise exception 'worker_id_required'; end if;
  if p_batch_size < 1 or p_batch_size > 50 then raise exception 'invalid_batch_size'; end if;
  if p_event_types is null or cardinality(p_event_types)=0 then raise exception 'event_types_required'; end if;

  update integration.outbox_messages m
  set status='Failed',locked_at_utc=null,locked_by=null,
      available_at_utc=now(),last_error_code='stale_worker_lock',last_error_at_utc=now()
  where m.status='Processing'
    and m.event_type=any(p_event_types)
    and m.locked_at_utc < now()-interval '10 minutes'
    and (
      m.event_type in ('identity.session_revoke_requested','identity.account_deletion_requested')
      or m.created_at_utc + make_interval(secs=>m.max_age_seconds) > now()
    );

  update integration.outbox_messages m
  set status='DeadLetter',locked_at_utc=null,locked_by=null,
      last_error_code='message_expired',last_error_at_utc=now(),
      dead_lettered_at_utc=coalesce(dead_lettered_at_utc,now())
  where m.status in ('Pending','Failed','Processing')
    and m.event_type=any(p_event_types)
    and m.event_type not in ('identity.session_revoke_requested','identity.account_deletion_requested')
    and m.created_at_utc + make_interval(secs=>m.max_age_seconds) <= now()
    and (m.status <> 'Processing' or m.locked_at_utc < now()-interval '10 minutes');

  return query
  with candidates as (
    select m.id
    from integration.outbox_messages m
    where m.status in ('Pending','Failed')
      and m.event_type=any(p_event_types)
      and m.available_at_utc<=now()
      and (
        m.event_type in ('identity.session_revoke_requested','identity.account_deletion_requested')
        or m.created_at_utc + make_interval(secs=>m.max_age_seconds)>now()
      )
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
            m.attempt_count;
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
  v_event_type character varying;
  v_dead boolean;
begin
  if p_retry_seconds < 1 or p_retry_seconds > 86400 then
    raise exception 'invalid_retry_seconds';
  end if;

  select attempt_count,max_attempts,created_at_utc,max_age_seconds,event_type
  into v_attempts,v_max_attempts,v_created_at,v_max_age,v_event_type
  from integration.outbox_messages
  where id=p_message_id and status='Processing' and locked_by=p_worker_id
  for update;
  if not found then return false; end if;

  v_dead := p_permanent
    or v_attempts>=v_max_attempts
    or (
      v_event_type not in ('identity.session_revoke_requested','identity.account_deletion_requested')
      and v_created_at + make_interval(secs=>v_max_age)<=now()
    );

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
