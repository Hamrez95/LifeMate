-- The Women companion API reads and records privacy-safe guidance
-- impressions through the restricted Edge runtime. Keep browser/provider
-- roles denied; grant only operations used by the server route.

grant select,insert
  on lifemate.women_companion_guidance_history
  to lifemate_edge_runtime;

drop policy if exists lifemate_edge_runtime_select
  on lifemate.women_companion_guidance_history;
create policy lifemate_edge_runtime_select
  on lifemate.women_companion_guidance_history
  for select
  to lifemate_edge_runtime
  using (true);

drop policy if exists lifemate_edge_runtime_insert
  on lifemate.women_companion_guidance_history;
create policy lifemate_edge_runtime_insert
  on lifemate.women_companion_guidance_history
  for insert
  to lifemate_edge_runtime
  with check (true);
