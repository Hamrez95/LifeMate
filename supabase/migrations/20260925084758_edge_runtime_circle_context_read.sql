begin;

-- The API performs Person/relationship authorization before these reads.
-- Keep the grants read-only and private to the trusted Edge runtime; Circle
-- membership is context only and never grants access to health records.
grant usage on schema network to lifemate_edge_runtime;
grant select on network.circles, network.circle_members
  to lifemate_edge_runtime;

drop policy if exists lifemate_edge_runtime_read_context
  on network.circles;
create policy lifemate_edge_runtime_read_context
  on network.circles
  for select to lifemate_edge_runtime
  using (true);

drop policy if exists lifemate_edge_runtime_read_context
  on network.circle_members;
create policy lifemate_edge_runtime_read_context
  on network.circle_members
  for select to lifemate_edge_runtime
  using (true);

commit;
