-- #350 / #217: allow the least-privilege Admin runtime to resolve an Account
-- through the same opaque external identity-token boundary used by Core.
-- This is additive only: legacy raw external identities remain available until
-- protected token-only activation and raw-link retirement are separately proven.

alter table identity.external_identity_tokens enable row level security;
alter table identity.external_identity_tokens force row level security;

do $$
begin
  if exists (select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant select on identity.external_identity_tokens to lifemate_admin_runtime;

    drop policy if exists lifemate_admin_runtime_select
      on identity.external_identity_tokens;
    create policy lifemate_admin_runtime_select
      on identity.external_identity_tokens
      for select to lifemate_admin_runtime
      using (true);
  end if;
end
$$;

-- Direct Supabase client roles remain denied. The Admin API must be the only
-- browser-reachable path and still enforces AAL2 + Admin membership/RBAC.
do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format(
        'revoke all on identity.external_identity_tokens from %I',
        v_role
      );
    end if;
  end loop;
end
$$;

revoke all on identity.external_identity_tokens from public;
