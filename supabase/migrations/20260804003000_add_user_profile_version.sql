-- Adds optimistic concurrency to the stable database-backed user profile.
-- Existing rows begin at version 1; every successful edit increments the value.

alter table lifemate.user_profiles
  add column if not exists version integer not null default 1;

alter table lifemate.user_profiles
  drop constraint if exists user_profiles_version_positive;

alter table lifemate.user_profiles
  add constraint user_profiles_version_positive check (version > 0);

comment on column lifemate.user_profiles.version is
  'Optimistic concurrency token incremented after each accepted profile edit.';

-- Rollback plan (manual and reviewed; data-safe for pre-release environments):
-- alter table lifemate.user_profiles drop constraint if exists user_profiles_version_positive;
-- alter table lifemate.user_profiles drop column if exists version;
