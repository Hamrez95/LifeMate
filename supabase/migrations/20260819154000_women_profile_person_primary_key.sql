-- #383 / #289 / #217
-- Move the Women Calendar profile's physical identity boundary from legacy
-- AppUser ownership to canonical Person ownership without yet removing the
-- compatibility value required for a safe backend rollback.

-- Fail closed before changing the primary/uniqueness boundary.
do $$
begin
  if exists (
    select 1
    from lifemate.women_calendar_profiles
    where owner_person_id is null
  ) then
    raise exception 'women_calendar_profile_person_backfill_incomplete';
  end if;

  if exists (
    select owner_person_id
    from lifemate.women_calendar_profiles
    group by owner_person_id
    having count(*) > 1
  ) then
    raise exception 'women_calendar_profile_person_ownership_ambiguous';
  end if;
end
$$;

-- Preserve legacy lookup/write uniqueness before replacing the old AppUser PK.
create unique index if not exists uq_women_calendar_profile_owner_user
  on lifemate.women_calendar_profiles(owner_user_id);

alter table lifemate.women_calendar_profiles
  drop constraint if exists women_calendar_profiles_pkey;

alter table lifemate.women_calendar_profiles
  alter column owner_person_id set not null,
  alter column owner_user_id drop not null;

alter table lifemate.women_calendar_profiles
  add constraint women_calendar_profiles_pkey primary key(owner_person_id);

comment on column lifemate.women_calendar_profiles.owner_person_id is
  'Canonical Women Calendar profile owner and physical primary-key identity.';
comment on column lifemate.women_calendar_profiles.owner_user_id is
  'Legacy AppUser compatibility lookup retained temporarily for staged rollback; not the canonical ownership key.';
