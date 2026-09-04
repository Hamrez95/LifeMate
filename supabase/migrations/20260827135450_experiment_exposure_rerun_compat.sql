-- Compatibility guard for the historical experimentation foundation migration.
-- The immediately following foundation migration creates the 7-argument exposure
-- recorder and comments it without a signature. A later hardening migration replaces
-- that contract with an 8-argument overload. On a full canonical rerun both overloads
-- are therefore present before the historical COMMENT statement, making it ambiguous.
-- Fresh databases reach this guard before either function exists, so it is a no-op.
-- On rerun, remove only the later hardened overload; 20260827135500 can then rerun,
-- and 20260827135600 immediately restores the hardened 8-argument contract.

drop function if exists analytics.record_experiment_exposure(
  varchar,bigint,varchar,bigint,varchar,varchar,timestamptz,jsonb
);
