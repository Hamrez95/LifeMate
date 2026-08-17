begin;

create table if not exists finance.approved_budget_sets (
  id uuid primary key default gen_random_uuid(),
  budget_code text not null check (budget_code ~ '^[a-z0-9][a-z0-9._:-]{0,63}$'),
  version integer not null check (version > 0),
  label text not null check (length(trim(label)) between 1 and 120),
  period_start date not null,
  period_end date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  approved_at_utc timestamptz not null,
  source_kind text not null check (length(trim(source_kind)) between 1 and 64),
  source_reference_hash text check (
    source_reference_hash is null or length(source_reference_hash) between 32 and 256
  ),
  creation_txid bigint not null default txid_current(),
  recorded_at_utc timestamptz not null default now(),
  check (period_start <= period_end),
  check (period_start = date_trunc('month', period_start::timestamp)::date),
  check (
    period_end = (
      date_trunc('month', period_end::timestamp) + interval '1 month - 1 day'
    )::date
  ),
  unique (budget_code, version, currency)
);

create table if not exists finance.approved_budget_allocations (
  id uuid primary key default gen_random_uuid(),
  budget_set_id uuid not null references finance.approved_budget_sets(id) on delete restrict,
  month_start date not null,
  entry_kind text not null check (entry_kind in ('Revenue', 'Expense')),
  category_code text not null check (category_code ~ '^[a-z0-9][a-z0-9._:-]{0,63}$'),
  category_label text not null check (length(trim(category_label)) between 1 and 120),
  amount_minor bigint not null check (amount_minor >= 0),
  recorded_at_utc timestamptz not null default now(),
  check (month_start = date_trunc('month', month_start::timestamp)::date),
  unique (budget_set_id, month_start, entry_kind, category_code)
);

create index if not exists ix_finance_budget_sets_period_currency
  on finance.approved_budget_sets(currency, period_start, period_end, approved_at_utc desc);
create index if not exists ix_finance_budget_allocations_set_month
  on finance.approved_budget_allocations(budget_set_id, month_start, entry_kind, category_code);

create or replace function finance.validate_budget_allocation_period()
returns trigger
language plpgsql
set search_path = finance, pg_temp
as $$
declare
  budget_period_start date;
  budget_period_end date;
  budget_creation_txid bigint;
begin
  select period_start, period_end, creation_txid
    into budget_period_start, budget_period_end, budget_creation_txid
  from finance.approved_budget_sets
  where id = new.budget_set_id;

  if not found
     or new.month_start < budget_period_start
     or new.month_start > budget_period_end then
    raise exception 'finance budget allocation month must be covered by its approved budget set';
  end if;

  if budget_creation_txid <> txid_current() then
    raise exception 'approved finance budget allocations must be published atomically with their budget set';
  end if;

  return new;
end
$$;

create or replace function finance.reject_budget_mutation()
returns trigger
language plpgsql
set search_path = finance, pg_temp
as $$
begin
  raise exception 'approved finance budgets are immutable; publish a new version instead';
end
$$;

drop trigger if exists trg_finance_validate_budget_allocation_period
  on finance.approved_budget_allocations;
create trigger trg_finance_validate_budget_allocation_period
before insert on finance.approved_budget_allocations
for each row execute function finance.validate_budget_allocation_period();

drop trigger if exists trg_finance_budget_sets_append_only on finance.approved_budget_sets;
create trigger trg_finance_budget_sets_append_only
before update or delete on finance.approved_budget_sets
for each row execute function finance.reject_budget_mutation();

drop trigger if exists trg_finance_budget_allocations_append_only
  on finance.approved_budget_allocations;
create trigger trg_finance_budget_allocations_append_only
before update or delete on finance.approved_budget_allocations
for each row execute function finance.reject_budget_mutation();

comment on table finance.approved_budget_sets is
  'Canonical approved management-budget versions. A set and all allocations are published in one transaction; later correction requires a new version. Budget assumptions remain separate from posted actuals and forecast data.';
comment on table finance.approved_budget_allocations is
  'Monthly approved budget allocations by finance category. A missing allocation or missing month is not interpreted as a zero budget.';
comment on column finance.approved_budget_sets.creation_txid is
  'Internal PostgreSQL transaction marker used only to prove allocations were created atomically with the immutable approved budget version.';

revoke all on finance.approved_budget_sets from public;
revoke all on finance.approved_budget_allocations from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on finance.approved_budget_sets from anon';
    execute 'revoke all on finance.approved_budget_allocations from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on finance.approved_budget_sets from authenticated';
    execute 'revoke all on finance.approved_budget_allocations from authenticated';
  end if;
end
$$;

grant select on finance.approved_budget_sets to lifemate_admin_runtime;
grant select on finance.approved_budget_allocations to lifemate_admin_runtime;
-- No budget write grant is given to the Admin runtime. Approved budget ingestion is a
-- separate controlled accounting process; browser/Admin API mutations remain out of scope.

commit;
