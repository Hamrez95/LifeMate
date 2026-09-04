-- Compatibility guard for the historical 20260827023000 abuse-rules migration.
-- On a fresh database the target tables do not exist yet, so this is a no-op.
-- On a canonical migration rerun, remove the policies that the historical
-- migration recreates with plain CREATE POLICY statements.

do $$
begin
  if to_regclass('security.abuse_rules') is not null then
    execute 'drop policy if exists abuse_rules_admin_runtime on security.abuse_rules';
  end if;

  if to_regclass('security.abuse_rule_versions') is not null then
    execute 'drop policy if exists abuse_rule_versions_admin_runtime on security.abuse_rule_versions';
    execute 'drop policy if exists abuse_rule_versions_admin_insert on security.abuse_rule_versions';
  end if;

  if to_regclass('security.abuse_events') is not null then
    execute 'drop policy if exists abuse_events_admin_runtime on security.abuse_events';
    execute 'drop policy if exists abuse_events_edge_insert on security.abuse_events';
    execute 'drop policy if exists abuse_events_admin_insert on security.abuse_events';
  end if;

  if to_regclass('security.abuse_decisions') is not null then
    execute 'drop policy if exists abuse_decisions_admin_runtime on security.abuse_decisions';
    execute 'drop policy if exists abuse_decisions_edge_insert on security.abuse_decisions';
    execute 'drop policy if exists abuse_decisions_admin_insert on security.abuse_decisions';
  end if;
end
$$;
