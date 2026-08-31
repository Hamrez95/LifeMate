do $$
begin
  if to_regrole('lifemate_edge_runtime') is null then
    create role lifemate_edge_runtime nologin;
  end if;
  if to_regrole('lifemate_backup_reader') is null then
    create role lifemate_backup_reader nologin;
  end if;
end $$;

create table if not exists lifemate.medication_schedule_optimization_proposals (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  algorithm_version varchar(32) not null,
  status varchar(24) not null default 'Previewed'
    check (status in ('Previewed','Applied','Expired','Cancelled','Stale')),
  expected_notification_reduction integer not null default 0
    check (expected_notification_reduction >= 0),
  expires_at_utc timestamptz not null,
  confirmed_at_utc timestamptz,
  applied_at_utc timestamptz,
  idempotency_key_hash char(64),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (expires_at_utc > created_at_utc),
  check (idempotency_key_hash is null or idempotency_key_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists ix_med_schedule_optimization_owner_status
  on lifemate.medication_schedule_optimization_proposals
  (owner_person_id,status,expires_at_utc desc,id);

create table if not exists lifemate.medication_schedule_optimization_plan_changes (
  proposal_id uuid not null references lifemate.medication_schedule_optimization_proposals(id) on delete cascade,
  treatment_plan_id uuid not null references lifemate.treatment_plans(id) on delete cascade,
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  old_anchor_local_time time not null,
  new_anchor_local_time time not null,
  interval_hours integer not null check (interval_hours between 1 and 8760),
  expected_treatment_plan_version integer not null check (expected_treatment_plan_version > 0),
  expected_timing_version integer not null check (expected_timing_version >= 0),
  shift_minutes integer not null check (shift_minutes between 0 and 29),
  created_at_utc timestamptz not null default now(),
  primary key (proposal_id,treatment_plan_id)
);

create index if not exists ix_med_schedule_optimization_change_plan
  on lifemate.medication_schedule_optimization_plan_changes
  (treatment_plan_id,proposal_id);

create or replace function lifemate.enforce_medication_schedule_optimization_owner()
returns trigger
language plpgsql
set search_path = pg_catalog,lifemate
as $$
begin
  if not exists (
    select 1 from lifemate.medication_schedule_optimization_proposals p
    where p.id = new.proposal_id and p.owner_person_id = new.owner_person_id
  ) then
    raise exception 'optimization change owner does not match proposal owner'
      using errcode = '23514';
  end if;
  if not exists (
    select 1 from lifemate.treatment_plans p
    where p.id = new.treatment_plan_id and p.patient_person_id = new.owner_person_id
  ) then
    raise exception 'optimization change owner does not match treatment owner'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function lifemate.enforce_medication_schedule_optimization_owner() from public;

drop trigger if exists trg_med_schedule_optimization_change_owner
  on lifemate.medication_schedule_optimization_plan_changes;
create trigger trg_med_schedule_optimization_change_owner
before insert or update of proposal_id,treatment_plan_id,owner_person_id
on lifemate.medication_schedule_optimization_plan_changes
for each row execute function lifemate.enforce_medication_schedule_optimization_owner();

alter table lifemate.medication_schedule_optimization_proposals enable row level security;
alter table lifemate.medication_schedule_optimization_proposals force row level security;
alter table lifemate.medication_schedule_optimization_plan_changes enable row level security;
alter table lifemate.medication_schedule_optimization_plan_changes force row level security;

revoke all on lifemate.medication_schedule_optimization_proposals from public;
revoke all on lifemate.medication_schedule_optimization_plan_changes from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on lifemate.medication_schedule_optimization_proposals from anon';
    execute 'revoke all on lifemate.medication_schedule_optimization_plan_changes from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on lifemate.medication_schedule_optimization_proposals from authenticated';
    execute 'revoke all on lifemate.medication_schedule_optimization_plan_changes from authenticated';
  end if;
end $$;

grant select,insert,update,delete on lifemate.medication_schedule_optimization_proposals to lifemate_edge_runtime;
grant select,insert,update,delete on lifemate.medication_schedule_optimization_plan_changes to lifemate_edge_runtime;
grant select on lifemate.medication_schedule_optimization_proposals to lifemate_backup_reader;
grant select on lifemate.medication_schedule_optimization_plan_changes to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access on lifemate.medication_schedule_optimization_proposals;
create policy lifemate_edge_runtime_access
on lifemate.medication_schedule_optimization_proposals
for all to lifemate_edge_runtime using (true) with check (true);

drop policy if exists lifemate_edge_runtime_access on lifemate.medication_schedule_optimization_plan_changes;
create policy lifemate_edge_runtime_access
on lifemate.medication_schedule_optimization_plan_changes
for all to lifemate_edge_runtime using (true) with check (true);

comment on table lifemate.medication_schedule_optimization_proposals is
  'Short-lived self-owned reminder-convenience proposals. This table does not represent medical interaction or suitability advice.';
comment on table lifemate.medication_schedule_optimization_plan_changes is
  'Version-pinned proposed anchor changes. Exact interval_hours is immutable across a strict nearby-dose proposal.';
