begin;

create or replace function messaging.refresh_campaign_execution_terminal_state(
  p_execution_id uuid
) returns void
language plpgsql
security definer
set search_path=pg_catalog,messaging,pg_temp
as $$
begin
  update messaging.campaign_executions e
  set status=case
      when exists(
        select 1
        from messaging.delivery_jobs j
        where j.execution_id=e.id
          and (
            j.status in ('Pending','InFlight')
            or (j.status='Failed' and j.attempt_count<5)
          )
      ) then e.status
      when exists(
        select 1 from messaging.delivery_jobs j
        where j.execution_id=e.id and j.status='Failed'
      ) then 'Failed'
      else 'Completed'
    end,
    updated_at_utc=now()
  where e.id=p_execution_id
    and e.status='Sending';
end $$;

revoke all on function messaging.refresh_campaign_execution_terminal_state(uuid)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_edge_runtime,lifemate_worker_runtime;

create or replace function messaging.on_campaign_delivery_terminal_change()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,messaging,pg_temp
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('Delivered','Failed','Suppressed','Cancelled') then
    perform messaging.refresh_campaign_execution_terminal_state(new.execution_id);
  end if;
  return new;
end $$;

revoke all on function messaging.on_campaign_delivery_terminal_change()
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_edge_runtime,lifemate_worker_runtime;

drop trigger if exists trg_campaign_delivery_terminal_state on messaging.delivery_jobs;
create trigger trg_campaign_delivery_terminal_state
after update of status on messaging.delivery_jobs
for each row
execute function messaging.on_campaign_delivery_terminal_change();

comment on function messaging.refresh_campaign_execution_terminal_state(uuid)
is 'Closes a Sending campaign once every delivery is terminal, including the all-suppressed late-opt-out case; any terminal delivery failure makes the execution Failed.';

commit;
