begin;

-- Keep refund and correction rows admin-only while giving the trusted healthcare
-- runtime the single boolean it needs to decide whether Period value can transfer.
create or replace function commerce.cocoon_period_conversion_eligible(
  p_account_id uuid,
  p_person_id uuid
) returns boolean
language sql
stable
security definer
set search_path = pg_catalog, commerce
as $$
  select exists(
    select 1
    from commerce.products period_product
    join commerce.subscriptions source
      on source.product_id=period_product.id
    join commerce.subscription_payment_sources payment
      on payment.subscription_id=source.id
    join commerce.transaction_effective_state_v1 transaction_state
      on transaction_state.transaction_id=payment.transaction_id
    where period_product.code='period-calendar'
      and period_product.status='Active'
      and source.owner_account_id=p_account_id
      and (source.beneficiary_person_id is null or source.beneficiary_person_id=p_person_id)
      and source.status='Active'
      and source.starts_at_utc<=now()
      and source.current_period_end_utc>now()
      and payment.service_period_end_utc>now()
      and transaction_state.effective_normalized_status in ('Succeeded','Refunded')
      and transaction_state.net_collected_minor>0
      and not exists(
        select 1
        from commerce.subscription_conversions conversion
        where conversion.source_subscription_id=source.id
      )
      and not exists(
        select 1
        from commerce.subscriptions existing
        join commerce.products cocoon_product on cocoon_product.id=existing.product_id
        where cocoon_product.code='cocoonmate'
          and cocoon_product.status='Active'
          and existing.owner_account_id=p_account_id
          and (existing.beneficiary_person_id is null or existing.beneficiary_person_id=p_person_id)
          and existing.status='Active'
          and (existing.current_period_end_utc is null or existing.current_period_end_utc>now())
      )
  );
$$;

revoke all on function commerce.cocoon_period_conversion_eligible(uuid,uuid)
  from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function commerce.cocoon_period_conversion_eligible(uuid,uuid) from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function commerce.cocoon_period_conversion_eligible(uuid,uuid) from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname='service_role') then
    revoke all on function commerce.cocoon_period_conversion_eligible(uuid,uuid) from service_role;
  end if;
  if exists (select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema commerce to lifemate_edge_runtime;
    grant execute on function commerce.cocoon_period_conversion_eligible(uuid,uuid)
      to lifemate_edge_runtime;
  end if;
end
$$;

commit;
