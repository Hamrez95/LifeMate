create table if not exists lifemate.medication_schedule_preferences (
  owner_person_id uuid primary key references core.persons(id) on delete cascade,
  time_zone varchar(64) not null,
  sleep_window_enabled boolean not null default false,
  sleep_start_local_time time,
  sleep_end_local_time time,
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint medication_schedule_preferences_sleep_window_check check (
    (sleep_window_enabled = false)
    or (sleep_start_local_time is not null and sleep_end_local_time is not null)
  )
);

create table if not exists lifemate.treatment_plan_timing_constraints (
  treatment_plan_id uuid primary key references lifemate.treatment_plans(id) on delete cascade,
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  nearby_grouping_enabled boolean not null default false,
  timing_locked boolean not null default false,
  manual_spacing_before_minutes integer not null default 0 check (manual_spacing_before_minutes between 0 and 1440),
  manual_spacing_after_minutes integer not null default 0 check (manual_spacing_after_minutes between 0 and 1440),
  timing_note varchar(240),
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

create index if not exists ix_treatment_plan_timing_constraints_owner_person
  on lifemate.treatment_plan_timing_constraints(owner_person_id, treatment_plan_id);

create or replace function lifemate.enforce_treatment_plan_timing_constraint_owner()
returns trigger
language plpgsql
set search_path = pg_catalog, lifemate
as $$
begin
  if not exists (
    select 1
    from lifemate.treatment_plans p
    where p.id = new.treatment_plan_id
      and p.patient_person_id = new.owner_person_id
  ) then
    raise exception 'timing constraint owner does not match treatment plan owner'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function lifemate.enforce_treatment_plan_timing_constraint_owner() from public;

drop trigger if exists trg_treatment_plan_timing_constraint_owner
  on lifemate.treatment_plan_timing_constraints;
create trigger trg_treatment_plan_timing_constraint_owner
before insert or update of treatment_plan_id, owner_person_id
on lifemate.treatment_plan_timing_constraints
for each row execute function lifemate.enforce_treatment_plan_timing_constraint_owner();

alter table lifemate.medication_schedule_preferences enable row level security;
alter table lifemate.medication_schedule_preferences force row level security;
alter table lifemate.treatment_plan_timing_constraints enable row level security;
alter table lifemate.treatment_plan_timing_constraints force row level security;

revoke all on lifemate.medication_schedule_preferences from public, anon, authenticated;
revoke all on lifemate.treatment_plan_timing_constraints from public, anon, authenticated;
grant select, insert, update, delete on lifemate.medication_schedule_preferences to lifemate_edge_runtime;
grant select, insert, update, delete on lifemate.treatment_plan_timing_constraints to lifemate_edge_runtime;
grant select on lifemate.medication_schedule_preferences to lifemate_backup_reader;
grant select on lifemate.treatment_plan_timing_constraints to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access on lifemate.medication_schedule_preferences;
create policy lifemate_edge_runtime_access
on lifemate.medication_schedule_preferences
for all
to lifemate_edge_runtime
using (true)
with check (true);

drop policy if exists lifemate_edge_runtime_access on lifemate.treatment_plan_timing_constraints;
create policy lifemate_edge_runtime_access
on lifemate.treatment_plan_timing_constraints
for all
to lifemate_edge_runtime
using (true)
with check (true);

comment on table lifemate.medication_schedule_preferences is
  'Person-owned non-clinical timing preferences used only by the authenticated API to prepare explicit medication schedule proposals; browser roles have no direct access.';
comment on table lifemate.treatment_plan_timing_constraints is
  'User-entered plan timing constraints. Does not encode inferred medical safety or drug interaction rules; browser roles have no direct access.';
