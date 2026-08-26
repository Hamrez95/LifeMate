import { type LifeMateSql, getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export type CommerceCatalogQuery = { product: string | null };
const PRODUCT_CODE = /^[a-z0-9][a-z0-9._-]{1,63}$/;

export function parseCommerceCatalogQuery(url: URL): CommerceCatalogQuery {
  const raw = url.searchParams.get("product")?.trim().toLowerCase() ?? "";
  if (raw && !PRODUCT_CODE.test(raw)) {
    throw new ApiError(400, "commerce_product_invalid", "Commerce product filter is invalid.");
  }
  return { product: raw || null };
}

export function createCommerceCatalogStore(databaseUrl: string) {
  const sql: LifeMateSql = getLifeMateSql(databaseUrl);
  return {
    async published(query: CommerceCatalogQuery) {
      const products = await sql`
        select id,code,display_name,updated_at_utc
        from commerce.products
        where lifecycle_status='Published'
          and (${query.product}::text is null or code=${query.product})
        order by display_name,id
      `;
      const ids = products.map((row) => String(row.id));
      if (ids.length === 0) return { version: "2026-08-26", products: [], bundles: [] };
      const offers = await sql`
        select o.id,o.product_id,o.code,o.display_name,o.duration_months,o.gift_eligible,o.version,
               p.id as price_id,p.country_code,p.currency,p.store_provider,p.amount_minor,p.effective_from_utc
        from commerce.offers o
        left join lateral (
          select p2.* from commerce.prices p2
          where p2.offer_id=o.id and p2.status='Active'
            and p2.effective_from_utc <= now()
            and (p2.effective_to_utc is null or p2.effective_to_utc > now())
          order by p2.effective_from_utc desc,p2.id desc limit 1
        ) p on true
        where o.product_id=any(${ids}::uuid[]) and o.status='Published'
        order by o.product_id,o.duration_months,o.code
      `;
      const policies = await sql`
        select product_id,policy_key,value_json,value_type,version
        from commerce.catalog_policies
        where product_id=any(${ids}::uuid[]) and status='Active'
        order by product_id,policy_key
      `;
      const bundles = await sql`
        select distinct b.id,b.code,b.display_name,b.gift_eligible,b.version
        from commerce.bundles b
        join commerce.bundle_items bi on bi.bundle_id=b.id
        join commerce.offers o on o.id=bi.offer_id
        where b.status='Published' and o.status='Published'
          and o.product_id=any(${ids}::uuid[])
        order by b.display_name,b.id
      `;
      return {
        version: "2026-08-26",
        products: products.map((product) => ({
          id: String(product.id), code: String(product.code), name: String(product.display_name),
          offers: offers.filter((offer) => String(offer.product_id) === String(product.id)).map((offer) => ({
            id: String(offer.id), code: String(offer.code), name: String(offer.display_name),
            durationMonths: Number(offer.duration_months), giftEligible: Boolean(offer.gift_eligible), version: Number(offer.version),
            price: offer.price_id ? { id:String(offer.price_id), countryCode:offer.country_code == null ? null : String(offer.country_code), currency:String(offer.currency), storeProvider:String(offer.store_provider), amountMinor:String(offer.amount_minor), effectiveFromUtc:new Date(String(offer.effective_from_utc)).toISOString() } : null,
          })),
          policies: policies.filter((policy) => String(policy.product_id) === String(product.id)).map((policy) => ({ key:String(policy.policy_key), value:policy.value_json, valueType:String(policy.value_type), version:Number(policy.version) })),
        })),
        bundles: bundles.map((bundle) => ({ id:String(bundle.id), code:String(bundle.code), name:String(bundle.display_name), giftEligible:Boolean(bundle.gift_eligible), version:Number(bundle.version) })),
      };
    },
  };
}
