import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { CommerceCatalogV2Query } from "./commerce_catalog_v2.ts";

function iso(value: unknown): string | null {
  if (value instanceof Date) return value.toISOString();
  if (typeof value !== "string") return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

export function createCommerceCatalogV2Store(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async get(query: CommerceCatalogV2Query) {
      const products = await sql`
        select p.id, p.code, p.display_name, p.lifecycle_status, p.version, p.updated_at_utc
        from commerce.products p
        where (${query.product}::text is null or p.code=${query.product})
          and (${query.includeHidden}::boolean or p.lifecycle_status='Published')
          and p.lifecycle_status <> 'Retired'
        order by p.display_name, p.id
      `;
      const productIds = products.map((row) => String(row.id));
      const offers = productIds.length === 0 ? [] : await sql`
        select o.id,o.product_id,o.code,o.display_name,o.duration_months,o.status,o.gift_eligible,o.version,
               pr.id as price_id,pr.country_code,pr.currency,pr.store_provider,pr.amount_minor,pr.effective_from_utc
        from commerce.offers o
        left join lateral (
          select p2.* from commerce.prices p2
          where p2.offer_id=o.id
            and p2.status='Active'
            and p2.effective_from_utc <= now()
            and (p2.effective_to_utc is null or p2.effective_to_utc > now())
          order by p2.effective_from_utc desc,p2.id desc limit 1
        ) pr on true
        where o.product_id = any(${productIds}::uuid[])
          and (${query.includeHidden}::boolean or o.status='Published')
          and o.status <> 'Retired'
        order by o.product_id,o.duration_months,o.code
      `;
      const policies = productIds.length === 0 ? [] : await sql`
        select policy_key,product_id,value_json,value_type,version
        from commerce.catalog_policies
        where product_id = any(${productIds}::uuid[]) and status='Active'
        order by product_id,policy_key
      `;
      const bundles = productIds.length === 0 ? [] : await sql`
        select b.id,b.code,b.display_name,b.status,b.gift_eligible,b.version,
               bi.offer_id,o.product_id,o.code as offer_code
        from commerce.bundles b
        left join commerce.bundle_items bi on bi.bundle_id=b.id
        left join commerce.offers o on o.id=bi.offer_id
        where (${query.includeHidden}::boolean or b.status='Published')
          and b.status <> 'Retired'
          and (o.product_id is null or o.product_id = any(${productIds}::uuid[]))
        order by b.code,o.product_id,o.code
      `;
      return {
        version: "2026-08-26",
        products: products.map((row) => ({
          id: String(row.id),
          code: String(row.code),
          name: String(row.display_name),
          status: String(row.lifecycle_status),
          version: Number(row.version),
          updatedAtUtc: iso(row.updated_at_utc),
          offers: offers
            .filter((offer) => String(offer.product_id) === String(row.id))
            .map((offer) => ({
              id: String(offer.id),
              code: String(offer.code),
              name: String(offer.display_name),
              durationMonths: Number(offer.duration_months),
              status: String(offer.status),
              giftEligible: Boolean(offer.gift_eligible),
              version: Number(offer.version),
              price: offer.price_id
                ? {
                  id: String(offer.price_id),
                  countryCode: offer.country_code == null
                    ? null
                    : String(offer.country_code),
                  currency: String(offer.currency),
                  storeProvider: String(offer.store_provider),
                  amountMinor: String(offer.amount_minor),
                  effectiveFromUtc: iso(offer.effective_from_utc),
                }
                : null,
            })),
          policies: policies
            .filter((policy) => String(policy.product_id) === String(row.id))
            .map((policy) => ({
              key: String(policy.policy_key),
              value: policy.value_json,
              valueType: String(policy.value_type),
              version: Number(policy.version),
            })),
        })),
        bundles: Object.values(
          bundles.reduce<
            Record<string, {
              id: string;
              code: string;
              name: string;
              status: string;
              giftEligible: boolean;
              version: number;
              items: Array<
                { offerId: string; offerCode: string; productId: string }
              >;
            }>
          >((acc, row) => {
            const id = String(row.id);
            acc[id] ??= {
              id,
              code: String(row.code),
              name: String(row.display_name),
              status: String(row.status),
              giftEligible: Boolean(row.gift_eligible),
              version: Number(row.version),
              items: [],
            };
            if (row.offer_id) {
              acc[id].items.push({
                offerId: String(row.offer_id),
                offerCode: String(row.offer_code),
                productId: String(row.product_id),
              });
            }
            return acc;
          }, {}),
        ),
      };
    },
  };
}
