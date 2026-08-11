-- SECURITY INVOKER account-deletion finalization filters these tables by account
-- or person id. PostgreSQL requires SELECT on predicate columns in addition to
-- UPDATE/DELETE, so grant read access only to the worker's existing deletion
-- surface instead of broad schema reads.
grant select on
  identity.contact_points,
  identity.external_identities,
  identity.accounts,
  core.person_profiles,
  core.persons,
  lifemate.user_profiles,
  ecosystem.app_enrollments
  to lifemate_worker_runtime;
