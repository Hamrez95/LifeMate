begin;

-- Expose only whether CocoonMate has a published offer. The edge runtime does
-- not need direct read access to the commerce offers catalog.
create or replace function commerce.cocoon_product_offer_available()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, commerce
as $$
  select exists(
    select 1
    from commerce.offers offer
    join commerce.products product on product.id=offer.product_id
    where product.code='cocoonmate'
      and product.status='Active'
      and product.lifecycle_status='Published'
      and offer.status='Published'
  );
$$;

revoke all on function commerce.cocoon_product_offer_available() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function commerce.cocoon_product_offer_available() from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function commerce.cocoon_product_offer_available() from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname='service_role') then
    revoke all on function commerce.cocoon_product_offer_available() from service_role;
  end if;
  if exists (select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema commerce to lifemate_edge_runtime;
    grant execute on function commerce.cocoon_product_offer_available()
      to lifemate_edge_runtime;
  end if;
end
$$;

commit;
