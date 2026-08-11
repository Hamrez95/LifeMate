-- Harden LifeMate Edge database identities without changing the API authorization model.
--
-- The mobile clients never receive these credentials. Supabase still injects the
-- platform SUPABASE_DB_URL into Edge Functions; the functions use that connection
-- only during cold start to read the dedicated runtime password from Vault, then
-- all application SQL runs through the restricted login roles below.
--
-- RLS is intentionally role-scoped here. The Edge API remains the healthcare
-- authorization boundary and continues to enforce person/relationship/consent
-- predicates in every query. RLS prevents ordinary client/platform roles from
-- gaining access and ensures the restricted runtime cannot bypass policies.

create extension if not exists pgcrypto;

do $$
declare
  v_api_password text;
  v_worker_password text;
  v_secret_id uuid;
begin
  if not exists (select 1 from pg_roles where rolname = 'lifemate_edge_runtime') then
    v_api_password := encode(gen_random_bytes(32), 'hex');
    execute format(
      'create role lifemate_edge_runtime with login password %L nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 20',
      v_api_password
    );
  else
    alter role lifemate_edge_runtime with login nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 20;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'lifemate_worker_runtime') then
    v_worker_password := encode(gen_random_bytes(32), 'hex');
    execute format(
      'create role lifemate_worker_runtime with login password %L nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 5',
      v_worker_password
    );
  else
    alter role lifemate_worker_runtime with login nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 5;
  end if;

  -- Vault exists in Supabase but not in portable PostgreSQL CI. Keep every Vault
  -- reference dynamic so a fresh ordinary PostgreSQL database can replay this
  -- canonical migration without the Supabase extension installed.
  if to_regnamespace('vault') is not null then
    execute 'select id from vault.secrets where name = ''lifemate_edge_runtime_password'' limit 1'
      into v_secret_id;
    if v_secret_id is null then
      if v_api_password is null then
        v_api_password := encode(gen_random_bytes(32), 'hex');
        execute format('alter role lifemate_edge_runtime password %L', v_api_password);
      end if;
      execute format(
        'select vault.create_secret(%L,%L,%L)',
        v_api_password,
        'lifemate_edge_runtime_password',
        'Password for the least-privilege LifeMate healthcare Edge API database role'
      );
    end if;

    v_secret_id := null;
    execute 'select id from vault.secrets where name = ''lifemate_worker_runtime_password'' limit 1'
      into v_secret_id;
    if v_secret_id is null then
      if v_worker_password is null then
        v_worker_password := encode(gen_random_bytes(32), 'hex');
        execute format('alter role lifemate_worker_runtime password %L', v_worker_password);
      end if;
      execute format(
        'select vault.create_secret(%L,%L,%L)',
        v_worker_password,
        'lifemate_worker_runtime_password',
        'Password for the least-privilege LifeMate outbox worker database role'
      );
    end if;
  end if;
end
$$;

do $$
begin
  execute format('revoke all on database %I from lifemate_edge_runtime', current_database());
  execute format('revoke all on database %I from lifemate_worker_runtime', current_database());
  execute format(
    'grant connect on database %I to lifemate_edge_runtime, lifemate_worker_runtime',
    current_database()
  );
end
$$;

-- Start from an explicit deny baseline.
do $$
declare
  v_schema text;
begin
  foreach v_schema in array array[
    'lifemate','identity','core','ecosystem','network','security','consent',
    'commerce','integration','analytics','care'
  ] loop
    if to_regnamespace(v_schema) is not null then
      execute format('revoke all on schema %I from lifemate_edge_runtime, lifemate_worker_runtime', v_schema);
      execute format('revoke all on all tables in schema %I from lifemate_edge_runtime, lifemate_worker_runtime', v_schema);
      execute format('revoke all on all sequences in schema %I from lifemate_edge_runtime, lifemate_worker_runtime', v_schema);
      execute format('revoke all on all functions in schema %I from lifemate_edge_runtime, lifemate_worker_runtime', v_schema);
    end if;
  end loop;
end
$$;

-- Healthcare API role. DDL/ownership/role administration are never granted.
grant usage on schema lifemate, identity, core, ecosystem, network, security, consent, commerce, integration, analytics, care to lifemate_edge_runtime;
grant select, insert, update, delete on all tables in schema lifemate, identity, core, ecosystem, network, security, consent, integration to lifemate_edge_runtime;
grant select on all tables in schema commerce, analytics, care to lifemate_edge_runtime;
grant usage, select on all sequences in schema lifemate, identity, core, ecosystem, network, security, consent, commerce, integration, analytics, care to lifemate_edge_runtime;
grant execute on function security.can_access_person_feature(uuid, uuid, character varying, character varying, character varying, timestamp with time zone) to lifemate_edge_runtime;

