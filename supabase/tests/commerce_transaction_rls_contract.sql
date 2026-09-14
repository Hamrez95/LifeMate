\set ON_ERROR_STOP on
begin;

-- Structural defense-in-depth: every canonical order/payment/refund table must
-- use FORCE RLS, and only the restricted Admin runtime gets a row policy.
do $$
declare
  v_table text;
  v_role text;
begin
  foreach v_table in array array[
    'orders',
    'transactions',
    'transaction_events',
    'refund_requests'
  ] loop
    if not coalesce((
      select c.relrowsecurity and c.relforcerowsecurity
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'commerce'
        and c.relname = v_table
        and c.relkind = 'r'
    ), false) then
      raise exception 'commerce.% is not FORCE RLS protected', v_table;
    end if;

    if not exists (
      select 1
      from pg_policies
      where schemaname = 'commerce'
        and tablename = v_table
        and policyname = 'lifemate_admin_runtime_select'
        and cmd = 'SELECT'
        and 'lifemate_admin_runtime' = any(roles)
    ) then
      raise exception 'commerce.% lacks the reviewed Admin runtime SELECT policy', v_table;
    end if;

    if not has_table_privilege(
      'lifemate_admin_runtime', format('commerce.%I', v_table), 'SELECT'
    ) then
      raise exception 'Admin runtime lost required SELECT on commerce.%', v_table;
    end if;

    if has_table_privilege(
      'lifemate_admin_runtime', format('commerce.%I', v_table), 'INSERT'
    ) or has_table_privilege(
      'lifemate_admin_runtime', format('commerce.%I', v_table), 'UPDATE'
    ) or has_table_privilege(
      'lifemate_admin_runtime', format('commerce.%I', v_table), 'DELETE'
    ) or has_table_privilege(
      'lifemate_admin_runtime', format('commerce.%I', v_table), 'TRUNCATE'
    ) then
      raise exception 'Admin runtime can directly mutate commerce.%', v_table;
    end if;

    if not has_table_privilege(
      'lifemate_backup_reader', format('commerce.%I', v_table), 'SELECT'
    ) then
      raise exception 'Backup reader lost extraction SELECT on commerce.%', v_table;
    end if;

    if has_table_privilege(
      'lifemate_backup_reader', format('commerce.%I', v_table), 'INSERT'
    ) or has_table_privilege(
      'lifemate_backup_reader', format('commerce.%I', v_table), 'UPDATE'
    ) or has_table_privilege(
      'lifemate_backup_reader', format('commerce.%I', v_table), 'DELETE'
    ) or has_table_privilege(
      'lifemate_backup_reader', format('commerce.%I', v_table), 'TRUNCATE'
    ) then
      raise exception 'Backup reader can mutate commerce.%', v_table;
    end if;

    foreach v_role in array array['anon','authenticated','service_role'] loop
      if to_regrole(v_role) is not null and has_table_privilege(
        v_role, format('commerce.%I', v_table), 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'
      ) then
        raise exception '% retained direct privileges on commerce.%', v_role, v_table;
      end if;
    end loop;
  end loop;

  if (select rolbypassrls or rolsuper or rolcreatedb or rolcreaterole
      from pg_roles where rolname = 'lifemate_admin_runtime') then
    raise exception 'Admin runtime regained a privilege that can bypass the RLS contract';
  end if;

  if not (select not rolcanlogin and rolbypassrls
          from pg_roles where rolname = 'lifemate_backup_reader') then
    raise exception 'Backup reader no longer matches reviewed NOLOGIN/BYPASSRLS extraction contract';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'commerce'
      and c.relname = 'transaction_effective_state_v1'
      and c.relkind = 'v'
      and 'security_invoker=true' = any(coalesce(c.reloptions, array[]::text[]))
  ) then
    raise exception 'transaction_effective_state_v1 is not SECURITY INVOKER';
  end if;
end
$$;

-- Prove the real backend role can traverse RLS for each reviewed read surface.
set local role lifemate_admin_runtime;
select count(*) from commerce.orders;
select count(*) from commerce.transactions;
select count(*) from commerce.transaction_events;
select count(*) from commerce.refund_requests;
select count(*) from commerce.transaction_effective_state_v1;
reset role;

-- Prove direct consumer/service roles cannot traverse the storage boundary at
-- runtime. This is intentionally stronger than owner-only client RLS: these
-- financial tables are not a client Data API surface at all, so even an owner
-- must use the reviewed LifeMate API/backend contract.
do $$
declare
  v_role text;
  v_table text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if to_regrole(v_role) is null then
      continue;
    end if;

    foreach v_table in array array[
      'orders',
      'transactions',
      'transaction_events',
      'refund_requests'
    ] loop
      begin
        execute format('set local role %I', v_role);
        execute format('select count(*) from commerce.%I', v_table);
        execute 'reset role';
        raise exception '% unexpectedly read commerce.%', v_role, v_table;
      exception
        when insufficient_privilege then
          null;
      end;
    end loop;
  end loop;
end
$$;

-- Prove the Admin runtime cannot bypass narrow mutation functions by writing
-- storage directly. UPDATE and DELETE are executed for real; INSERT is checked
-- both structurally and with a real statement that must fail before row checks.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'orders',
    'transactions',
    'transaction_events',
    'refund_requests'
  ] loop
    begin
      execute 'set local role lifemate_admin_runtime';
      execute format('update commerce.%I set id = id where false', v_table);
      execute 'reset role';
      raise exception 'Admin runtime unexpectedly updated commerce.%', v_table;
    exception
      when insufficient_privilege then
        null;
    end;

    begin
      execute 'set local role lifemate_admin_runtime';
      execute format('delete from commerce.%I where false', v_table);
      execute 'reset role';
      raise exception 'Admin runtime unexpectedly deleted from commerce.%', v_table;
    exception
      when insufficient_privilege then
        null;
    end;

    begin
      execute 'set local role lifemate_admin_runtime';
      execute format('insert into commerce.%I default values', v_table);
      execute 'reset role';
      raise exception 'Admin runtime unexpectedly inserted into commerce.%', v_table;
    exception
      when insufficient_privilege then
        null;
    end;
  end loop;
end
$$;

-- The reviewed disaster-recovery extractor must still read through FORCE RLS,
-- but its ACL remains read-only.
set local role lifemate_backup_reader;
select count(*) from commerce.orders;
select count(*) from commerce.transactions;
select count(*) from commerce.transaction_events;
select count(*) from commerce.refund_requests;
reset role;

rollback;
