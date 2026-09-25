begin;

-- Only authenticated caregiver calendar routes use this privacy-safe delivery
-- history. Those handlers verify the active relationship and exact companion
-- privacy scopes before filtering by relationship and participant Person IDs.
grant select, insert
  on lifemate.women_companion_guidance_history
  to lifemate_edge_runtime;

drop policy if exists lifemate_edge_runtime_access
  on lifemate.women_companion_guidance_history;
create policy lifemate_edge_runtime_access
  on lifemate.women_companion_guidance_history
  for all to lifemate_edge_runtime
  using (true)
  with check (true);

commit;