-- Worker role: only outbox processing, adherence projection and account-deletion
-- finalization surfaces used by lifemate-worker.
grant usage on schema integration, care, identity, core, ecosystem, lifemate to lifemate_worker_runtime;
grant select, insert, update on integration.outbox_messages to lifemate_worker_runtime;
grant select, insert, update on care.daily_adherence_summary to lifemate_worker_runtime;
grant select on lifemate.app_users, lifemate.dose_occurrences to lifemate_worker_runtime;
grant update on lifemate.user_profiles to lifemate_worker_runtime;
grant select, update on identity.account_deletion_requests to lifemate_worker_runtime;
grant delete on identity.contact_points, identity.external_identities to lifemate_worker_runtime;
grant update on identity.accounts to lifemate_worker_runtime;
grant select, update on core.account_person_links to lifemate_worker_runtime;
grant update on core.person_profiles, core.persons to lifemate_worker_runtime;
grant update on ecosystem.app_enrollments to lifemate_worker_runtime;
grant execute on function integration.claim_outbox_messages_for_events(character varying, integer, character varying[]) to lifemate_worker_runtime;
grant execute on function integration.complete_outbox_message(uuid, character varying) to lifemate_worker_runtime;
grant execute on function integration.fail_outbox_message(uuid, character varying, character varying, integer) to lifemate_worker_runtime;
grant execute on function care.rebuild_daily_adherence_summary(uuid, date) to lifemate_worker_runtime;
grant execute on function identity.finalize_account_deletion(uuid) to lifemate_worker_runtime;

-- Enable/force RLS on application-owned tables. Runtime policies are deliberately
-- bound to the two restricted roles; table grants above still constrain commands.
do $$
declare
  r record;
begin
  for r in
    select n.nspname as schema_name, c.relname as table_name
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind = 'r'
       and n.nspname = any(array[
         'lifemate','identity','core','ecosystem','network','security','consent',
         'commerce','integration','analytics','care'
       ])
       and not (n.nspname = 'lifemate' and c.relname = '__ef_migrations_history')
  loop
    execute format('alter table %I.%I enable row level security', r.schema_name, r.table_name);
    execute format('alter table %I.%I force row level security', r.schema_name, r.table_name);
    execute format('drop policy if exists lifemate_edge_runtime_access on %I.%I', r.schema_name, r.table_name);
    execute format(
      'create policy lifemate_edge_runtime_access on %I.%I for all to lifemate_edge_runtime using (true) with check (true)',
      r.schema_name, r.table_name
    );
  end loop;
end
$$;

-- The worker receives an RLS path only on tables it actually touches.
do $$
declare
  v_target text;
  v_schema text;
  v_table text;
begin
  foreach v_target in array array[
    'integration.outbox_messages',
    'care.daily_adherence_summary',
    'lifemate.app_users',
    'lifemate.dose_occurrences',
    'lifemate.user_profiles',
    'identity.account_deletion_requests',
    'identity.contact_points',
    'identity.external_identities',
    'identity.accounts',
    'core.account_person_links',
    'core.person_profiles',
    'core.persons',
    'ecosystem.app_enrollments'
  ] loop
    v_schema := split_part(v_target, '.', 1);
    v_table := split_part(v_target, '.', 2);
    if to_regclass(v_target) is not null then
      execute format('drop policy if exists lifemate_worker_runtime_access on %I.%I', v_schema, v_table);
      execute format(
        'create policy lifemate_worker_runtime_access on %I.%I for all to lifemate_worker_runtime using (true) with check (true)',
        v_schema, v_table
      );
    end if;
  end loop;
end
$$;

-- Preserve direct-client denial explicitly even if platform defaults change.
do $$
declare
  v_schema text;
begin
  foreach v_schema in array array[
    'lifemate','identity','core','ecosystem','network','security','consent',
    'commerce','integration','analytics','care'
  ] loop
    if to_regnamespace(v_schema) is not null then
      execute format('revoke all on schema %I from anon, authenticated', v_schema);
      execute format('revoke all on all tables in schema %I from anon, authenticated', v_schema);
      execute format('revoke all on all sequences in schema %I from anon, authenticated', v_schema);
    end if;
  end loop;
end
$$;
