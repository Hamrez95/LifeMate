-- #381 / #289 / #217
-- Women Calendar episode/daily authorization and reads are Person-authoritative.
-- Preserve historical compatibility values and old-style AppUser-only writers,
-- while preventing new canonical Person writes from persisting owner_user_id.

-- Fail closed if canonical ownership is incomplete or ambiguous before making
-- Person required / unique.
do $$
begin
  if exists (
    select 1 from lifemate.women_calendar_episodes
    where owner_person_id is null
  ) then
    raise exception 'women_calendar_episode_person_backfill_incomplete';
  end if;

  if exists (
    select owner_person_id,started_on
    from lifemate.women_calendar_episodes
    group by owner_person_id,started_on
    having count(*) > 1
  ) then
    raise exception 'women_calendar_episode_person_ownership_ambiguous';
  end if;

  if exists (
    select 1 from lifemate.women_calendar_daily_logs
    where owner_person_id is null
  ) then
    raise exception 'women_calendar_daily_person_backfill_incomplete';
  end if;

  if exists (
    select owner_person_id,logged_on
    from lifemate.women_calendar_daily_logs
    group by owner_person_id,logged_on
    having count(*) > 1
  ) then
    raise exception 'women_calendar_daily_person_ownership_ambiguous';
  end if;
end
$$;

alter table lifemate.women_calendar_episodes
  alter column owner_person_id set not null,
  alter column owner_user_id drop not null;

alter table lifemate.women_calendar_daily_logs
  alter column owner_person_id set not null,
  alter column owner_user_id drop not null;

-- Canonical concurrency/uniqueness boundary. Keep the existing legacy
-- owner_user_id/date unique constraints so an older runtime can still roll back
-- safely during staged deployment.
create unique index if not exists uq_women_calendar_episode_person_start
  on lifemate.women_calendar_episodes(owner_person_id,started_on);

create unique index if not exists uq_women_calendar_daily_person_log
  on lifemate.women_calendar_daily_logs(owner_person_id,logged_on);

-- This trigger runs alphabetically before trg_sync_health_person_id. Therefore:
-- * a canonical writer that already supplied owner_person_id loses the redundant
--   AppUser linkage before storage;
-- * a legacy writer with only owner_user_id is left untouched here, then the
--   existing compatibility trigger resolves owner_person_id afterward.
-- INSERT-only scope guarantees historical owner_user_id values survive updates.
create or replace function core.retire_canonical_women_owner_user_id()
returns trigger
language plpgsql
set search_path = pg_catalog, core, lifemate, pg_temp
as $$
begin
  if new.owner_person_id is not null then
    new.owner_user_id := null;
  end if;
  return new;
end
$$;

revoke execute on function core.retire_canonical_women_owner_user_id()
  from public;

drop trigger if exists trg_00_retire_canonical_women_owner_user
  on lifemate.women_calendar_episodes;
create trigger trg_00_retire_canonical_women_owner_user
before insert on lifemate.women_calendar_episodes
for each row execute function core.retire_canonical_women_owner_user_id();

drop trigger if exists trg_00_retire_canonical_women_owner_user
  on lifemate.women_calendar_daily_logs;
create trigger trg_00_retire_canonical_women_owner_user
before insert on lifemate.women_calendar_daily_logs
for each row execute function core.retire_canonical_women_owner_user_id();

comment on column lifemate.women_calendar_episodes.owner_person_id is
  'Canonical women-health data subject. Required for all current episode rows.';
comment on column lifemate.women_calendar_episodes.owner_user_id is
  'Legacy owner AppUser compatibility identifier. Historical/legacy-writer rows may retain it; canonical Person inserts store NULL.';
comment on column lifemate.women_calendar_daily_logs.owner_person_id is
  'Canonical women-health data subject. Required for all current daily-log rows.';
comment on column lifemate.women_calendar_daily_logs.owner_user_id is
  'Legacy owner AppUser compatibility identifier. Historical/legacy-writer rows may retain it; canonical Person inserts store NULL.';
