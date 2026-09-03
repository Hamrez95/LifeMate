create schema if not exists pregnancy;
revoke all on schema pregnancy from public;

do $$
begin
  if to_regrole('lifemate_edge_runtime') is null then
    create role lifemate_edge_runtime nologin;
  end if;
  if to_regrole('lifemate_backup_reader') is null then
    create role lifemate_backup_reader nologin bypassrls;
  end if;
end $$;

grant usage on schema pregnancy to lifemate_edge_runtime,lifemate_backup_reader;

create table if not exists pregnancy.episodes (
  id uuid primary key default gen_random_uuid(),
  mother_person_id uuid not null references core.persons(id) on delete cascade,
  status varchar(16) not null default 'draft'
    check (status in ('draft','active','ended')),
  dating_method varchar(32)
    check (dating_method is null or dating_method in (
      'lmp','edd','clinician_ultrasound','manual_correction','imported'
    )),
  lmp_date date,
  estimated_due_date date,
  dating_reference_date date,
  gestational_age_at_reference_days integer
    check (
      gestational_age_at_reference_days is null
      or gestational_age_at_reference_days between 0 and 308
    ),
  outcome varchar(32)
    check (outcome is null or outcome in (
      'delivered','pregnancy_loss','other','unknown'
    )),
  activated_at_utc timestamptz,
  ended_at_utc timestamptz,
  creation_idempotency_key_hash char(64) not null
    check (creation_idempotency_key_hash ~ '^[0-9a-f]{64}$'),
  version integer not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_pregnancy_episode_dating_presence check (
    (
      dating_method is null
      and lmp_date is null
      and estimated_due_date is null
      and dating_reference_date is null
      and gestational_age_at_reference_days is null
    ) or dating_method is not null
  ),
  constraint ck_pregnancy_episode_dating_method_inputs check (
    dating_method is null
    or (dating_method='lmp' and lmp_date is not null)
    or (dating_method='edd' and estimated_due_date is not null)
    or (
      dating_method='clinician_ultrasound'
      and dating_reference_date is not null
      and gestational_age_at_reference_days is not null
    )
    or (
      dating_method in ('manual_correction','imported')
      and (
        lmp_date is not null
        or estimated_due_date is not null
        or (
          dating_reference_date is not null
          and gestational_age_at_reference_days is not null
        )
      )
    )
  ),
  constraint ck_pregnancy_episode_reference_pair check (
    (dating_reference_date is null) =
    (gestational_age_at_reference_days is null)
  ),
  constraint ck_pregnancy_episode_activation check (
    status <> 'active' or activated_at_utc is not null
  ),
  constraint ck_pregnancy_episode_end check (
    status <> 'ended' or ended_at_utc is not null
  ),
  constraint ck_pregnancy_episode_outcome check (
    status='ended' or outcome is null
  ),
  constraint ck_pregnancy_episode_timestamps check (
    ended_at_utc is null
    or activated_at_utc is null
    or ended_at_utc >= activated_at_utc
  )
);

create unique index if not exists ux_pregnancy_one_active_per_mother
  on pregnancy.episodes(mother_person_id)
  where status='active';
create unique index if not exists ux_pregnancy_creation_idempotency
  on pregnancy.episodes(mother_person_id,creation_idempotency_key_hash);
create index if not exists ix_pregnancy_episode_mother_history
  on pregnancy.episodes(mother_person_id,created_at_utc desc,id);

create table if not exists pregnancy.dating_revisions (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete cascade,
  revision_number integer not null check (revision_number >= 1),
  previous_dating_method varchar(32),
  new_dating_method varchar(32) not null,
  previous_lmp_date date,
  new_lmp_date date,
  previous_estimated_due_date date,
  new_estimated_due_date date,
  previous_reference_date date,
  new_reference_date date,
  previous_gestational_age_at_reference_days integer,
  new_gestational_age_at_reference_days integer,
  source varchar(32) not null
    check (source in (
      'lmp','clinician_ultrasound','manual_correction','imported',
      'system_reconciliation'
    )),
  actor_account_id uuid references identity.accounts(id) on delete set null,
  reason_code varchar(64),
  idempotency_key_hash char(64) not null
    check (idempotency_key_hash ~ '^[0-9a-f]{64}$'),
  created_at_utc timestamptz not null default now(),
  unique(episode_id,revision_number),
  unique(episode_id,idempotency_key_hash),
  constraint ck_pregnancy_revision_method check (
    new_dating_method in (
      'lmp','edd','clinician_ultrasound','manual_correction','imported'
    )
  ),
  constraint ck_pregnancy_revision_prev_method check (
    previous_dating_method is null
    or previous_dating_method in (
      'lmp','edd','clinician_ultrasound','manual_correction','imported'
    )
  ),
  constraint ck_pregnancy_revision_new_reference_pair check (
    (new_reference_date is null) =
    (new_gestational_age_at_reference_days is null)
  ),
  constraint ck_pregnancy_revision_prev_reference_pair check (
    (previous_reference_date is null) =
    (previous_gestational_age_at_reference_days is null)
  ),
  constraint ck_pregnancy_revision_new_ga check (
    new_gestational_age_at_reference_days is null
    or new_gestational_age_at_reference_days between 0 and 308
  ),
  constraint ck_pregnancy_revision_prev_ga check (
    previous_gestational_age_at_reference_days is null
    or previous_gestational_age_at_reference_days between 0 and 308
  ),
  constraint ck_pregnancy_revision_reason check (
    reason_code is null or length(btrim(reason_code)) between 1 and 64
  )
);

