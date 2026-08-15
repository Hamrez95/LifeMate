import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { CommerceOverviewQuery } from "./commerce.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export type CommerceSubscriptionRow = {
  subscriptionId: string;
  productCode: string;
  productName: string;
  planId: string;
  planCode: string;
  planName: string;
  status: string;
  startsAtUtc: string;
  currentPeriodEndUtc: string | null;
  cancelledAtUtc: string | null;
};

export type CommercePlanDistributionRow = {
  planId: string;
  productCode: string;
  productName: string;
  planCode: string;
  planName: string;
  planStatus: string;
  subscriptions: number;
  activeSubscriptions: number;
};

export type CommerceEntitlementCoverageRow = {
  featureCode: string;
  active: number;
  expired: number;
  revoked: number;
};

export type CommerceRenewalHighlight = {
  subscriptionId: string;
  productCode: string;
  planCode: string;
  planName: string;
  status: string;
  currentPeriodEndUtc: string;
};

export type CommerceEntitlementExpiryHighlight = {
  entitlementId: string;
  featureCode: string;
  source: string;
  expiresAtUtc: string;
};

async function getSummary(sql: AdminSql, product: string | null) {
  const rows = await sql`
    select
      count(*) filter (where s.status = 'Active')::integer as active,
      count(*) filter (where s.status = 'Trial')::integer as trial,
      count(*) filter (where s.status = 'PastDue')::integer as past_due,
      count(*) filter (where s.status = 'Cancelled')::integer as cancelled,
      count(*) filter (where s.status = 'Expired')::integer as expired,
      count(*) filter (where s.status = 'Refunded')::integer as refunded
    from commerce.subscriptions s
    join commerce.products p on p.id = s.product_id
    where (${product}::text is null or p.code = ${product})
  `;

  const entitlementRows = await sql`
    select
      count(*) filter (
        where e.status = 'Active'
          and e.starts_at_utc <= now()
          and (e.expires_at_utc is null or e.expires_at_utc > now())
      )::integer as active,
      count(*) filter (
        where e.status = 'Expired'
           or (
             e.status = 'Active'
             and e.expires_at_utc is not null
             and e.expires_at_utc <= now()
           )
      )::integer as expired,
      count(*) filter (where e.status = 'Revoked')::integer as revoked
    from commerce.entitlements e
    where ${product}::text is null
       or exists (
         select 1
         from commerce.product_features pf
         join commerce.products p on p.id = pf.product_id
         where pf.feature_id = e.feature_id
           and p.code = ${product}
       )
  `;

  const subscription = rows[0] ?? {};
  const entitlement = entitlementRows[0] ?? {};
  return {
    subscriptions: {
      active: Number(subscription.active ?? 0),
      trial: Number(subscription.trial ?? 0),
      pastDue: Number(subscription.past_due ?? 0),
      cancelled: Number(subscription.cancelled ?? 0),
      expired: Number(subscription.expired ?? 0),
      refunded: Number(subscription.refunded ?? 0),
    },
    entitlements: {
      active: Number(entitlement.active ?? 0),
      expired: Number(entitlement.expired ?? 0),
      revoked: Number(entitlement.revoked ?? 0),
    },
  };
}

async function listProducts(sql: AdminSql) {
  const rows = await sql`
    select p.id, p.code, p.display_name, p.status,
           count(distinct pl.id)::integer as plan_count
    from commerce.products p
    left join commerce.plans pl on pl.product_id = p.id
    group by p.id, p.code, p.display_name, p.status
    order by p.display_name asc, p.code asc
    limit 100
  `;
  return rows.map((row) => ({
    id: String(row.id),
    code: String(row.code),
    name: String(row.display_name),
    status: String(row.status),
    planCount: Number(row.plan_count ?? 0),
  }));
}

