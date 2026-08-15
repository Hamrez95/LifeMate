-- Provider-neutral PostgreSQL recovery role used by workstation pg_dump.
--
-- Complete pg_dump archives require the effective dump role to bypass RLS;
-- otherwise PostgreSQL intentionally refuses to dump rows hidden by policies.
-- This role is therefore NOLOGIN + read-only + BYPASSRLS. A separately
-- provisioned LOGIN may be granted membership and pg_dump must use
-- --role=lifemate_backup_reader. Never place that LOGIN password in Git.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lifemate_backup_reader') THEN
    CREATE ROLE lifemate_backup_reader
      NOLOGIN
      NOSUPERUSER
      INHERIT
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION
      BYPASSRLS;
  ELSE
    ALTER ROLE lifemate_backup_reader
      NOLOGIN
      NOSUPERUSER
      INHERIT
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION
      BYPASSRLS;
  END IF;
END
$$;

DO $$
DECLARE
  schema_name text;
BEGIN
  FOREACH schema_name IN ARRAY ARRAY[
    'analytics','care','commerce','consent','core','ecosystem',
    'identity','integration','lifemate','public','security'
  ] LOOP
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = schema_name) THEN
      EXECUTE format('REVOKE CREATE ON SCHEMA %I FROM lifemate_backup_reader', schema_name);
      EXECUTE format('GRANT USAGE ON SCHEMA %I TO lifemate_backup_reader', schema_name);
      EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO lifemate_backup_reader', schema_name);
      EXECUTE format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA %I TO lifemate_backup_reader', schema_name);
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO lifemate_backup_reader',
        schema_name
      );
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON SEQUENCES TO lifemate_backup_reader',
        schema_name
      );
    END IF;
  END LOOP;
END
$$;

-- Defense in depth: this operational role must never receive database/schema
-- mutation privileges through this migration.
REVOKE CREATE ON SCHEMA public FROM lifemate_backup_reader;
