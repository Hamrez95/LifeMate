begin;

create schema if not exists finance;

create table if not exists finance.actual_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  occurred_on date not null,
  entry_kind text not null check (entry_kind in ('Revenue', 'Expense')),
  category_code text not null check (category_code ~ '^[a-z0-9][a-z0-9._:-]{0,63}$'),
  category_label text not null check (length(trim(category_label)) between 1 and 120),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  effect smallint not null default 1 check (effect in (-1, 1)),
  reversal_of_entry_id uuid references finance.actual_ledger_entries(id) on delete restrict,
  source_kind text not null check (length(trim(source_kind)) between 1 and 64),
  source_reference_hash text check (
    source_reference_hash is null or length(source_reference_hash) between 32 and 256
  ),
  posted_at_utc timestamptz not null,
  recorded_at_utc timestamptz not null default now(),
  check (
    (effect = 1 and reversal_of_entry_id is null)
    or (effect = -1 and reversal_of_entry_id is not null)
  )
);

create unique index if not exists uq_finance_actual_ledger_single_reversal
  on finance.actual_ledger_entries(reversal_of_entry_id)
  where reversal_of_entry_id is not null;
create index if not exists ix_finance_actual_ledger_period_currency
  on finance.actual_ledger_entries(occurred_on, currency, entry_kind, category_code);
create index if not exists ix_finance_actual_ledger_posted
  on finance.actual_ledger_entries(posted_at_utc desc, id desc);

create or replace function finance.validate_actual_ledger_reversal()
returns trigger
language plpgsql
set search_path = finance, pg_temp
as $$
declare
  original finance.actual_ledger_entries%rowtype;
begin
  if new.effect = 1 then
    return new;
  end if;

  select * into original
  from finance.actual_ledger_entries
  where id = new.reversal_of_entry_id
  for update;

  if not found or original.effect <> 1 then
    raise exception 'finance reversal target is invalid';
  end if;

  if new.entry_kind <> original.entry_kind
     or new.category_code <> original.category_code
     or new.category_label <> original.category_label
     or new.amount_minor <> original.amount_minor
     or new.currency <> original.currency then
    raise exception 'finance reversal must exactly negate its original entry';
  end if;

  return new;
end
$$;

create or replace function finance.reject_actual_ledger_mutation()
returns trigger
language plpgsql
set search_path = finance, pg_temp
as $$
begin
  raise exception 'finance actual ledger is append-only; post a reversal instead';
end
$$;

drop trigger if exists trg_finance_validate_actual_ledger_reversal on finance.actual_ledger_entries;
create trigger trg_finance_validate_actual_ledger_reversal
before insert on finance.actual_ledger_entries
for each row execute function finance.validate_actual_ledger_reversal();

drop trigger if exists trg_finance_actual_ledger_append_only on finance.actual_ledger_entries;
create trigger trg_finance_actual_ledger_append_only
before update or delete on finance.actual_ledger_entries
for each row execute function finance.reject_actual_ledger_mutation();

comment on table finance.actual_ledger_entries is
  'Canonical posted management-finance actuals. Entries are append-only; corrections are exact reversal plus replacement. Forecast/budget assumptions never belong in this table.';
comment on column finance.actual_ledger_entries.source_reference_hash is
  'Optional privacy-minimized external/source reference hash. Raw banking credentials, card data and provider secrets are forbidden.';

revoke all on schema finance from public;
revoke all on finance.actual_ledger_entries from public;

do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on schema finance from anon';
    execute 'revoke all on finance.actual_ledger_entries from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on schema finance from authenticated';
    execute 'revoke all on finance.actual_ledger_entries from authenticated';
  end if;
end
$$;

grant usage on schema finance to lifemate_admin_runtime;
grant select on finance.actual_ledger_entries to lifemate_admin_runtime;
-- No INSERT/UPDATE/DELETE grant is given to lifemate_admin_runtime. Posting actuals is
-- an offline/accounting ingestion responsibility and must remain outside browser/Admin API mutations.

commit;
