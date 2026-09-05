-- The worker is allowed to request bounded historical outbox pruning, but it
-- must not receive unrestricted DELETE on the live queue. Execute the bounded
-- prune as the function owner instead and keep the callable surface restricted
-- to the dedicated worker runtime role.

create or replace function integration.prune_outbox_history(
  p_processed_retention_days integer default 7,
  p_dead_letter_retention_days integer default 30,
  p_batch_size integer default 500
) returns integer
language plpgsql
security definer
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

revoke all on function integration.prune_outbox_history(integer,integer,integer) from public;
revoke all on function integration.prune_outbox_history(integer,integer,integer) from anon;
revoke all on function integration.prune_outbox_history(integer,integer,integer) from authenticated;
grant execute on function integration.prune_outbox_history(integer,integer,integer) to lifemate_worker_runtime;
