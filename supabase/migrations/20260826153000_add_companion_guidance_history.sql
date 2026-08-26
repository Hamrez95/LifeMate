-- #105: privacy-safe, relationship/person-scoped history for Companion Care
-- cooldown and deduplication. No health payload or generated copy is stored.
create table if not exists lifemate.women_companion_guidance_history (
  id uuid primary key,
  relationship_id uuid not null
    references lifemate.care_relationships(id) on delete cascade,
  patient_person_id uuid not null
    references core.persons(id) on delete cascade,
  caregiver_user_id uuid not null
    references lifemate.app_users(id) on delete cascade,
  guidance_id character varying(80) not null,
  content_version character varying(40) not null,
  category character varying(32) not null,
  shown_at_utc timestamptz not null,
  created_at_utc timestamptz not null default now(),
  constraint ck_women_companion_guidance_id_nonempty
    check (length(trim(guidance_id)) between 1 and 80),
  constraint ck_women_companion_guidance_version_nonempty
    check (length(trim(content_version)) between 1 and 40),
  constraint ck_women_companion_guidance_category
    check (category in ('general','phase','mood','energy'))
);

create index if not exists ix_women_companion_guidance_relationship_time
  on lifemate.women_companion_guidance_history(
    relationship_id, caregiver_user_id, shown_at_utc desc
  );

create index if not exists ix_women_companion_guidance_patient_time
  on lifemate.women_companion_guidance_history(
    patient_person_id, shown_at_utc desc
  );

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all privileges on lifemate.women_companion_guidance_history from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all privileges on lifemate.women_companion_guidance_history from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    revoke all privileges on lifemate.women_companion_guidance_history from service_role;
  end if;
end $$;

comment on table lifemate.women_companion_guidance_history is
  'Privacy-safe Companion Care impression history. Stores identifiers/categories only; never health payload, private notes, symptoms, pain, or rendered guidance copy.';