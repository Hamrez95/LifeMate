begin;

-- Women Calendar Cycle Insight preferences/history are backend-owned storage.
-- The API product store executes through the restricted LifeMate Edge runtime
-- role; browser/provider roles remain explicitly denied.
do $$
declare
  v_table text;
begin
  if to_regrole('lifemate_edge_runtime') is not null then
    grant usage on schema lifemate to lifemate_edge_runtime;

    foreach v_table in array array[
      'women_cycle_insight_preferences',
      'women_cycle_insight_history'
    ] loop
      execute format(
        'grant select,insert,update,delete on table lifemate.%I to lifemate_edge_runtime',
        v_table
      );
      execute format(
        'drop policy if exists lifemate_edge_runtime_access on lifemate.%I',
        v_table
      );
      execute format(
        'create policy lifemate_edge_runtime_access on lifemate.%I for all to lifemate_edge_runtime using (true) with check (true)',
        v_table
      );
    end loop;
  end if;
end $$;

do $$
declare
  v_role text;
  v_table text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if to_regrole(v_role) is not null then
      foreach v_table in array array[
        'women_cycle_insight_preferences',
        'women_cycle_insight_history'
      ] loop
        execute format(
          'revoke all on table lifemate.%I from %I',
          v_table,
          v_role
        );
      end loop;
    end if;
  end loop;
end $$;

commit;
