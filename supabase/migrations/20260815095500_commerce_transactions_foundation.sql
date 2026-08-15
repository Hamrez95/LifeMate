begin;

create table commerce.orders (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references lifemate.accounts(id) on delete restrict,
  subscription_id uuid null references commerce.subscriptions(id) on delete set null,
  product_id uuid not null references commerce.products(id) on delete restrict,
  status text not null check (status in (
    'Pending', 'Authorized', 'Paid', 'Failed', 'Cancelled', 'Refunded', 'Chargeback'
  )),
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  occurred_at_utc timestamptz not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

create index idx_commerce_orders_account_updated
  on commerce.orders (account_id, updated_at_utc desc, id desc);
create index idx_commerce_orders_product_status_updated
  on commerce.orders (product_id, status, updated_at_utc desc, id desc);
create index idx_commerce_orders_subscription
  on commerce.orders (subscription_id)
  where subscription_id is not null;

create table commerce.transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid null references commerce.orders(id) on delete set null,
  subscription_id uuid null references commerce.subscriptions(id) on delete set null,
  product_id uuid not null references commerce.products(id) on delete restrict,
  account_id uuid null references lifemate.accounts(id) on delete set null,
  provider text not null check (length(provider) between 1 and 64),
  provider_reference_hash text not null check (length(provider_reference_hash) between 32 and 256),
  provider_status text not null check (length(provider_status) between 1 and 128),
  normalized_status text not null check (normalized_status in (
    'Pending', 'Succeeded', 'Failed', 'Cancelled', 'Refunded', 'Chargeback'
  )),
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  occurred_at_utc timestamptz not null,
  received_at_utc timestamptz not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  unique (provider, provider_reference_hash)
);

create index idx_commerce_transactions_received
  on commerce.transactions (received_at_utc desc, id desc);
create index idx_commerce_transactions_product_status_received
  on commerce.transactions (product_id, normalized_status, received_at_utc desc, id desc);
create index idx_commerce_transactions_provider_received
  on commerce.transactions (provider, received_at_utc desc, id desc);
create index idx_commerce_transactions_account_received
  on commerce.transactions (account_id, received_at_utc desc, id desc)
  where account_id is not null;
create index idx_commerce_transactions_order
  on commerce.transactions (order_id)
  where order_id is not null;

create table commerce.transaction_events (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid null references commerce.transactions(id) on delete set null,
  provider text not null check (length(provider) between 1 and 64),
  provider_event_reference_hash text not null check (length(provider_event_reference_hash) between 32 and 256),
  provider_transaction_reference_hash text not null check (length(provider_transaction_reference_hash) between 32 and 256),
  provider_status text not null check (length(provider_status) between 1 and 128),
  normalized_status text not null check (normalized_status in (
    'Pending', 'Succeeded', 'Failed', 'Cancelled', 'Refunded', 'Chargeback'
  )),
  observation_state text not null check (observation_state in (
    'InOrder', 'Duplicate', 'OutOfOrder'
  )),
  occurred_at_utc timestamptz not null,
  received_at_utc timestamptz not null,
  recorded_at_utc timestamptz not null default now(),
  unique (provider, provider_event_reference_hash)
);

create index idx_commerce_transaction_events_transaction_time
  on commerce.transaction_events (transaction_id, occurred_at_utc desc, id desc)
  where transaction_id is not null;
create index idx_commerce_transaction_events_observation_received
  on commerce.transaction_events (observation_state, received_at_utc desc, id desc);

comment on table commerce.orders is
  'Canonical commercial order intent. It is not a provider payment payload and does not store card/payment secrets.';
comment on table commerce.transactions is
  'Canonical normalized financial transaction state. Provider references are stored only as hashes.';
comment on table commerce.transaction_events is
  'Privacy-minimized provider event facts used for deduplication/order diagnostics. Raw webhook payloads are not stored here.';

revoke all on commerce.orders from public, anon, authenticated;
revoke all on commerce.transactions from public, anon, authenticated;
revoke all on commerce.transaction_events from public, anon, authenticated;

grant select on commerce.orders to lifemate_admin_runtime;
grant select on commerce.transactions to lifemate_admin_runtime;
grant select on commerce.transaction_events to lifemate_admin_runtime;

commit;
