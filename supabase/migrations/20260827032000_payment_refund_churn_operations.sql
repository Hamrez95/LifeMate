begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('commerce.refund.read','commerce','SENSITIVE',true,'Read refund and provider execution state'),
('commerce.refund.request','commerce','HIGH_RISK',true,'Request full or partial refund review'),
('commerce.refund.approve','commerce','HIGH_RISK',true,'Approve refund execution'),
('commerce.refund.execute','commerce','HIGH_RISK',true,'Submit an approved refund to provider execution'),
('commerce.reconciliation.read','commerce','SENSITIVE',true,'Read payment reconciliation cases and correction events'),
('commerce.reconciliation.write','commerce','HIGH_RISK',true,'Resolve reconciliation cases through append-only correction events'),
('commerce.churn.read','commerce','SENSITIVE',true,'Read cancellation and non-renewal reasons'),
('commerce.churn.write','commerce','HIGH_RISK',true,'Record subscription non-renewal/cancellation intent')
on conflict(code) do update set
  domain=excluded.domain,risk_level=excluded.risk_level,role_assignable=excluded.role_assignable,
  description=excluded.description,updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.permission_code
from admin.roles r
join (values
  ('support','commerce.refund.read'),('support','commerce.refund.request'),
  ('finance','commerce.refund.read'),('finance','commerce.refund.request'),('finance','commerce.refund.approve'),('finance','commerce.refund.execute'),
  ('founder','commerce.refund.read'),('founder','commerce.refund.request'),('founder','commerce.refund.approve'),('founder','commerce.refund.execute'),
  ('finance','commerce.reconciliation.read'),('finance','commerce.reconciliation.write'),
  ('founder','commerce.reconciliation.read'),('founder','commerce.reconciliation.write'),
  ('support','commerce.churn.read'),('finance','commerce.churn.read'),('founder','commerce.churn.read'),
  ('founder','commerce.churn.write')
) p(role_code,permission_code) on p.role_code=r.code
on conflict do nothing;

insert into admin.approval_policies(
  request_type,display_name,request_permission,approval_permission,execution_permission,
  self_approval_allowed,default_expiry_minutes,status,version
) values
('commerce_refund_execution','Refund execution','commerce.refund.request','commerce.refund.approve','commerce.refund.execute',false,1440,'Active',1),
('commerce_transaction_correction','Transaction correction','commerce.reconciliation.write','commerce.reconciliation.write','commerce.reconciliation.write',false,1440,'Active',1)
on conflict(request_type) do update set
  display_name=excluded.display_name,request_permission=excluded.request_permission,
  approval_permission=excluded.approval_permission,execution_permission=excluded.execution_permission,
  self_approval_allowed=false,status='Active',updated_at_utc=now();

insert into admin.approval_policy_approver_roles(request_type,role_code) values
('commerce_refund_execution','finance'),('commerce_refund_execution','founder'),
('commerce_transaction_correction','finance'),('commerce_transaction_correction','founder')
on conflict do nothing;

alter table commerce.refund_requests
  add column if not exists approval_request_id uuid references admin.approval_requests(id) on delete restrict,
  add column if not exists version bigint not null default 1 check(version>=1);

create table if not exists commerce.refund_operations(
  id uuid primary key default gen_random_uuid(),
  refund_request_id uuid not null unique references commerce.refund_requests(id) on delete restrict,
  transaction_id uuid not null references commerce.transactions(id) on delete restrict,
  provider character varying(80) not null,
  amount_minor bigint not null check(amount_minor>0),
  currency character varying(3) not null check(currency ~ '^[A-Z]{3}$'),
  status character varying(24) not null default 'PendingProvider'
    check(status in ('PendingProvider','Submitted','Succeeded','Failed','Cancelled')),
  provider_reference_hash character varying(128),
  provider_error_code character varying(120),
  submitted_at_utc timestamptz,
  settled_at_utc timestamptz,
  actor_account_id uuid not null,
  correlation_id uuid not null,
  idempotency_key character varying(180) not null,
  request_hash character varying(128) not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique(actor_account_id,idempotency_key)
);
create index if not exists ix_refund_operations_transaction on commerce.refund_operations(transaction_id,created_at_utc desc);

create table if not exists commerce.reconciliation_cases(
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid references commerce.transactions(id) on delete restrict,
  case_type character varying(40) not null check(case_type in ('MissingProviderEvent','StatusMismatch','AmountMismatch','ReferenceMismatch','ManualReview')),
  status character varying(20) not null default 'Open' check(status in ('Open','InReview','Resolved','Dismissed')),
  source character varying(40) not null check(source in ('System','Provider','Admin')),
  reason character varying(1000) not null check(length(trim(reason)) between 10 and 1000),
  assigned_to_account_id uuid,
  opened_at_utc timestamptz not null default now(),
  resolved_at_utc timestamptz,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);
create index if not exists ix_reconciliation_cases_status on commerce.reconciliation_cases(status,opened_at_utc desc,id desc);

