-- Restore the least-privilege Edge runtime boundary for the canonical
-- relationship-scoped Women Health companion privacy store.
--
-- This table was introduced after the original runtime-role grants, so the
-- hosted Edge runtime did not inherit the SELECT/INSERT/UPDATE privileges
-- required by the existing owner privacy mutation and caregiver read paths.
-- Browser roles remain governed by the table's existing RLS/grant contract.
-- DELETE remains unavailable: relationship deletion owns cleanup through the
-- existing foreign-key cascade.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'lifemate_edge_runtime') then
    grant select, insert, update
      on table lifemate.women_companion_privacy_scopes
      to lifemate_edge_runtime;

    revoke delete, truncate, references, trigger
      on table lifemate.women_companion_privacy_scopes
      from lifemate_edge_runtime;
  end if;
end $$;
