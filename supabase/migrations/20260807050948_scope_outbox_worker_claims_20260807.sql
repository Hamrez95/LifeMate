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
  if p_batch_size < 1 or p_batch_size > 100 then raise exception 'invalid_batch_size'; end if;
  if p_event_types is null or cardinality(p_event_types)=0 then raise exception 'event_types_required'; end if;

  return query
  with candidates as (
    select m.id
    from integration.outbox_messages m
    where m.status in ('Pending','Failed')
      and m.event_type = any(p_event_types)
      and m.available_at_utc <= now()
      and (m.locked_at_utc is null or m.locked_at_utc < now() - interval '10 minutes')
    order by m.available_at_utc,m.created_at_utc,m.id
    for update skip locked
    limit p_batch_size
  )
  update integration.outbox_messages m
     set status='Processing',locked_at_utc=now(),locked_by=p_worker_id,
         attempt_count=m.attempt_count+1
    from candidates c
   where m.id=c.id
  returning m.id,m.aggregate_type,m.aggregate_id,m.event_type,m.payload_json,m.attempt_count;
end
$$;
revoke execute on function integration.claim_outbox_messages_for_events(character varying,integer,character varying[]) from public;
