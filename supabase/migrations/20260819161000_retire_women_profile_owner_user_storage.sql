-- #385 / #289 / #217
-- Retire the remaining Women Calendar profile -> AppUser compatibility write.
--
-- The current Person-authoritative runtime no longer supplies owner_user_id.
-- This INSERT-only database boundary is defense in depth for canonical writers
-- while preserving an AppUser-only legacy writer for explicit rollback use.
-- Historical rows are not rewritten by this migration.

create or replace function core.retire_canonical_women_profile_owner_user()
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

revoke execute on function core.retire_canonical_women_profile_owner_user()
  from public;

-- Trigger names on the same timing/event fire alphabetically. This retirement
-- trigger intentionally runs before trg_sync_health_person_id:
-- * canonical writer: owner_person_id already exists -> owner_user_id is removed;
-- * legacy writer: owner_person_id is absent -> owner_user_id survives here and
--   trg_sync_health_person_id resolves the explicit Self Person mapping.
drop trigger if exists trg_00_retire_canonical_women_profile_owner_user
  on lifemate.women_calendar_profiles;
create trigger trg_00_retire_canonical_women_profile_owner_user
before insert on lifemate.women_calendar_profiles
for each row execute function core.retire_canonical_women_profile_owner_user();

comment on column lifemate.women_calendar_profiles.owner_user_id is
  'Retired AppUser compatibility linkage. Canonical Person writes store NULL; explicit rollback writers may temporarily rehydrate it.';
