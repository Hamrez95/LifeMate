begin;

-- ADM-PERF-001: bounded query execution and indexes for the current high-volume
-- Command Center read paths. These are additive and do not expose new data.

create extension if not exists pg_trgm;

-- Prevent a pathological admin query from monopolizing a database connection. The
-- application still applies its own shorter request timeout; these role settings are a
-- database-side safety net and are intentionally scoped to the least-privilege Admin role.
alter role lifemate_admin_runtime set statement_timeout = '4s';
alter role lifemate_admin_runtime set lock_timeout = '1s';
alter role lifemate_admin_runtime set idle_in_transaction_session_timeout = '5s';

-- User Directory: supports status/order scans and contains-search on the approved
-- display-name field without indexing contact identifiers or health data.
create index if not exists ix_identity_accounts_status_created_admin
  on identity.accounts(status, created_at_utc desc, id);

create index if not exists ix_core_account_person_links_admin_self
  on core.account_person_links(account_id, person_id)
  where link_type='Self' and status='Active';

create index if not exists ix_core_person_profiles_display_name_trgm
  on core.person_profiles using gin (lower(coalesce(display_name, '')) gin_trgm_ops);

create index if not exists ix_ecosystem_app_enrollments_admin_account_activity
  on ecosystem.app_enrollments(account_id, last_active_at_utc desc, application_id)
  where status in ('Active','Suspended');

-- Support Queue: SLA/status/priority are the main operational filters. Trigram indexes
-- are limited to the already-redacted queue summary and display name projection source.
create index if not exists ix_support_tickets_admin_status_priority_activity
  on support.tickets(status, priority, last_activity_at_utc desc, id);

create index if not exists ix_support_tickets_admin_sla_due
  on support.tickets(status, next_due_at_utc, id)
  where next_due_at_utc is not null;

create index if not exists ix_support_tickets_queue_summary_trgm
  on support.tickets using gin (lower(coalesce(queue_summary_redacted, '')) gin_trgm_ops);

-- Commerce Transactions: existing indexes cover product+status and provider. These
-- additions cover common status-only/date and product/date list filters without
-- indexing provider reference material.
create index if not exists idx_commerce_transactions_status_received_admin
  on commerce.transactions(normalized_status, received_at_utc desc, id desc);

create index if not exists idx_commerce_transactions_product_received_admin
  on commerce.transactions(product_id, received_at_utc desc, id desc);

create index if not exists idx_commerce_orders_status_occurred_admin
  on commerce.orders(status, occurred_at_utc desc, id desc);

create index if not exists idx_commerce_orders_product_occurred_admin
  on commerce.orders(product_id, occurred_at_utc desc, id desc);

-- Audit/notification access is time-oriented. Keep failed/denied scans bounded by a
-- partial index without adding metadata/reason payloads to the index.
create index if not exists ix_admin_audit_alert_failures
  on admin.audit_events(occurred_at_utc desc, id)
  where result in ('Failed','Denied');

commit;