async function getPlanDistribution(sql: AdminSql, product: string | null) {
  const rows = await sql`
    select pl.id as plan_id,
           p.code as product_code,
           p.display_name as product_name,
           pl.code as plan_code,
           pl.display_name as plan_name,
           pl.status as plan_status,
           count(s.id)::integer as subscriptions,
           count(s.id) filter (where s.status in ('Trial','Active','PastDue'))::integer
             as active_subscriptions
    from commerce.plans pl
    join commerce.products p on p.id = pl.product_id
    left join commerce.subscriptions s on s.plan_id = pl.id
    where (${product}::text is null or p.code = ${product})
    group by pl.id, p.code, p.display_name, pl.code, pl.display_name, pl.status
    order by active_subscriptions desc, subscriptions desc, p.display_name, pl.display_name
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map(
    (row): CommercePlanDistributionRow => ({
      planId: String(row.plan_id),
      productCode: String(row.product_code),
      productName: String(row.product_name),
      planCode: String(row.plan_code),
      planName: String(row.plan_name),
      planStatus: String(row.plan_status),
      subscriptions: Number(row.subscriptions ?? 0),
      activeSubscriptions: Number(row.active_subscriptions ?? 0),
    }),
  );
}

async function getEntitlementCoverage(sql: AdminSql, product: string | null) {
  const rows = await sql`
    select f.code as feature_code,
           count(distinct e.id) filter (
             where e.status = 'Active'
               and e.starts_at_utc <= now()
               and (e.expires_at_utc is null or e.expires_at_utc > now())
           )::integer as active,
           count(distinct e.id) filter (
             where e.status = 'Expired'
                or (
                  e.status = 'Active'
                  and e.expires_at_utc is not null
                  and e.expires_at_utc <= now()
                )
           )::integer as expired,
           count(distinct e.id) filter (where e.status = 'Revoked')::integer as revoked
    from commerce.features f
    left join commerce.entitlements e on e.feature_id = f.id
    where ${product}::text is null
       or exists (
         select 1
         from commerce.product_features pf
         join commerce.products p on p.id = pf.product_id
         where pf.feature_id = f.id
           and p.code = ${product}
       )
    group by f.id, f.code
    order by active desc, f.code asc
    limit 100
  `;
  return (rows as unknown as Record<string, unknown>[]).map(
    (row): CommerceEntitlementCoverageRow => ({
      featureCode: String(row.feature_code),
      active: Number(row.active ?? 0),
      expired: Number(row.expired ?? 0),
      revoked: Number(row.revoked ?? 0),
    }),
  );
}

async function getRenewalHighlights(sql: AdminSql, product: string | null) {
  const rows = await sql`
    select s.id as subscription_id,
           p.code as product_code,
           pl.code as plan_code,
           pl.display_name as plan_name,
           s.status,
           s.current_period_end_utc
    from commerce.subscriptions s
    join commerce.products p on p.id = s.product_id
    join commerce.plans pl on pl.id = s.plan_id
    where s.status in ('Trial','Active','PastDue')
      and s.current_period_end_utc is not null
      and (${product}::text is null or p.code = ${product})
    order by s.current_period_end_utc asc, s.id asc
    limit 12
  `;
  return (rows as unknown as Record<string, unknown>[]).map(
    (row): CommerceRenewalHighlight => ({
      subscriptionId: String(row.subscription_id),
      productCode: String(row.product_code),
      planCode: String(row.plan_code),
      planName: String(row.plan_name),
      status: String(row.status),
      currentPeriodEndUtc: iso(row.current_period_end_utc),
    }),
  );
}

async function getEntitlementExpiryHighlights(
  sql: AdminSql,
  product: string | null,
) {
  const rows = await sql`
    select e.id as entitlement_id,
           f.code as feature_code,
           e.source,
           e.expires_at_utc
    from commerce.entitlements e
    join commerce.features f on f.id = e.feature_id
    where e.status = 'Active'
      and e.starts_at_utc <= now()
      and e.expires_at_utc is not null
      and e.expires_at_utc > now()
      and (
        ${product}::text is null
        or exists (
          select 1
          from commerce.product_features pf
          join commerce.products p on p.id = pf.product_id
          where pf.feature_id = e.feature_id
            and p.code = ${product}
        )
      )
    order by e.expires_at_utc asc, e.id asc
    limit 12
  `;
  return (rows as unknown as Record<string, unknown>[]).map(
    (row): CommerceEntitlementExpiryHighlight => ({
      entitlementId: String(row.entitlement_id),
      featureCode: String(row.feature_code),
      source: String(row.source),
      expiresAtUtc: iso(row.expires_at_utc),
    }),
  );
}

async function listSubscriptions(sql: AdminSql, query: CommerceOverviewQuery) {
  const countRows = await sql`
    select count(*)::integer as total
    from commerce.subscriptions s
    join commerce.products p on p.id = s.product_id
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.status}::text is null or s.status = ${query.status})
  `;

  const rows = await sql`
    select s.id as subscription_id,
           p.code as product_code,
           p.display_name as product_name,
           pl.id as plan_id,
           pl.code as plan_code,
           pl.display_name as plan_name,
           s.status,
           s.starts_at_utc,
           s.current_period_end_utc,
           s.cancelled_at_utc
    from commerce.subscriptions s
    join commerce.products p on p.id = s.product_id
    join commerce.plans pl on pl.id = s.plan_id
    where (${query.product}::text is null or p.code = ${query.product})
      and (${query.status}::text is null or s.status = ${query.status})
    order by s.updated_at_utc desc, s.id desc
    limit ${query.pageSize} offset ${query.offset}
  `;

  return {
    items: (rows as unknown as Record<string, unknown>[]).map(
      (row): CommerceSubscriptionRow => ({
        subscriptionId: String(row.subscription_id),
        productCode: String(row.product_code),
        productName: String(row.product_name),
        planId: String(row.plan_id),
        planCode: String(row.plan_code),
        planName: String(row.plan_name),
        status: String(row.status),
        startsAtUtc: iso(row.starts_at_utc),
        currentPeriodEndUtc: nullableIso(row.current_period_end_utc),
        cancelledAtUtc: nullableIso(row.cancelled_at_utc),
      }),
    ),
    total: Number(countRows[0]?.total ?? 0),
  };
}

export function createCommerceOverviewStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async getOverview(query: CommerceOverviewQuery) {
      const [
        summary,
        products,
        planDistribution,
        entitlementCoverage,
        renewals,
        expiries,
        subscriptions,
      ] = await Promise.all([
        getSummary(sql, query.product),
        listProducts(sql),
        getPlanDistribution(sql, query.product),
        getEntitlementCoverage(sql, query.product),
        getRenewalHighlights(sql, query.product),
        getEntitlementExpiryHighlights(sql, query.product),
        listSubscriptions(sql, query),
      ]);

      return {
        summary,
        products,
        planDistribution,
        entitlementCoverage,
        renewalHighlights: renewals,
        entitlementExpiryHighlights: expiries,
        subscriptions,
      };
    },
  };
}
