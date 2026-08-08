-- Complete the runtime foundation without removing legacy compatibility paths.
-- Portable PostgreSQL only; Supabase Auth-specific work stays in Edge adapters.

alter table integration.outbox_messages
  add column if not exists locked_at_utc timestamp with time zone,
  add column if not exists locked_by character varying(120);

create index if not exists ix_outbox_claim
  on integration.outbox_messages(available_at_utc, created_at_utc, id)
  where status in ('Pending','Failed');

create or replace function integration.claim_outbox_messages(
    p_worker_id character varying,
    p_batch_size integer default 25
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
  if nullif(trim(p_worker_id),'') is null then
    raise exception 'worker_id_required';
  end if;
  if p_batch_size < 1 or p_batch_size > 100 then
    raise exception 'invalid_batch_size';
  end if;

  return query
  with candidates as (
    select m.id
    from integration.outbox_messages m
    where m.status in ('Pending','Failed')
      and m.available_at_utc <= now()
      and (m.locked_at_utc is null or m.locked_at_utc < now() - interval '10 minutes')
    order by m.available_at_utc, m.created_at_utc, m.id
    for update skip locked
    limit p_batch_size
  )
  update integration.outbox_messages m
     set status='Processing',
         locked_at_utc=now(),
         locked_by=p_worker_id,
         attempt_count=m.attempt_count+1
    from candidates c
   where m.id=c.id
  returning m.id,m.aggregate_type,m.aggregate_id,m.event_type,m.payload_json,m.attempt_count;
end
$$;

create or replace function integration.complete_outbox_message(
    p_message_id uuid,
    p_worker_id character varying
) returns boolean
language sql
set search_path = integration, pg_temp
as $$
  update integration.outbox_messages
     set status='Processed',
         processed_at_utc=now(),
         locked_at_utc=null,
         locked_by=null,
         last_error_code=null
   where id=p_message_id
     and status='Processing'
     and locked_by=p_worker_id
  returning true
$$;

create or replace function integration.fail_outbox_message(
    p_message_id uuid,
    p_worker_id character varying,
    p_error_code character varying,
    p_retry_seconds integer default 60
) returns boolean
language plpgsql
set search_path = integration, pg_temp
as $$
declare v_attempts integer;
begin
  if p_retry_seconds < 1 or p_retry_seconds > 86400 then
    raise exception 'invalid_retry_seconds';
  end if;

  select attempt_count into v_attempts
  from integration.outbox_messages
  where id=p_message_id and status='Processing' and locked_by=p_worker_id
  for update;

  if not found then return false; end if;

  update integration.outbox_messages
     set status=case when v_attempts >= 10 then 'DeadLetter' else 'Failed' end,
         available_at_utc=case
           when v_attempts >= 10 then available_at_utc
           else now() + make_interval(secs => p_retry_seconds)
         end,
         locked_at_utc=null,
         locked_by=null,
         last_error_code=left(coalesce(nullif(trim(p_error_code),''),'worker_error'),80)
   where id=p_message_id;
  return true;
end
$$;

create or replace function care.rebuild_daily_adherence_summary(
    p_person_id uuid,
    p_summary_date date
) returns void
language plpgsql
set search_path = care, lifemate, pg_temp
as $$
declare
  v_scheduled integer;
  v_taken integer;
  v_missed integer;
  v_late integer;
begin
  if p_person_id is null or p_summary_date is null then
    raise exception 'person_and_date_required';
  end if;

  select
    count(*)::integer,
    count(*) filter (where o.status='Taken')::integer,
    count(*) filter (where o.status in ('Missed','Skipped'))::integer,
    count(*) filter (
      where o.status='Taken'
        and o.responded_at_utc is not null
        and o.responded_at_utc > o.scheduled_at_utc + interval '15 minutes'
    )::integer
  into v_scheduled,v_taken,v_missed,v_late
  from lifemate.dose_occurrences o
  where o.patient_person_id=p_person_id
    and o.scheduled_local_date=p_summary_date;

  insert into care.daily_adherence_summary(
    person_id,summary_date,scheduled_count,taken_count,missed_count,late_count,
    projection_version,rebuilt_at_utc)
  values(
    p_person_id,p_summary_date,v_scheduled,v_taken,v_missed,v_late,1,now())
  on conflict(person_id,summary_date) do update set
    scheduled_count=excluded.scheduled_count,
    taken_count=excluded.taken_count,
    missed_count=excluded.missed_count,
    late_count=excluded.late_count,
    projection_version=care.daily_adherence_summary.projection_version+1,
    rebuilt_at_utc=excluded.rebuilt_at_utc;
end
$$;

create or replace function integration.enqueue_adherence_projection_refresh()
returns trigger
language plpgsql
set search_path = integration, lifemate, pg_temp
as $$
declare
  v_person_id uuid;
  v_date date;
  v_occurrence_id uuid;
begin
  v_occurrence_id := coalesce(new.id, old.id);
  v_person_id := coalesce(new.patient_person_id, old.patient_person_id);
  v_date := coalesce(new.scheduled_local_date, old.scheduled_local_date);

  if v_person_id is null or v_date is null then return coalesce(new,old); end if;

  insert into integration.outbox_messages(
    aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc)
  values(
    'person',v_person_id,'care.adherence_projection_refresh_requested',
    'adherence-projection:'||v_person_id::text||':'||v_date::text||':'||txid_current()::text,
    jsonb_build_object('personId',v_person_id,'summaryDate',v_date,'occurrenceId',v_occurrence_id),
    'Pending',now())
  on conflict(idempotency_key) do nothing;
  return coalesce(new,old);
end
$$;

drop trigger if exists trg_enqueue_adherence_projection_refresh on lifemate.dose_occurrences;
create trigger trg_enqueue_adherence_projection_refresh
after insert or update of status,responded_at_utc,scheduled_local_date,patient_person_id
on lifemate.dose_occurrences
for each row execute function integration.enqueue_adherence_projection_refresh();

create or replace function identity.finalize_account_deletion(
    p_request_id uuid
) returns boolean
language plpgsql
set search_path = identity, core, ecosystem, security, consent, commerce, lifemate, pg_temp
as $$
declare
  v_account_id uuid;
  v_self_person_id uuid;
begin
  select account_id into v_account_id
  from identity.account_deletion_requests
  where id=p_request_id and status in ('Requested','Processing')
  for update;
  if not found then return false; end if;

  update identity.account_deletion_requests
     set status='Processing',processing_started_at_utc=coalesce(processing_started_at_utc,now())
   where id=p_request_id;

  select person_id into v_self_person_id
  from core.account_person_links
  where account_id=v_account_id and link_type='Self'
  order by created_at_utc
  limit 1;

  delete from identity.contact_points where account_id=v_account_id;
  delete from identity.external_identities where account_id=v_account_id;

  update core.account_person_links
     set status='Revoked',revoked_at_utc=coalesce(revoked_at_utc,now())
   where account_id=v_account_id and status='Active';

  if v_self_person_id is not null then
    update core.person_profiles
       set display_name='Deleted LifeMate User',
           avatar_key=null,
           profile_photo_path=null,
           updated_at_utc=now()
     where person_id=v_self_person_id;

    update core.persons
       set status='Deleted',updated_at_utc=now()
     where id=v_self_person_id;
  end if;

  update lifemate.user_profiles
     set display_name='Deleted LifeMate User',
         phone_number=null,
         email=null,
         profile_photo_path=null,
         updated_at_utc=now()
   where user_id=v_account_id;

  update ecosystem.app_enrollments set status='Left'
   where account_id=v_account_id and status <> 'Left';

  update identity.accounts
     set status='Deleted',updated_at_utc=now()
   where id=v_account_id;

  update identity.account_deletion_requests
     set status='Completed',completed_at_utc=now()
   where id=p_request_id;

  return true;
end
$$;

create or replace function identity.latest_account_deletion_request(
    p_account_id uuid
) returns table(
    id uuid,status character varying,requested_at_utc timestamp with time zone,
    processing_started_at_utc timestamp with time zone,
    completed_at_utc timestamp with time zone,
    retention_policy_version character varying
)
language sql
stable
set search_path = identity, pg_temp
as $$
  select r.id,r.status,r.requested_at_utc,r.processing_started_at_utc,
         r.completed_at_utc,r.retention_policy_version
  from identity.account_deletion_requests r
  where r.account_id=p_account_id
  order by r.requested_at_utc desc,r.id desc
  limit 1
$$;

revoke execute on function integration.claim_outbox_messages(character varying,integer) from public;
revoke execute on function integration.complete_outbox_message(uuid,character varying) from public;
revoke execute on function integration.fail_outbox_message(uuid,character varying,character varying,integer) from public;
revoke execute on function care.rebuild_daily_adherence_summary(uuid,date) from public;
revoke execute on function integration.enqueue_adherence_projection_refresh() from public;
revoke execute on function identity.finalize_account_deletion(uuid) from public;
revoke execute on function identity.latest_account_deletion_request(uuid) from public;
