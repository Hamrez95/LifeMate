-- Reconcile the canonical relationship-scoped Women Health companion privacy
-- store when production skipped the historical #109 migration, then restore
-- the least-privilege Edge runtime boundary required by the existing API.
--
-- All sensitive scopes default off. No legacy relationship flag or broad
-- consent is copied into this table, so reconciliation cannot grant new health
-- access. Browser roles remain revoked. DELETE stays unavailable to the Edge
-- runtime; relationship deletion owns cleanup through ON DELETE CASCADE.

create table if not exists lifemate.women_companion_privacy_scopes (
  relationship_id uuid primary key
    references lifemate.care_relationships(id) on delete cascade,
  view_period_timing boolean not null default false,
  view_phase_summary boolean not null default false,
  view_shared_wellbeing boolean not null default false,
  receive_mood_support_notifications boolean not null default false,
  receive_phase_notifications boolean not null default false,
  view_fertility_estimate boolean not null default false,
  receive_fertility_notifications boolean not null default false,
  view_calendar_detail boolean not null default false,
  version integer not null default 1,
  updated_by_user_id uuid references lifemate.app_users(id) on delete set null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_women_companion_privacy_scopes_version check (version > 0)
);

create index if not exists ix_women_companion_privacy_scopes_relationship
  on lifemate.women_companion_privacy_scopes(relationship_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all privileges on lifemate.women_companion_privacy_scopes from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all privileges on lifemate.women_companion_privacy_scopes from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'lifemate_edge_runtime') then
    grant select, insert, update
      on table lifemate.women_companion_privacy_scopes
      to lifemate_edge_runtime;
    revoke delete, truncate, references, trigger
      on table lifemate.women_companion_privacy_scopes
      from lifemate_edge_runtime;
  end if;
end $$;

comment on table lifemate.women_companion_privacy_scopes is
  'Owner-controlled, relationship-bound companion scopes. All sensitive scopes default off and are never inferred from relationship type or legacy broad consent.';
