begin;

create or replace function commerce.enforce_refund_operation_integrity()
returns trigger
language plpgsql
set search_path=pg_catalog,commerce,pg_temp
as $$
declare
  v_transaction commerce.transactions%rowtype;
  v_refunded_minor bigint;
begin
  select * into v_transaction
  from commerce.transactions
  where id=new.transaction_id
  for update;

  if not found then
    raise exception 'refund_transaction_not_found';
  end if;

  if new.amount_minor <= 0 or new.amount_minor > v_transaction.amount_minor then
    raise exception 'refund_amount_invalid';
  end if;

  if new.currency <> v_transaction.currency then
    raise exception 'refund_currency_mismatch';
  end if;

  if new.provider <> v_transaction.provider then
    raise exception 'refund_provider_mismatch';
  end if;

  if new.status='Succeeded' then
    select coalesce(sum(amount_minor),0)::bigint into v_refunded_minor
    from commerce.refund_operations
    where transaction_id=new.transaction_id
      and status='Succeeded'
      and id<>new.id;

    if v_refunded_minor + new.amount_minor > v_transaction.amount_minor then
      raise exception 'refund_total_exceeds_transaction';
    end if;
  end if;

  return new;
end
$$;

drop trigger if exists trg_refund_operation_integrity on commerce.refund_operations;
create trigger trg_refund_operation_integrity
before insert or update of transaction_id,amount_minor,currency,provider,status
on commerce.refund_operations
for each row execute function commerce.enforce_refund_operation_integrity();

revoke all on function commerce.enforce_refund_operation_integrity() from public;

do $$
begin
  if to_regrole('anon') is not null then
    revoke all on function commerce.enforce_refund_operation_integrity() from anon;
  end if;
  if to_regrole('authenticated') is not null then
    revoke all on function commerce.enforce_refund_operation_integrity() from authenticated;
  end if;
end
$$;

comment on function commerce.enforce_refund_operation_integrity() is
  'Serializes successful refund settlement per transaction and rejects amount/currency/provider mismatches or cumulative over-refunds.';

commit;