create table if not exists commerce.transaction_corrections(
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references commerce.transactions(id) on delete restrict,
  reconciliation_case_id uuid references commerce.reconciliation_cases(id) on delete restrict,
  correction_type character varying(40) not null check(correction_type in ('NormalizedStatusClassification','ReferenceAnnotation')),
  corrected_normalized_status character varying(20)
    check(corrected_normalized_status is null or corrected_normalized_status in ('Pending','Succeeded','Failed','Cancelled','Refunded','Chargeback')),
  annotation_code character varying(80),
  reason character varying(1000) not null check(length(trim(reason)) between 10 and 1000),
  approval_request_id uuid not null references admin.approval_requests(id) on delete restrict,
  actor_account_id uuid not null,
  correlation_id uuid not null,
  created_at_utc timestamptz not null default now(),
  check(
    (correction_type='NormalizedStatusClassification' and corrected_normalized_status is not null and annotation_code is null)
    or (correction_type='ReferenceAnnotation' and corrected_normalized_status is null and annotation_code ~ '^[a-z][a-z0-9._-]{2,79}$')
  )
);
create index if not exists ix_transaction_corrections_transaction on commerce.transaction_corrections(transaction_id,created_at_utc desc,id desc);

alter table commerce.subscriptions
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists non_renewal_requested_at_utc timestamptz,
  add column if not exists cancellation_reason_code character varying(80),
  add column if not exists cancellation_reason_text character varying(1000),
  add column if not exists cancellation_version bigint not null default 1 check(cancellation_version>=1);

create table if not exists commerce.subscription_cancellation_events(
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references commerce.subscriptions(id) on delete restrict,
  event_type character varying(24) not null check(event_type in ('CancelAtPeriodEnd','ResumeRenewal','PeriodEnded')),
  reason_code character varying(80),
  reason_text character varying(1000),
  actor_account_id uuid,
  actor_type character varying(20) not null check(actor_type in ('User','Admin','System','Provider')),
  occurred_at_utc timestamptz not null default now(),
  correlation_id uuid not null,
  idempotency_key character varying(180),
  created_at_utc timestamptz not null default now()
);
create unique index if not exists ux_subscription_cancellation_event_idempotency
  on commerce.subscription_cancellation_events(subscription_id,idempotency_key)
  where idempotency_key is not null;

alter table commerce.refund_operations enable row level security;
alter table commerce.refund_operations force row level security;
alter table commerce.reconciliation_cases enable row level security;
alter table commerce.reconciliation_cases force row level security;
alter table commerce.transaction_corrections enable row level security;
alter table commerce.transaction_corrections force row level security;
alter table commerce.subscription_cancellation_events enable row level security;
alter table commerce.subscription_cancellation_events force row level security;

revoke all on commerce.refund_operations,commerce.reconciliation_cases,commerce.transaction_corrections,commerce.subscription_cancellation_events from public,anon,authenticated;
grant select on commerce.refund_operations,commerce.reconciliation_cases,commerce.transaction_corrections,commerce.subscription_cancellation_events to lifemate_admin_runtime;

drop policy if exists refund_operations_admin_read on commerce.refund_operations;
drop policy if exists reconciliation_cases_admin_read on commerce.reconciliation_cases;
drop policy if exists transaction_corrections_admin_read on commerce.transaction_corrections;
drop policy if exists subscription_cancellation_events_admin_read on commerce.subscription_cancellation_events;
create policy refund_operations_admin_read on commerce.refund_operations for select to lifemate_admin_runtime using(true);
create policy reconciliation_cases_admin_read on commerce.reconciliation_cases for select to lifemate_admin_runtime using(true);
create policy transaction_corrections_admin_read on commerce.transaction_corrections for select to lifemate_admin_runtime using(true);
create policy subscription_cancellation_events_admin_read on commerce.subscription_cancellation_events for select to lifemate_admin_runtime using(true);

create or replace view commerce.transaction_effective_state_v1
with (security_invoker=true)
as
select
  t.id as transaction_id,
  t.normalized_status as provider_normalized_status,
  coalesce(c.corrected_normalized_status,t.normalized_status) as effective_normalized_status,
  case when c.id is null then 'ProviderFact' else 'ManualCorrection' end as classification_source,
  c.id as correction_id,
  coalesce(r.refunded_minor,0)::bigint as refunded_minor,
  greatest(t.amount_minor-coalesce(r.refunded_minor,0),0)::bigint as net_collected_minor,
  t.amount_minor,
  t.currency,
  t.received_at_utc
from commerce.transactions t
left join lateral(
  select tc.id,tc.corrected_normalized_status
  from commerce.transaction_corrections tc
  where tc.transaction_id=t.id and tc.correction_type='NormalizedStatusClassification'
  order by tc.created_at_utc desc,tc.id desc limit 1
) c on true
left join lateral(
  select sum(ro.amount_minor) filter(where ro.status='Succeeded') as refunded_minor
  from commerce.refund_operations ro where ro.transaction_id=t.id
) r on true;
revoke all on commerce.transaction_effective_state_v1 from public,anon,authenticated;
grant select on commerce.transaction_effective_state_v1 to lifemate_admin_runtime;

commit;