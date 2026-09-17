-- TEST HARNESS ONLY.
--
-- Canonical LifeMate business migrations run on PostgreSQL providers where the
-- adapter may expose Supabase-compatible browser roles. Vanilla PostgreSQL does
-- not create those roles, so portability CI provisions inert NOLOGIN fixtures
-- to compile and exercise grants/revokes without creating provider-owned schemas.
--
-- Never apply this file as a production migration. Runtime/browser privileges
-- remain owned by the deployment/provider configuration and canonical RLS.

do $fixture$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
end
$fixture$;
