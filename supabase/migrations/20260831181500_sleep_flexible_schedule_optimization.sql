do $$
begin
  if to_regrole('lifemate_edge_runtime') is null then
    create role lifemate_edge_runtime nologin;
  end if;
  if to_regrole('lifemate_backup_reader') is null then
    create role lifemate_backup_reader nologin;
  end if;
end $$;

create table if not exists lifemate.medication_schedule_optimization_runs (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  mode varchar(32) not null check (mode in ('strict_anchor_shift','flexible_interval')),
  algorithm_version varchar(32) not null,
  consent_text_version varchar(32) not null,
  schedule_preferences_version integer not null check (schedule_preferences_version >= 0),
  sleep_window_enabled boolean not null,
  sleep_window_snapshot_hash char(64),
  max_variation_minutes integer,
  effective_from_local_date date not null,
  effective_until_local_date date not null,
  status varchar(24) not null default 'Previewed'
    check (status in ('Previewed','Applied','Undone','Expired','Cancelled','Stale')),
  expires_at_utc timestamptz not null,
  confirmed_at_utc timestamptz,
  applied_at_utc timestamptz,
  undone_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (effective_until_local_date >= effective_from_local_date),
  check (expires_at_utc > created_at_utc),
  check (
    (mode='strict_anchor_shift' and max_variation_minutes is null)
    or
    (mode='flexible_interval' and max_variation_minutes between 5 and 180)
  ),
  check (sleep_window_snapshot_hash is null or sleep_window_snapshot_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists ix_med_schedule_opt_runs_owner_status
  on lifemate.medication_schedule_optimization_runs
  (owner_person_id,status,effective_until_local_date desc,id);

create table if not exists lifemate.medication_schedule_optimization_changes (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references lifemate.medication_schedule_optimization_runs(id) on delete cascade,
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  treatment_plan_id uuid not null references lifemate.treatment_plans(id) on delete cascade,
  expected_treatment_plan_version integer not null check (expected_treatment_plan_version > 0),
  expected_timing_version integer not null check (expected_timing_version >= 0),
  entered_interval_minutes integer not null check (entered_interval_minutes between 60 and 525600),
  old_anchor_local_time time,
  proposed_anchor_local_time time,
  reason varchar(32) not null check (reason in ('sleep_preference','nearby_grouping','both')),
  created_at_utc timestamptz not null default now(),
  unique(run_id,treatment_plan_id)
);

create index if not exists ix_med_schedule_opt_changes_plan
  on lifemate.medication_schedule_optimization_changes(treatment_plan_id,run_id);

create table if not exists lifemate.dose_occurrence_overrides (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references lifemate.medication_schedule_optimization_runs(id) on delete cascade,
  change_id uuid not null references lifemate.medication_schedule_optimization_changes(id) on delete cascade,
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  treatment_plan_id uuid not null references lifemate.treatment_plans(id) on delete cascade,
  original_local_date date not null,
  original_local_time time not null,
  replacement_local_date date not null,
  replacement_local_time time not null,
  time_zone varchar(64) not null,
  entered_interval_minutes integer not null check (entered_interval_minutes between 60 and 525600),
  actual_gap_minutes integer,
  variation_minutes integer not null,
  status varchar(16) not null default 'Active' check (status in ('Active','Undone','Expired')),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (abs(variation_minutes) <= 180),
  check (actual_gap_minutes is null or actual_gap_minutes > 0),
  unique(run_id,treatment_plan_id,original_local_date,original_local_time)
);

create unique index if not exists uq_dose_occurrence_override_active_identity
  on lifemate.dose_occurrence_overrides
  (treatment_plan_id,original_local_date,original_local_time)
  where status='Active';

create index if not exists ix_dose_occurrence_overrides_owner_window
  on lifemate.dose_occurrence_overrides
  (owner_person_id,status,replacement_local_date,replacement_local_time);

create or replace function lifemate.enforce_schedule_optimization_change_owner()
returns trigger
language plpgsql
set search_path=pg_catalog,lifemate
as $$
begin
  if not exists (
    select 1 from lifemate.medication_schedule_optimization_runs r
    where r.id=new.run_id and r.owner_person_id=new.owner_person_id
  ) then
    raise exception 'optimization change owner mismatch' using errcode='23514';
  end if;
  if not exists (
    select 1 from lifemate.treatment_plans p
    where p.id=new.treatment_plan_id and p.patient_person_id=new.owner_person_id
  ) then
    raise exception 'optimization treatment owner mismatch' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function lifemate.enforce_schedule_optimization_change_owner() from public;

drop trigger if exists trg_schedule_optimization_change_owner
  on lifemate.medication_schedule_optimization_changes;
create trigger trg_schedule_optimization_change_owner
before insert or update of run_id,owner_person_id,treatment_plan_id
on lifemate.medication_schedule_optimization_changes
for each row execute function lifemate.enforce_schedule_optimization_change_owner();

create or replace function lifemate.enforce_dose_occurrence_override_owner()
returns trigger
language plpgsql
set search_path=pg_catalog,lifemate
as $$
begin
  if not exists (
    select 1
    from lifemate.medication_schedule_optimization_changes c
    join lifemate.medication_schedule_optimization_runs r on r.id=c.run_id
    where c.id=new.change_id and c.run_id=new.run_id
      and c.treatment_plan_id=new.treatment_plan_id
      and c.owner_person_id=new.owner_person_id
      and r.owner_person_id=new.owner_person_id
  ) then
    raise exception 'dose occurrence override owner mismatch' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function lifemate.enforce_dose_occurrence_override_owner() from public;

drop trigger if exists trg_dose_occurrence_override_owner
  on lifemate.dose_occurrence_overrides;
create trigger trg_dose_occurrence_override_owner
before insert or update of run_id,change_id,owner_person_id,treatment_plan_id
on lifemate.dose_occurrence_overrides
for each row execute function lifemate.enforce_dose_occurrence_override_owner();

create or replace function lifemate.apply_active_dose_occurrence_override()
returns trigger
language plpgsql
set search_path=pg_catalog,lifemate
as $$
declare
  v_override lifemate.dose_occurrence_overrides%rowtype;
begin
  if new.status <> 'Scheduled' then
    return new;
  end if;

  select o.* into v_override
  from lifemate.dose_occurrence_overrides o
  join lifemate.medication_schedule_optimization_runs r on r.id=o.run_id
  where o.treatment_plan_id=new.treatment_plan_id
    and o.owner_person_id=new.patient_person_id
    and o.original_local_date=new.scheduled_local_date
    and o.original_local_time=new.scheduled_local_time
    and o.status='Active'
    and r.status='Applied'
    and r.mode='flexible_interval'
    and o.original_local_date between r.effective_from_local_date and r.effective_until_local_date
  order by r.applied_at_utc desc nulls last,o.id
  limit 1;

  if found then
    new.scheduled_local_date := v_override.replacement_local_date;
    new.scheduled_local_time := v_override.replacement_local_time;
    new.time_zone := v_override.time_zone;
    new.scheduled_at_utc :=
      ((v_override.replacement_local_date + v_override.replacement_local_time)
        at time zone v_override.time_zone);
  end if;
  return new;
end;
$$;
revoke all on function lifemate.apply_active_dose_occurrence_override() from public;

drop trigger if exists trg_apply_active_dose_occurrence_override
  on lifemate.dose_occurrences;
create trigger trg_apply_active_dose_occurrence_override
before insert on lifemate.dose_occurrences
for each row execute function lifemate.apply_active_dose_occurrence_override();

alter table lifemate.medication_schedule_optimization_runs enable row level security;
alter table lifemate.medication_schedule_optimization_runs force row level security;
alter table lifemate.medication_schedule_optimization_changes enable row level security;
alter table lifemate.medication_schedule_optimization_changes force row level security;
alter table lifemate.dose_occurrence_overrides enable row level security;
alter table lifemate.dose_occurrence_overrides force row level security;

revoke all on lifemate.medication_schedule_optimization_runs from public;
revoke all on lifemate.medication_schedule_optimization_changes from public;
revoke all on lifemate.dose_occurrence_overrides from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on lifemate.medication_schedule_optimization_runs from anon';
    execute 'revoke all on lifemate.medication_schedule_optimization_changes from anon';
    execute 'revoke all on lifemate.dose_occurrence_overrides from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on lifemate.medication_schedule_optimization_runs from authenticated';
    execute 'revoke all on lifemate.medication_schedule_optimization_changes from authenticated';
    execute 'revoke all on lifemate.dose_occurrence_overrides from authenticated';
  end if;
end $$;

grant select,insert,update,delete on lifemate.medication_schedule_optimization_runs to lifemate_edge_runtime;
grant select,insert,update,delete on lifemate.medication_schedule_optimization_changes to lifemate_edge_runtime;
grant select,insert,update,delete on lifemate.dose_occurrence_overrides to lifemate_edge_runtime;
grant select on lifemate.medication_schedule_optimization_runs to lifemate_backup_reader;
grant select on lifemate.medication_schedule_optimization_changes to lifemate_backup_reader;
grant select on lifemate.dose_occurrence_overrides to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access on lifemate.medication_schedule_optimization_runs;
drop policy if exists lifemate_edge_runtime_access on lifemate.medication_schedule_optimization_changes;
drop policy if exists lifemate_edge_runtime_access on lifemate.dose_occurrence_overrides;
create policy lifemate_edge_runtime_access on lifemate.medication_schedule_optimization_runs
for all to lifemate_edge_runtime using(true) with check(true);
create policy lifemate_edge_runtime_access on lifemate.medication_schedule_optimization_changes
for all to lifemate_edge_runtime using(true) with check(true);
create policy lifemate_edge_runtime_access on lifemate.dose_occurrence_overrides
for all to lifemate_edge_runtime using(true) with check(true);

comment on table lifemate.medication_schedule_optimization_runs is
  'Time-bounded user-confirmed scheduling proposals. Consent records a displayed timing choice and is not clinical validation.';
comment on table lifemate.dose_occurrence_overrides is
  'Future occurrence timing overrides approved by the owner. Canonical recurrence remains unchanged and resumes after the approved range.';
comment on function lifemate.apply_active_dose_occurrence_override() is
  'Materialization hook for owner-confirmed bounded flexible timing overrides. It never alters historical adherence or canonical recurrence.';
