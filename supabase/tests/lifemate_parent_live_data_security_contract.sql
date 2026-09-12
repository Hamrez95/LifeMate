\set ON_ERROR_STOP on

-- #1065 — Parent-app live-data security regression contract.
--
-- LifeMate mobile clients authenticate with Supabase Auth but healthcare/profile,
-- enrollment, entitlement, consent and companion/relationship data must remain
-- behind the reviewed LifeMate API. These assertions intentionally fail the
-- disposable PostgreSQL contract gate if a later migration opens direct client
-- table access, weakens RLS, or exposes a SECURITY DEFINER RPC to public mobile
-- roles.

DO $$
DECLARE
  v_relation regclass;
  v_schema text;
  v_table text;
  v_rls boolean;
  v_force_rls boolean;
BEGIN
  FOR v_schema, v_table IN
    SELECT * FROM (VALUES
      ('identity', 'accounts'),
      ('core', 'persons'),
      ('core', 'person_profiles'),
      ('core', 'account_person_links'),
      ('ecosystem', 'applications'),
      ('ecosystem', 'app_enrollments'),
      ('commerce', 'entitlements'),
      ('commerce', 'subscriptions'),
      ('security', 'access_grants'),
      ('security', 'access_grant_scopes'),
      ('network', 'person_relationships'),
      ('lifemate', 'user_profiles'),
      ('lifemate', 'privacy_consents'),
      ('lifemate', 'care_relationships')
    ) AS required_relation(schema_name, table_name)
  LOOP
    v_relation := to_regclass(format('%I.%I', v_schema, v_table));
    IF v_relation IS NULL THEN
      RAISE EXCEPTION 'required protected relation %.% is missing', v_schema, v_table;
    END IF;

    SELECT c.relrowsecurity, c.relforcerowsecurity
      INTO v_rls, v_force_rls
      FROM pg_class c
     WHERE c.oid = v_relation;

    IF NOT v_rls OR NOT v_force_rls THEN
      RAISE EXCEPTION 'protected relation %.% must keep RLS + FORCE RLS enabled', v_schema, v_table;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      IF has_table_privilege('anon', v_relation, 'SELECT')
         OR has_table_privilege('anon', v_relation, 'INSERT')
         OR has_table_privilege('anon', v_relation, 'UPDATE')
         OR has_table_privilege('anon', v_relation, 'DELETE') THEN
        RAISE EXCEPTION 'anon must not have direct mobile privileges on %.%', v_schema, v_table;
      END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
      IF has_table_privilege('authenticated', v_relation, 'SELECT')
         OR has_table_privilege('authenticated', v_relation, 'INSERT')
         OR has_table_privilege('authenticated', v_relation, 'UPDATE')
         OR has_table_privilege('authenticated', v_relation, 'DELETE') THEN
        RAISE EXCEPTION 'authenticated must not have direct mobile privileges on %.%', v_schema, v_table;
      END IF;
    END IF;
  END LOOP;
END
$$;

DO $$
DECLARE
  v_function record;
BEGIN
  FOR v_function IN
    SELECT p.oid,
           n.nspname AS schema_name,
           p.proname AS function_name,
           p.proconfig,
           p.proacl,
           p.proowner
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.prosecdef
       AND n.nspname IN (
         'identity',
         'core',
         'ecosystem',
         'commerce',
         'security',
         'network',
         'lifemate'
       )
  LOOP
    IF NOT EXISTS (
      SELECT 1
        FROM unnest(coalesce(v_function.proconfig, ARRAY[]::text[])) setting
       WHERE setting LIKE 'search_path=%'
    ) THEN
      RAISE EXCEPTION 'SECURITY DEFINER %.% must pin search_path',
        v_function.schema_name,
        v_function.function_name;
    END IF;

    IF EXISTS (
      SELECT 1
        FROM aclexplode(coalesce(v_function.proacl, acldefault('f', v_function.proowner))) acl
       WHERE acl.grantee = 0
         AND acl.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'SECURITY DEFINER %.% must revoke EXECUTE from PUBLIC',
        v_function.schema_name,
        v_function.function_name;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
       AND has_function_privilege('anon', v_function.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon must not execute SECURITY DEFINER %.%',
        v_function.schema_name,
        v_function.function_name;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated')
       AND has_function_privilege('authenticated', v_function.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'authenticated must not execute SECURITY DEFINER %.%',
        v_function.schema_name,
        v_function.function_name;
    END IF;
  END LOOP;
END
$$;

DO $$
DECLARE
  v_function regprocedure;
BEGIN
  -- These bridges cross the legacy AppUser -> canonical Account/Person boundary.
  -- They are internal Edge-runtime capabilities, never mobile RPCs.
  FOR v_function IN
    SELECT unnest(ARRAY[
      to_regprocedure('identity.account_id_for_legacy_app_user(uuid)'),
      to_regprocedure('core.self_person_id_for_legacy_app_user(uuid)'),
      to_regprocedure('commerce.mobile_subscription_snapshot(uuid)')
    ]::regprocedure[])
  LOOP
    IF v_function IS NULL THEN
      RAISE EXCEPTION 'required internal identity/entitlement bridge is missing';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lifemate_edge_runtime')
       AND NOT has_function_privilege('lifemate_edge_runtime', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'lifemate_edge_runtime lost required internal bridge EXECUTE: %', v_function;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')
       AND has_function_privilege('anon', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon unexpectedly executes internal bridge: %', v_function;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated')
       AND has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'authenticated unexpectedly executes internal bridge: %', v_function;
    END IF;
  END LOOP;
END
$$;
