-- #105 Companion Care privacy-safe impression history.
-- Contains identifiers and content metadata only; never stores rendered copy,
-- private notes, symptoms, pain, fertility data, diagnosis, or raw health data.

create table if not exists lifemate.women_companion_guidance_history (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references lifemate.care_relationships(id) on delete cascade,
  patient_person_id uuid not null references core.persons(id) on delete cascade,
  caregiver_person_id uuid not null references core.persons(id) on delete cascade,
  guidance_id character varying(80) not null,
  content_version character varying(40) not null,
  category character varying(32) not null,
  shown_at_utc timestamptz not null default now(),
  created_at_utc timestamptz not null default now(),
  constraint ck_companion_guidance_id check (length(trim(guidance_id)) between 1 and 80),
  constraint ck_companion_guidance_version check (length(trim(content_version)) between 1 and 40),
  constraint ck_companion_guidance_category check (category in ('general','phase','mood','energy'))
);

create index if not exists ix_companion_guidance_relationship_time
  on lifemate.women_companion_guidance_history(
    relationship_id,
    caregiver_person_id,
    patient_person_id,
    shown_at_utc desc
  );

create index if not exists ix_companion_guidance_dedup
  on lifemate.women_companion_guidance_history(
    relationship_id,
    caregiver_person_id,
    patient_person_id,
    guidance_id,
    shown_at_utc desc
  );

alter table lifemate.women_companion_guidance_history enable row level security;
alter table lifemate.women_companion_guidance_history force row level security;
revoke all on table lifemate.women_companion_guidance_history from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname = v_role) then
      execute format(
        'revoke all on table lifemate.women_companion_guidance_history from %I',
        v_role
      );
    end if;
  end loop;
end $$;

comment on table lifemate.women_companion_guidance_history is
  'Privacy-safe relationship/person-scoped Companion Care impression history. No rendered copy or raw health data.';
comment on column lifemate.care_relationships.can_view_women_calendar is
  'Legacy presentation compatibility only. Never use as authorization; exact women_companion_privacy_scopes are authoritative.';
