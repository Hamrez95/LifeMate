-- TEST HARNESS ONLY.
--
-- Canonical LifeMate business migrations run on PostgreSQL providers where the
-- adapter may expose Supabase-compatible browser roles and pgcrypto through an
-- `extensions` schema. Vanilla PostgreSQL provides neither shape by default, so
-- portability/integration CI provisions inert NOLOGIN role fixtures plus a tiny
-- pgcrypto forwarding shim. Provider-owned auth/storage/realtime schemas are
-- deliberately not created.
--
-- Never apply this file as a production migration. Runtime/browser privileges
-- and extension placement remain owned by the deployment/provider configuration
-- and canonical RLS.

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

-- Supabase exposes pgcrypto from `extensions`; vanilla PostgreSQL installs the
-- same standard extension into `public` in our legacy baseline. PL/pgSQL resolves
-- the explicit public calls at execution time, after the baseline has installed
-- pgcrypto, so the shim can safely be declared before schema replay begins.
create schema if not exists extensions;

create or replace function extensions.gen_random_bytes(integer)
returns bytea
language plpgsql
volatile
strict
as $fixture$
begin
  return public.gen_random_bytes($1);
end
$fixture$;

create or replace function extensions.digest(text, text)
returns bytea
language plpgsql
immutable
strict
as $fixture$
begin
  return public.digest($1, $2);
end
$fixture$;

create or replace function extensions.digest(bytea, text)
returns bytea
language plpgsql
immutable
strict
as $fixture$
begin
  return public.digest($1, $2);
end
$fixture$;