create index if not exists ix_pregnancy_dating_episode_time
  on pregnancy.dating_revisions(
    episode_id,revision_number desc,created_at_utc desc
  );

create table if not exists pregnancy.episode_events (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references pregnancy.episodes(id) on delete cascade,
  event_type varchar(32) not null
    check (event_type in (
      'created','activated','dating_revised','ended','outcome_recorded'
    )),
  from_status varchar(16)
    check (from_status is null or from_status in ('draft','active','ended')),
  to_status varchar(16)
    check (to_status is null or to_status in ('draft','active','ended')),
  outcome varchar(32)
    check (outcome is null or outcome in (
      'delivered','pregnancy_loss','other','unknown'
    )),
  actor_account_id uuid references identity.accounts(id) on delete set null,
  idempotency_key_hash char(64) not null
    check (idempotency_key_hash ~ '^[0-9a-f]{64}$'),
  occurred_at_utc timestamptz not null default now(),
  created_at_utc timestamptz not null default now(),
  unique(episode_id,idempotency_key_hash)
);

create index if not exists ix_pregnancy_events_episode_time
  on pregnancy.episode_events(episode_id,occurred_at_utc desc,id);

create or replace function pregnancy.touch_episode_version()
returns trigger
language plpgsql
set search_path=pg_catalog,pregnancy
as $$
begin
  new.version := old.version + 1;
  new.updated_at_utc := now();
  return new;
end;
$$;

revoke all on function pregnancy.touch_episode_version() from public;

drop trigger if exists trg_pregnancy_episode_touch on pregnancy.episodes;
create trigger trg_pregnancy_episode_touch
before update on pregnancy.episodes
for each row execute function pregnancy.touch_episode_version();

alter table pregnancy.episodes enable row level security;
alter table pregnancy.episodes force row level security;
alter table pregnancy.dating_revisions enable row level security;
alter table pregnancy.dating_revisions force row level security;
alter table pregnancy.episode_events enable row level security;
alter table pregnancy.episode_events force row level security;

revoke all on pregnancy.episodes,pregnancy.dating_revisions,
  pregnancy.episode_events from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on pregnancy.episodes,pregnancy.dating_revisions,pregnancy.episode_events from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on pregnancy.episodes,pregnancy.dating_revisions,pregnancy.episode_events from authenticated';
  end if;
  if to_regrole('service_role') is not null then
    execute 'revoke all on pregnancy.episodes,pregnancy.dating_revisions,pregnancy.episode_events from service_role';
  end if;
end $$;

grant select,insert,update,delete
  on pregnancy.episodes,pregnancy.dating_revisions,pregnancy.episode_events
  to lifemate_edge_runtime;
grant select
  on pregnancy.episodes,pregnancy.dating_revisions,pregnancy.episode_events
  to lifemate_backup_reader;

drop policy if exists lifemate_edge_runtime_access on pregnancy.episodes;
create policy lifemate_edge_runtime_access
on pregnancy.episodes
for all to lifemate_edge_runtime
using(true) with check(true);

drop policy if exists lifemate_edge_runtime_access on pregnancy.dating_revisions;
create policy lifemate_edge_runtime_access
on pregnancy.dating_revisions
for all to lifemate_edge_runtime
using(true) with check(true);

drop policy if exists lifemate_edge_runtime_access on pregnancy.episode_events;
create policy lifemate_edge_runtime_access
on pregnancy.episode_events
for all to lifemate_edge_runtime
using(true) with check(true);

comment on schema pregnancy is
  'CocoonMate pregnancy-specific bounded health domain. Mother ownership is core.persons; shared health facts remain in canonical LifeMate domains.';
comment on table pregnancy.episodes is
  'Person-owned pregnancy episodes. Gestational week/day is derived from dating inputs and never stored as mutable current-week truth.';
comment on table pregnancy.dating_revisions is
  'Immutable provenance for clinically meaningful dating changes; revisions preserve previous and new dating inputs.';
comment on table pregnancy.episode_events is
  'Idempotent pregnancy lifecycle/domain events only; not a duplicate universal timeline.';
