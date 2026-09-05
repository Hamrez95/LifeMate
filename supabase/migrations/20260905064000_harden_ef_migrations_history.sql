-- Keep Entity Framework migration metadata outside application/runtime access.
-- EF/Supabase migrations execute under the database owner/admin path; request-time
-- Edge, worker and direct-client roles do not need this table.

do $$
declare
  v_role text;
begin
  if to_regclass('lifemate.__ef_migrations_history') is null then
    return;
  end if;

  -- Direct/browser and request-time runtime principals must not inspect or mutate
  -- deployment metadata. PUBLIC is revoked explicitly so future role membership
  -- cannot accidentally reintroduce access.
  revoke all on table lifemate.__ef_migrations_history from public;

  foreach v_role in array array[
    'anon',
    'authenticated',
    'lifemate_edge_runtime',
    'lifemate_worker_runtime'
  ] loop
    if exists (select 1 from pg_roles where rolname = v_role) then
      execute format(
        'revoke all on table lifemate.__ef_migrations_history from %I',
        v_role
      );
    end if;
  end loop;

  -- Migration/admin ownership remains the only access path. RLS removes the
  -- Security Advisor finding without adding a permissive application policy.
  alter table lifemate.__ef_migrations_history enable row level security;
end
$$;
