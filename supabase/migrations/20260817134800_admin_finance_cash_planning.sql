begin;

create table if not exists finance.cash_balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  as_of_date date not null,
  balance_minor bigint not null check (balance_minor >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  source_kind text not null check (length(trim(source_kind)) between 1 and 64),
  source_reference_hash text check (
    source_reference_hash is null or length(source_reference_hash) between 32 and 256
  ),
  observed_at_utc timestamptz not null,
  recorded_at_utc timestamptz not null default now()
);

create index if not exists ix_finance_cash_balance_currency_date
  on finance.cash_balance_snapshots(currency, as_of_date desc, observed_at_utc desc, id desc);

create table if not exists finance.cash_plan_versions (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null check (plan_code ~ '^[a-z0-9][a-z0-9._:-]{0,63}$'),
  version integer not null check (version > 0),
  label text not null check (length(trim(label)) between 1 and 120),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  forecast_start_month date not null,
  horizon_months integer not null check (horizon_months between 1 and 18),
  approved_at_utc timestamptz not null,
  source_kind text not null check (length(trim(source_kind)) between 1 and 64),
  source_reference_hash text check (
    source_reference_hash is null or length(source_reference_hash) between 32 and 256
  ),
  creation_txid bigint not null default txid_current(),
  recorded_at_utc timestamptz not null default now(),
  check (forecast_start_month = date_trunc('month', forecast_start_month::timestamp)::date),
  unique (plan_code, version, currency)
);

create table if not exists finance.cash_plan_assumptions (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references finance.cash_plan_versions(id) on delete restrict,
  scenario text not null check (scenario in ('Base', 'Upside', 'Downside')),
  assumption_code text not null check (assumption_code ~ '^[a-z0-9][a-z0-9._:-]{0,63}$'),
  label text not null check (length(trim(label)) between 1 and 120),
  value_text text not null check (length(trim(value_text)) between 1 and 240),
  sort_order integer not null default 0 check (sort_order between 0 and 10000),
  recorded_at_utc timestamptz not null default now(),
  unique (plan_version_id, scenario, assumption_code)
);

create table if not exists finance.cash_plan_scenario_months (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references finance.cash_plan_versions(id) on delete restrict,
  scenario text not null check (scenario in ('Base', 'Upside', 'Downside')),
  month_start date not null,
  revenue_minor bigint not null check (revenue_minor >= 0),
  expense_minor bigint not null check (expense_minor >= 0),
  recorded_at_utc timestamptz not null default now(),
  check (month_start = date_trunc('month', month_start::timestamp)::date),
  unique (plan_version_id, scenario, month_start)
);

create index if not exists ix_finance_cash_plan_versions_start_currency
  on finance.cash_plan_versions(currency, forecast_start_month, approved_at_utc desc, version desc);
create index if not exists ix_finance_cash_plan_assumptions_plan_scenario
  on finance.cash_plan_assumptions(plan_version_id, scenario, sort_order, assumption_code);
create index if not exists ix_finance_cash_plan_scenario_months_plan
  on finance.cash_plan_scenario_months(plan_version_id, scenario, month_start);

create or replace function finance.validate_cash_plan_child()
returns trigger
language plpgsql
set search_path = finance, pg_temp
as $$
declare
  plan_creation_txid bigint;
  plan_start date;
  plan_horizon integer;
begin
  select creation_txid, forecast_start_month, horizon_months
    into plan_creation_txid, plan_start, plan_horizon
  from finance.cash_plan_versions
  where id = new.plan_version_id;

  if not found or plan_creation_txid <> txid_current() then
    raise exception 'cash plan children must be published atomically with their immutable plan version';
  end if;

  if tg_table_name = 'cash_plan_scenario_months' then
    if new.month_start < plan_start
       or new.month_start >= (plan_start + make_interval(months => plan_horizon))::date then
      raise exception 'cash plan scenario month must be inside the declared forecast horizon';
    end if;
  end if;

  return new;
