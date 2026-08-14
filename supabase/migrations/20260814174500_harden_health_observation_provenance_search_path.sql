-- Security Advisor hardening: the trigger function executes on every health
-- observation insert and must not inherit a caller-controlled search_path.
-- Keep the canonical body from the earlier migration; only pin name resolution.

alter function lifemate.populate_health_observation_provenance()
  set search_path = pg_catalog, lifemate, ecosystem, pg_temp;

-- The function is trigger-only. Direct client/runtime EXECUTE is unnecessary;
-- the already-created trigger continues to invoke it as part of INSERT.
revoke execute on function lifemate.populate_health_observation_provenance()
  from public;
