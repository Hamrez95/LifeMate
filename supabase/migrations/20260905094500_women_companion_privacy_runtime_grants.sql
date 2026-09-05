-- Restore the least-privilege Edge runtime boundary for the canonical
-- relationship-scoped Women Health companion privacy store.
--
-- The table was introduced after the original runtime-role grant migration,
-- so hosted/prod runtimes did not inherit the SELECT/INSERT/UPDATE privileges
-- required by women_companion_privacy.ts and caregiver authorization reads.
-- Browser roles remain revoked by the table-creation migration. DELETE stays
-- unavailable: relationship deletion owns row removal through ON DELETE CASCADE.

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