end
$$;

create or replace function finance.reject_cash_planning_mutation()
returns trigger
language plpgsql
set search_path = finance, pg_temp
as $$
begin
  raise exception 'canonical finance cash-planning records are immutable; append a new snapshot or publish a new plan version';
end
$$;

drop trigger if exists trg_finance_cash_balance_append_only on finance.cash_balance_snapshots;
create trigger trg_finance_cash_balance_append_only
before update or delete on finance.cash_balance_snapshots
for each row execute function finance.reject_cash_planning_mutation();

drop trigger if exists trg_finance_cash_plan_versions_append_only on finance.cash_plan_versions;
create trigger trg_finance_cash_plan_versions_append_only
before update or delete on finance.cash_plan_versions
for each row execute function finance.reject_cash_planning_mutation();

drop trigger if exists trg_finance_cash_plan_assumptions_validate on finance.cash_plan_assumptions;
create trigger trg_finance_cash_plan_assumptions_validate
before insert on finance.cash_plan_assumptions
for each row execute function finance.validate_cash_plan_child();

drop trigger if exists trg_finance_cash_plan_assumptions_append_only on finance.cash_plan_assumptions;
create trigger trg_finance_cash_plan_assumptions_append_only
before update or delete on finance.cash_plan_assumptions
for each row execute function finance.reject_cash_planning_mutation();

drop trigger if exists trg_finance_cash_plan_months_validate on finance.cash_plan_scenario_months;
create trigger trg_finance_cash_plan_months_validate
before insert on finance.cash_plan_scenario_months
for each row execute function finance.validate_cash_plan_child();

drop trigger if exists trg_finance_cash_plan_months_append_only on finance.cash_plan_scenario_months;
create trigger trg_finance_cash_plan_months_append_only
before update or delete on finance.cash_plan_scenario_months
for each row execute function finance.reject_cash_planning_mutation();

comment on table finance.cash_balance_snapshots is
  'Canonical observed management cash balances. Each row is an immutable point-in-time actual; raw banking credentials, account secrets, card data and provider secrets are forbidden.';
comment on table finance.cash_plan_versions is
  'Immutable, versioned management cash forecast plans. Forecast data is separate from posted actuals and observed cash balances; no plan is inferred from historical actuals.';
comment on table finance.cash_plan_assumptions is
  'Display-safe, versioned forecast assumptions by Base/Upside/Downside scenario. Assumptions are explanatory inputs, never actuals.';
comment on table finance.cash_plan_scenario_months is
  'Versioned forecast monthly revenue/expense by scenario. Missing scenario months are unavailable and must never be treated as zero.';

revoke all on finance.cash_balance_snapshots from public;
revoke all on finance.cash_plan_versions from public;
revoke all on finance.cash_plan_assumptions from public;
revoke all on finance.cash_plan_scenario_months from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on finance.cash_balance_snapshots from anon';
    execute 'revoke all on finance.cash_plan_versions from anon';
    execute 'revoke all on finance.cash_plan_assumptions from anon';
    execute 'revoke all on finance.cash_plan_scenario_months from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on finance.cash_balance_snapshots from authenticated';
    execute 'revoke all on finance.cash_plan_versions from authenticated';
    execute 'revoke all on finance.cash_plan_assumptions from authenticated';
    execute 'revoke all on finance.cash_plan_scenario_months from authenticated';
  end if;
end
$$;

grant select on finance.cash_balance_snapshots to lifemate_admin_runtime;
grant select on finance.cash_plan_versions to lifemate_admin_runtime;
grant select on finance.cash_plan_assumptions to lifemate_admin_runtime;
grant select on finance.cash_plan_scenario_months to lifemate_admin_runtime;
-- The Admin runtime is deliberately read-only. Cash snapshot and forecast-plan ingestion
-- remains a controlled finance process outside browser/Admin API mutation authority.

commit;
