-- Updating the legacy profile during deletion fires sync_legacy_user_profile(),
-- which performs INSERT ... ON CONFLICT UPDATE into core.person_profiles.
-- Grant only the missing insert privilege to the worker's existing profile
-- compatibility surface.
grant insert on core.person_profiles to lifemate_worker_runtime;
