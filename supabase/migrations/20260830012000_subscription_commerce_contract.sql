begin;

-- #615 Subscription / Commerce contract. Extends canonical Commerce Catalog v2.

alter table commerce.products add column if not exists subscription_family_code varchar(64);

update commerce.products
set subscription_family_code = case
  when code='wellmate-caremate' then 'wellmate-caremate-premium'
  when code in ('period-calendar','cocoonmate') then 'women-lifecycle-premium'
  else subscription_family_code
end
where subscription_family_code is null;

insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version)
select p.id,v.policy_key,v.value_json,v.value_type,'Active',1
from commerce.products p
cross join (values
  ('free.medications.max','3'::jsonb,'integer'),
  ('free.visits.max','1'::jsonb,'integer'),
  ('free.owner_caregivers.max','1'::jsonb,'integer'),
  ('free.caremate_people.max','1'::jsonb,'integer')
) as v(policy_key,value_json,value_type)
where p.code='wellmate-caremate'
on conflict (product_id,policy_key) do nothing;

insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version)
select p.id,'trial.days','7'::jsonb,'integer','Active',1
from commerce.products p where p.code='period-calendar'
on conflict (product_id,policy_key) do nothing;

insert into commerce.catalog_policies(product_id,policy_key,value_json,value_type,status,version)
select p.id,'pricing.family',to_jsonb(p.subscription_family_code),'string','Active',1
from commerce.products p
where p.subscription_family_code is not null
on conflict (product_id,policy_key) do nothing;

create or replace function commerce.mobile_subscription_snapshot(p_app_user_id uuid)
returns jsonb language plpgsql security definer stable
set search_path=pg_catalog,commerce,identity,pg_temp
as $$
declare
  v_account uuid;
  v_now timestamptz := now();
  v_products jsonb;
begin
  v_account := identity.account_id_for_legacy_app_user(p_app_user_id);
  if v_account is null then
    return jsonb_build_object('httpStatus',409,'code','identity_account_mapping_missing');
  end if;

  select coalesce(jsonb_agg(product_payload order by product_code),'[]'::jsonb)
  into v_products
  from (
    select p.code as product_code,
      jsonb_build_object(
        'code',p.code,
        'name',p.display_name,
        'pricingFamily',p.subscription_family_code,
        'state',coalesce((
          select case
            when s.status='Trial' and coalesce(s.current_period_end_utc,'infinity')>v_now then 'trial'
            when s.status='Active' and coalesce(s.current_period_end_utc,'infinity')>v_now then 'active'
            when s.status='Expired' then 'expired'
            when s.status='Cancelled' then 'cancelled'
            else null end
          from commerce.subscriptions s
          where s.owner_account_id=v_account and s.product_id=p.id
          order by s.created_at_utc desc,s.id desc limit 1
        ),case when p.code='wellmate-caremate' then 'free' else 'inactive' end),
        'subscription',(
          select jsonb_build_object('status',s.status,'startsAtUtc',s.starts_at_utc,
            'currentPeriodEndUtc',s.current_period_end_utc,'cancelledAtUtc',s.cancelled_at_utc)
          from commerce.subscriptions s
          where s.owner_account_id=v_account and s.product_id=p.id
          order by s.created_at_utc desc,s.id desc limit 1
        ),
        'policies',coalesce((
          select jsonb_object_agg(cp.policy_key,cp.value_json order by cp.policy_key)
          from commerce.catalog_policies cp
          where cp.product_id=p.id and cp.status='Active'
        ),'{}'::jsonb),
        'offers',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',o.id,'code',o.code,'name',o.display_name,'durationMonths',o.duration_months,
            'giftEligible',o.gift_eligible,
            'price',case when pr.id is null then null else jsonb_build_object(
              'id',pr.id,'countryCode',pr.country_code,'currency',pr.currency,
              'storeProvider',pr.store_provider,'amountMinor',pr.amount_minor,
              'effectiveFromUtc',pr.effective_from_utc,'effectiveToUtc',pr.effective_to_utc) end
          ) order by o.duration_months,o.code)
          from commerce.offers o
          left join lateral (
            select x.* from commerce.prices x
            where x.offer_id=o.id and x.status='Active'
              and x.effective_from_utc<=v_now
              and (x.effective_to_utc is null or x.effective_to_utc>v_now)
            order by x.effective_from_utc desc,x.id desc limit 1
          ) pr on true
          where o.product_id=p.id and o.status='Published'
        ),'[]'::jsonb)
      ) as product_payload
    from commerce.products p
    where p.lifecycle_status='Published'
      and p.code in ('wellmate-caremate','period-calendar','cocoonmate')
  ) q;

  return jsonb_build_object('httpStatus',200,'code','ok','schemaVersion','2026-08-30',
    'asOfUtc',v_now,'products',v_products);
end $$;

revoke all on function commerce.mobile_subscription_snapshot(uuid) from public;
grant execute on function commerce.mobile_subscription_snapshot(uuid) to lifemate_edge_runtime;

commit;
