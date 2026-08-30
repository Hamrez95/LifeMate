-- Keep Period Trial server-authoritative while permitting only the reviewed Edge runtime.
alter table commerce.product_trials enable row level security;
drop policy if exists lifemate_edge_runtime_product_trials on commerce.product_trials;
create policy lifemate_edge_runtime_product_trials
on commerce.product_trials
for all
to lifemate_edge_runtime
using (true)
with check (true);
revoke all on commerce.product_trials from public, anon, authenticated;
grant select, insert on commerce.product_trials to lifemate_edge_runtime;
