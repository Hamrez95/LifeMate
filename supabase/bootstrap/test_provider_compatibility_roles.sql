-- TEST HARNESS ONLY.
--
-- Canonical LifeMate business migrations run on PostgreSQL providers where the
-- adapter may expose Supabase-compatible browser roles and the standard
-- pgcrypto extension through an `extensions` schema. Vanilla PostgreSQL does
-- not create those roles/schema aliases, so portability CI provisions inert
-- fixtures without creating provider-owned auth/storage/realtime schemas.
--
-- This file is intentionally safe both before and after the canonical baseline:
-- when pgcrypto already exists in `public`, it adds narrow forwarding aliases
-- for the Supabase `extensions.*` names exercised by integration tests.
--
-- Never apply this file as a production migration. Runtime/browser privileges
-- remain owned by the deployment/provider configuration and canonical RLS.

create schema if not exists extensions;

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

  if to_regprocedure('public.digest(text,text)') is not null
     and to_regprocedure('extensions.digest(text,text)') is null then
    execute $sql$
      create function extensions.digest(text, text)
      returns bytea
      language sql
      immutable strict parallel safe
      as 'select public.digest($1, $2)'
    $sql$;
  end if;

  if to_regprocedure('public.digest(bytea,text)') is not null
     and to_regprocedure('extensions.digest(bytea,text)') is null then
    execute $sql$
      create function extensions.digest(bytea, text)
      returns bytea
      language sql
      immutable strict parallel safe
      as 'select public.digest($1, $2)'
    $sql$;
  end if;

  if to_regprocedure('public.gen_random_bytes(integer)') is not null
     and to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    execute $sql$
      create function extensions.gen_random_bytes(integer)
      returns bytea
      language sql
      volatile strict parallel safe
      as 'select public.gen_random_bytes($1)'
    $sql$;
  end if;
end
$fixture$;
