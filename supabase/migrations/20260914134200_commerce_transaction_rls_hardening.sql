begin;

-- These canonical payment/order tables are backend/admin storage, not a direct
-- browser/mobile Data API surface. Client roles stay fully denied; the
-- restricted Admin runtime keeps read-only access and privileged mutations
-- continue through reviewed SECURITY DEFINER/backend contracts.

alter table commerce.orders enable row level security;
alter table commerce.orders force row level security;
alter table commerce.transactions enable row level security;
alter table commerce.transactions force row level security;
alter table commerce.transaction_events enable row level security;
alter table commerce.transaction_events force row level security;
alter table commerce.refund_requests enable row level security;
alter table commerce.refund_requests force row level security;

revoke all on commerce.orders from public;
revoke all on commerce.transactions from public;
revoke all on commerce.transaction_events from public;
revoke all on commerce.refund_requests from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if to_regrole(v_role) is not null then
      execute format('revoke all on commerce.orders from %I', v_role);
      execute format('revoke all on commerce.transactions from %I', v_role);
      execute format('revoke all on commerce.transaction_events from %I', v_role);
      execute format('revoke all on commerce.refund_requests from %I', v_role);
    end if;
  end loop;
end
$$;

-- Re-state the application-runtime contract so future privilege drift cannot
-- silently turn these tables into mutable Admin runtime surfaces.
revoke all on commerce.orders from lifemate_admin_runtime;
revoke all on commerce.transactions from lifemate_admin_runtime;
revoke all on commerce.transaction_events from lifemate_admin_runtime;
revoke all on commerce.refund_requests from lifemate_admin_runtime;

grant select on commerce.orders to lifemate_admin_runtime;
grant select on commerce.transactions to lifemate_admin_runtime;
grant select on commerce.transaction_events to lifemate_admin_runtime;
grant select on commerce.refund_requests to lifemate_admin_runtime;

-- The portable backup reader is deliberately NOLOGIN + read-only + BYPASSRLS
-- so disaster-recovery extraction can see every tenant row without granting
-- application runtimes the same power.
revoke all on commerce.orders from lifemate_backup_reader;
revoke all on commerce.transactions from lifemate_backup_reader;
revoke all on commerce.transaction_events from lifemate_backup_reader;
revoke all on commerce.refund_requests from lifemate_backup_reader;

grant select on commerce.orders to lifemate_backup_reader;
grant select on commerce.transactions to lifemate_backup_reader;
grant select on commerce.transaction_events to lifemate_backup_reader;
grant select on commerce.refund_requests to lifemate_backup_reader;

drop policy if exists lifemate_admin_runtime_select on commerce.orders;
create policy lifemate_admin_runtime_select
on commerce.orders
for select
to lifemate_admin_runtime
using (true);

drop policy if exists lifemate_admin_runtime_select on commerce.transactions;
create policy lifemate_admin_runtime_select
on commerce.transactions
for select
to lifemate_admin_runtime
using (true);

drop policy if exists lifemate_admin_runtime_select on commerce.transaction_events;
create policy lifemate_admin_runtime_select
on commerce.transaction_events
for select
to lifemate_admin_runtime
using (true);

drop policy if exists lifemate_admin_runtime_select on commerce.refund_requests;
create policy lifemate_admin_runtime_select
on commerce.refund_requests
for select
to lifemate_admin_runtime
using (true);

comment on policy lifemate_admin_runtime_select on commerce.orders is
  'Restricted Admin backend may read canonical orders. Consumer/client roles have no table access; authorization remains at reviewed Admin API/RBAC boundaries.';
comment on policy lifemate_admin_runtime_select on commerce.transactions is
  'Restricted Admin backend may read normalized transactions. Consumer/client roles have no table access; authorization remains at reviewed Admin API/RBAC boundaries.';
comment on policy lifemate_admin_runtime_select on commerce.transaction_events is
  'Restricted Admin backend may read privacy-minimized transaction events. Consumer/client roles have no table access.';
comment on policy lifemate_admin_runtime_select on commerce.refund_requests is
  'Restricted Admin backend may read refund workflow state. Mutation remains behind reviewed privileged functions and provider workflows.';

commit;
