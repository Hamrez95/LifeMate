-- #407: close the remaining commerce RLS gap for Admin promotion metadata.
--
-- Promotions and discount codes are not browser-readable. The restricted Admin
-- runtime keeps SELECT access for the canonical Command Center read model;
-- mutation functions remain SECURITY DEFINER and preserve their existing
-- permission/AAL2/idempotency/audit checks.

alter table commerce.promotions enable row level security;
alter table commerce.discount_codes enable row level security;

revoke all on table commerce.promotions from public, anon, authenticated;
revoke all on table commerce.discount_codes from public, anon, authenticated;

drop policy if exists lifemate_admin_runtime_select on commerce.promotions;
create policy lifemate_admin_runtime_select
on commerce.promotions
for select
to lifemate_admin_runtime
using (true);

drop policy if exists lifemate_admin_runtime_select on commerce.discount_codes;
create policy lifemate_admin_runtime_select
on commerce.discount_codes
for select
to lifemate_admin_runtime
using (true);

grant select on table commerce.promotions to lifemate_admin_runtime;
grant select on table commerce.discount_codes to lifemate_admin_runtime;
