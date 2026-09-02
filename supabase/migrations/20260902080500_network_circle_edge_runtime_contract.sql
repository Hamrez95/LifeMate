begin;

-- Circle authorization remains in the authenticated API store using canonical
-- Person ownership/membership checks. The restricted Edge runtime receives
-- only the table privileges used by that store; browser roles remain denied.
do $$
declare v_table text;
begin
  if to_regrole('lifemate_edge_runtime') is not null then
    foreach v_table in array array[
      'circles',
      'circle_members',
      'circle_invitations',
      'circle_member_sharing_policies',
      'circle_planning_events',
      'circle_audit_events'
    ] loop
      execute format(
        'grant select, insert, update on table network.%I to lifemate_edge_runtime',
        v_table
      );
      execute format(
        'drop policy if exists lifemate_edge_runtime_access on network.%I',
        v_table
      );
      execute format(
        'create policy lifemate_edge_runtime_access on network.%I for all to lifemate_edge_runtime using (true) with check (true)',
        v_table
      );
    end loop;
  end if;
end $$;

comment on policy lifemate_edge_runtime_access on network.circles is
  'Restricted Edge runtime access only; authenticated API code still enforces canonical Person ownership/membership before Circle operations.';

commit;
