-- #105: canonical Companion Care cooldown/dedup history and exact-scope compatibility.
-- Stores no rendered copy, raw health data, notes, symptoms, pain, fertility data or diagnosis.

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
  on lifemate.women_companion_guidance_history(relationship_id, caregiver_person_id, shown_at_utc desc);
create index if not exists ix_companion_guidance_patient_time
  on lifemate.women_companion_guidance_history(patient_person_id, shown_at_utc desc);

alter table lifemate.women_companion_guidance_history enable row level security;
alter table lifemate.women_companion_guidance_history force row level security;
revoke all on lifemate.women_companion_guidance_history from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on lifemate.women_companion_guidance_history from %I',v_role);
    end if;
  end loop;
end $$;

-- `can_view_women_calendar` is retained only as a backwards-compatible UI hint.
-- Exact #109 relationship scopes are the authority. Legacy writes can never
-- manufacture permission: the hint is recomputed from the exact scope row.
create or replace function lifemate.sync_relationship_women_calendar_hint()
returns trigger language plpgsql security definer
set search_path = lifemate, pg_temp
as $$
declare v_relationship_id uuid;
begin
  v_relationship_id := coalesce(new.relationship_id, old.relationship_id);
  update lifemate.care_relationships r
     set can_view_women_calendar = exists (
       select 1 from lifemate.women_companion_privacy_scopes s
       where s.relationship_id = v_relationship_id
         and (
           s.view_period_timing or s.view_phase_summary or s.view_shared_wellbeing or
           s.receive_mood_support_notifications or s.receive_phase_notifications or
           s.view_fertility_estimate or s.receive_fertility_notifications or
           s.view_calendar_detail
         )
     ), updated_at_utc = now()
   where r.id = v_relationship_id;
  return coalesce(new, old);
end $$;

drop trigger if exists trg_women_companion_scope_sync_hint on lifemate.women_companion_privacy_scopes;
create trigger trg_women_companion_scope_sync_hint
after insert or update or delete on lifemate.women_companion_privacy_scopes
for each row execute function lifemate.sync_relationship_women_calendar_hint();

create or replace function lifemate.enforce_relationship_women_calendar_hint()
returns trigger language plpgsql security definer
set search_path = lifemate, pg_temp
as $$
begin
  new.can_view_women_calendar := exists (
    select 1 from lifemate.women_companion_privacy_scopes s
    where s.relationship_id = new.id
      and (
        s.view_period_timing or s.view_phase_summary or s.view_shared_wellbeing or
        s.receive_mood_support_notifications or s.receive_phase_notifications or
        s.view_fertility_estimate or s.receive_fertility_notifications or
        s.view_calendar_detail
      )
  );
  return new;
end $$;

drop trigger if exists trg_relationship_women_calendar_hint_guard on lifemate.care_relationships;
create trigger trg_relationship_women_calendar_hint_guard
before update of can_view_women_calendar on lifemate.care_relationships
for each row execute function lifemate.enforce_relationship_women_calendar_hint();

comment on table lifemate.women_companion_guidance_history is
  'Privacy-safe relationship/person-scoped Companion Care impression history; never stores health payload or rendered guidance copy.';
comment on column lifemate.care_relationships.can_view_women_calendar is
  'Compatibility presentation hint derived from exact women_companion_privacy_scopes; never an authorization source.';
