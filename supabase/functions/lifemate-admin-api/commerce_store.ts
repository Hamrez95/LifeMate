import type { AdminSql } from "./database_client.ts";
import type {
  CommerceDashboardQuery,
  CommerceSubscriptionStatus,
} from "./commerce.ts";

type Row = Record<string, unknown>;

export type CommerceSubscriptionItem = {
  subscriptionId: string;
  customerAccountId: string;
  beneficiaryPersonId: string | null;
  productCode: string;
  productName: string;
  planCode: string;
  planName: string;
  provider: string;
  status: CommerceSubscriptionStatus;
  startsAtUtc: string;
  currentPeriodEndUtc: string | null;
  cancelledAtUtc: string | null;
};

export type CommercePlanDistributionItem = {
  productCode: string;
  planCode: string;
  planName: string;
  subscriptionCount: number;
};

export type CommerceEntitlementCoverageItem = {
  featureCode: string;
  activeCount: number;
  expiringSoonCount: number;
};

export type CommerceRenewalHighlight = {
  subscriptionId: string;
  customerAccountId: string;
  productCode: string;
  planCode: string;
  status: CommerceSubscriptionStatus;
  currentPeriodEndUtc: string;
  daysRemaining: number;
};

export type CommerceDashboardData = {
  summary: Record<CommerceSubscriptionStatus, number> & { total: number };
  products: Array<{ code: string; name: string }>;
  plans: Array<{ productCode: string; code: string; name: string }>;
  planDistribution: CommercePlanDistributionItem[];
  entitlementCoverage: CommerceEntitlementCoverageItem[];
  renewalHighlights: CommerceRenewalHighlight[];
  subscriptions: CommerceSubscriptionItem[];
  total: number;
};

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function nullableIso(value: unknown): string | null {
  return value == null ? null : iso(value);
}

function nullableString(value: unknown): string | null {
  return value == null ? null : String(value);
}

