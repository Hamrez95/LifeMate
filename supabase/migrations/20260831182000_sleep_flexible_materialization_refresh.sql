create or replace function lifemate.refresh_flexible_schedule_materialization()
returns trigger
language plpgsql
set search_path=pg_catalog,lifemate
as $$
begin
  if new.mode <> 'flexible_interval' then
    return new;
  end if;

  if old.status is distinct from new.status
     and new.status in ('Applied','Undone','Expired','Cancelled') then
    delete from lifemate.dose_occurrences o
    using lifemate.medication_schedule_optimization_changes c
    where c.run_id=new.id
      and c.owner_person_id=new.owner_person_id
      and o.treatment_plan_id=c.treatment_plan_id
      and o.patient_person_id=new.owner_person_id
      and o.status='Scheduled'
      and o.scheduled_at_utc > now()
      and o.scheduled_local_date between
        new.effective_from_local_date and new.effective_until_local_date;
  end if;
  return new;
end;
$$;

revoke all on function lifemate.refresh_flexible_schedule_materialization() from public;

drop trigger if exists trg_refresh_flexible_schedule_materialization
  on lifemate.medication_schedule_optimization_runs;
create trigger trg_refresh_flexible_schedule_materialization
after update of status on lifemate.medication_schedule_optimization_runs
for each row execute function lifemate.refresh_flexible_schedule_materialization();

comment on function lifemate.refresh_flexible_schedule_materialization() is
  'Invalidates only untouched future Scheduled rows when a bounded flexible run is applied or removed; historical adherence remains immutable.';
