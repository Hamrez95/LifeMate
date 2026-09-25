begin;

-- Preferences and delivery receipts are accessed through authenticated API
-- handlers that resolve the caller's canonical Person and filter every row by
-- owner_person_id. Keep direct client access revoked and grant the API only the
-- operations used by those handlers.
grant select, insert, update
  on lifemate.women_cycle_insight_preferences
  to lifemate_edge_runtime;
grant select, insert
  on lifemate.women_cycle_insight_history
  to lifemate_edge_runtime;

drop policy if exists lifemate_edge_runtime_access
  on lifemate.women_cycle_insight_preferences;
create policy lifemate_edge_runtime_access
  on lifemate.women_cycle_insight_preferences
  for all to lifemate_edge_runtime
  using (true)
  with check (true);

drop policy if exists lifemate_edge_runtime_access
  on lifemate.women_cycle_insight_history;
create policy lifemate_edge_runtime_access
  on lifemate.women_cycle_insight_history
  for all to lifemate_edge_runtime
  using (true)
  with check (true);

commit;