function number(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function baseSummary(): CommerceDashboardData["summary"] {
  return {
    total: 0,
    Trial: 0,
    Active: 0,
    PastDue: 0,
    Cancelled: 0,
    Expired: 0,
    Refunded: 0,
  };
}

export async function getCommerceDashboard(
  sql: AdminSql,
  query: CommerceDashboardQuery,
): Promise<CommerceDashboardData> {
  const [summaryRows, productsRows, plansRows, distributionRows, entitlementRows, renewalRows, countRows, subscriptionRows] =
    await Promise.all([
      sql`
        select s.status, count(*)::integer as count
        from commerce.subscriptions s
        join commerce.products p on p.id=s.product_id
        join commerce.plans pl on pl.id=s.plan_id
        where (${query.product}::text is null or lower(p.code)=${query.product}::text)
          and (${query.plan}::text is null or lower(pl.code)=${query.plan}::text)
        group by s.status
      `,
      sql`
        select code, display_name
        from commerce.products
        where status='Active'
        order by display_name, code
        limit 100
      `,
      sql`
        select p.code as product_code, pl.code, pl.display_name
        from commerce.plans pl
        join commerce.products p on p.id=pl.product_id
        where pl.status='Active' and p.status='Active'
          and (${query.product}::text is null or lower(p.code)=${query.product}::text)
        order by p.code, pl.display_name, pl.code
        limit 250
      `,
      sql`
        select p.code as product_code, pl.code as plan_code, pl.display_name as plan_name,
               count(s.id)::integer as subscription_count
        from commerce.plans pl
        join commerce.products p on p.id=pl.product_id
        left join commerce.subscriptions s on s.plan_id=pl.id
        where p.status='Active'
          and (${query.product}::text is null or lower(p.code)=${query.product}::text)
          and (${query.plan}::text is null or lower(pl.code)=${query.plan}::text)
        group by p.code, pl.code, pl.display_name
        order by subscription_count desc, p.code, pl.code
        limit 100
      `,
      sql`
        select f.code as feature_code,
               count(*) filter (where e.status='Active' and (e.expires_at_utc is null or e.expires_at_utc > now()))::integer as active_count,
               count(*) filter (
                 where e.status='Active'
                   and e.expires_at_utc > now()
                   and e.expires_at_utc <= now() + interval '30 days'
               )::integer as expiring_soon_count
        from commerce.features f
        left join commerce.entitlements e on e.feature_id=f.id
        left join commerce.product_features pf on pf.feature_id=f.id
        left join commerce.products p on p.id=pf.product_id
        where (${query.product}::text is null or lower(p.code)=${query.product}::text)
        group by f.code
        order by active_count desc, f.code
        limit 100
      `,
      sql`
        select s.id as subscription_id,
               coalesce(s.owner_account_id, s.payer_account_id) as customer_account_id,
               p.code as product_code,
               pl.code as plan_code,
               s.status,
               s.current_period_end_utc,
               greatest(0, floor(extract(epoch from (s.current_period_end_utc-now()))/86400))::integer as days_remaining
        from commerce.subscriptions s
        join commerce.products p on p.id=s.product_id
        join commerce.plans pl on pl.id=s.plan_id
        where s.status in ('Trial','Active','PastDue')
          and s.current_period_end_utc is not null
          and s.current_period_end_utc >= now()
          and s.current_period_end_utc <= now() + interval '30 days'
          and (${query.product}::text is null or lower(p.code)=${query.product}::text)
          and (${query.plan}::text is null or lower(pl.code)=${query.plan}::text)
        order by s.current_period_end_utc asc, s.id asc
        limit 20
      `,
      sql`
        select count(*)::integer as total
        from commerce.subscriptions s
        join commerce.products p on p.id=s.product_id
        join commerce.plans pl on pl.id=s.plan_id
        where (${query.product}::text is null or lower(p.code)=${query.product}::text)
          and (${query.plan}::text is null or lower(pl.code)=${query.plan}::text)
          and (${query.status}::text is null or s.status=${query.status}::varchar)
      `,
      sql`
        select s.id as subscription_id,
               coalesce(s.owner_account_id, s.payer_account_id) as customer_account_id,
               s.beneficiary_person_id,
               p.code as product_code,
               p.display_name as product_name,
               pl.code as plan_code,
               pl.display_name as plan_name,
               s.provider,
               s.status,
               s.starts_at_utc,
               s.current_period_end_utc,
               s.cancelled_at_utc
        from commerce.subscriptions s
        join commerce.products p on p.id=s.product_id
        join commerce.plans pl on pl.id=s.plan_id
        where (${query.product}::text is null or lower(p.code)=${query.product}::text)
          and (${query.plan}::text is null or lower(pl.code)=${query.plan}::text)
          and (${query.status}::text is null or s.status=${query.status}::varchar)
        order by s.created_at_utc desc, s.id desc
        limit ${query.pageSize} offset ${query.offset}
      `,
    ]);

  const summary = baseSummary();
  for (const raw of summaryRows as unknown as Row[]) {
    const status = String(raw.status) as CommerceSubscriptionStatus;
    if (status in summary) {
      const count = number(raw.count);
      summary[status] = count;
      summary.total += count;
    }
  }

  return {
    summary,
    products: (productsRows as unknown as Row[]).map((row) => ({
      code: String(row.code),
      name: String(row.display_name),
    })),
    plans: (plansRows as unknown as Row[]).map((row) => ({
      productCode: String(row.product_code),
      code: String(row.code),
      name: String(row.display_name),
    })),
    planDistribution: (distributionRows as unknown as Row[]).map((row) => ({
      productCode: String(row.product_code),
      planCode: String(row.plan_code),
      planName: String(row.plan_name),
      subscriptionCount: number(row.subscription_count),
    })),
    entitlementCoverage: (entitlementRows as unknown as Row[]).map((row) => ({
      featureCode: String(row.feature_code),
      activeCount: number(row.active_count),
      expiringSoonCount: number(row.expiring_soon_count),
    })),
    renewalHighlights: (renewalRows as unknown as Row[]).map((row) => ({
      subscriptionId: String(row.subscription_id),
      customerAccountId: String(row.customer_account_id),
      productCode: String(row.product_code),
      planCode: String(row.plan_code),
      status: String(row.status) as CommerceSubscriptionStatus,
      currentPeriodEndUtc: iso(row.current_period_end_utc),
      daysRemaining: number(row.days_remaining),
    })),
    subscriptions: (subscriptionRows as unknown as Row[]).map((row) => ({
      subscriptionId: String(row.subscription_id),
      customerAccountId: String(row.customer_account_id),
      beneficiaryPersonId: nullableString(row.beneficiary_person_id),
      productCode: String(row.product_code),
      productName: String(row.product_name),
      planCode: String(row.plan_code),
      planName: String(row.plan_name),
      provider: String(row.provider),
      status: String(row.status) as CommerceSubscriptionStatus,
      startsAtUtc: iso(row.starts_at_utc),
      currentPeriodEndUtc: nullableIso(row.current_period_end_utc),
      cancelledAtUtc: nullableIso(row.cancelled_at_utc),
    })),
    total: number(countRows[0]?.total),
  };
}
