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

-- Old and current runtime versions both emit profile audit resource_id using the
-- compatibility AppUser identifier. Normalize only new profile audit resources
-- at the database boundary so actor_user_id remains deliberate actor provenance
-- while the sensitive profile resource is keyed by Person.
create or replace function core.canonicalize_women_profile_audit_resource()
returns trigger
language plpgsql
set search_path = pg_catalog, core, identity, lifemate, pg_temp
as $$
declare
  v_person_id uuid;
begin
  if new.resource_type <> 'women_calendar_profile' or new.resource_id is null then
    return new;
  end if;

  -- Newer writers may already supply the Person resource directly.
  if exists (
    select 1 from lifemate.women_calendar_profiles
    where owner_person_id=new.resource_id
  ) then
    return new;
  end if;

  v_person_id := core.self_person_id_for_legacy_app_user(new.resource_id);
  if v_person_id is null then
    raise exception 'women_calendar_profile_audit_person_mapping_missing';
  end if;
  new.resource_id := v_person_id;
  return new;
end
$$;

revoke execute on function core.canonicalize_women_profile_audit_resource()
  from public;

drop trigger if exists trg_canonicalize_women_profile_audit_resource
  on lifemate.audit_logs;
create trigger trg_canonicalize_women_profile_audit_resource
before insert on lifemate.audit_logs
for each row execute function core.canonicalize_women_profile_audit_resource();
