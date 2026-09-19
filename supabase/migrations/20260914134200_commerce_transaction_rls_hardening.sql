begin;

-- These canonical payment/order tables are backend/admin storage, not a direct
-- browser/mobile Data API surface. Client roles stay fully denied; the
-- restricted Admin runtime keeps read-only access and privileged mutations
-- continue through reviewed SECURITY DEFINER/backend contracts.
--
-- Some CI suites deliberately replay only a partial schema. Keep this
-- migration a no-op for Commerce relations that are not part of that fixture;
-- the dedicated Commerce security workflow replays the canonical full schema
-- and fails if any expected table/role/policy is missing.
do $$
declare
  v_table text;
  v_qualified text;
  v_role text;
  v_policy_comment text;
begin
  foreach v_table in array array[
    'orders',
    'transactions',
    'transaction_events',
    'refund_requests'
  ] loop
    v_qualified := format('commerce.%I', v_table);

    if to_regclass(v_qualified) is null then
      continue;
    end if;

    execute format('alter table %s enable row level security', v_qualified);
    execute format('alter table %s force row level security', v_qualified);
    execute format('revoke all on %s from public', v_qualified);

    foreach v_role in array array['anon','authenticated','service_role'] loop
      if to_regrole(v_role) is not null then
        execute format('revoke all on %s from %I', v_qualified, v_role);
      end if;
    end loop;

    -- Re-state the application-runtime contract so future privilege drift
    -- cannot silently turn these tables into mutable Admin runtime surfaces.
    if to_regrole('lifemate_admin_runtime') is not null then
      execute format('revoke all on %s from lifemate_admin_runtime', v_qualified);
      execute format('grant select on %s to lifemate_admin_runtime', v_qualified);
      execute format(
        'drop policy if exists lifemate_admin_runtime_select on %s',
        v_qualified
      );
      execute format(
        'create policy lifemate_admin_runtime_select on %s for select to lifemate_admin_runtime using (true)',
        v_qualified
      );

      v_policy_comment := case v_table
        when 'orders' then
          'Restricted Admin backend may read canonical orders. Consumer/client roles have no table access; authorization remains at reviewed Admin API/RBAC boundaries.'
        when 'transactions' then
          'Restricted Admin backend may read normalized transactions. Consumer/client roles have no table access; authorization remains at reviewed Admin API/RBAC boundaries.'
        when 'transaction_events' then
          'Restricted Admin backend may read privacy-minimized transaction events. Consumer/client roles have no table access.'
        when 'refund_requests' then
          'Restricted Admin backend may read refund workflow state. Mutation remains behind reviewed privileged functions and provider workflows.'
      end;

      execute format(
        'comment on policy lifemate_admin_runtime_select on %s is %L',
        v_qualified,
        v_policy_comment
      );
    end if;

    -- The portable backup reader is deliberately NOLOGIN + read-only +
    -- BYPASSRLS so disaster-recovery extraction can see every tenant row
    -- without granting application runtimes the same power.
    if to_regrole('lifemate_backup_reader') is not null then
      execute format('revoke all on %s from lifemate_backup_reader', v_qualified);
      execute format('grant select on %s to lifemate_backup_reader', v_qualified);
    end if;
  end loop;
end
$$;

commit;
