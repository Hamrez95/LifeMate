begin;

-- Women Calendar's product store reads and mutates Circle planning data through
-- the restricted LifeMate Edge backend role. The Circle foundation intentionally
-- revoked browser/provider roles, but omitted the backend runtime grant/policy.
-- Keep clients denied; this policy only restores the reviewed backend boundary.
do $$
declare
  v_table text;
begin
  if to_regrole('lifemate_edge_runtime') is not null then
    grant usage on schema network to lifemate_edge_runtime;

    foreach v_table in array array[
      'circles',
      'circle_members',
      'circle_invitations',
      'circle_member_sharing_policies',
      'circle_planning_events',
      'circle_audit_events'
    ] loop
      execute format(
        'grant select,insert,update,delete on table network.%I to lifemate_edge_runtime',
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

-- Browser/provider roles remain explicitly outside this backend storage surface.
do $$
declare
  v_role text;
  v_table text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if to_regrole(v_role) is not null then
      foreach v_table in array array[
        'circles',
        'circle_members',
        'circle_invitations',
        'circle_member_sharing_policies',
        'circle_planning_events',
        'circle_audit_events'
      ] loop
        execute format('revoke all on table network.%I from %I', v_table, v_role);
      end loop;
    end if;
  end loop;
end $$;

commit;
