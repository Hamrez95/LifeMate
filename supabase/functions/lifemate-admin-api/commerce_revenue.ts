import { type AdminSql, getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const CODE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
const CURRENCY = /^[A-Z]{3}$/;

export type CommerceRevenueQuery = {
  from: string | null;
  to: string | null;
  currency: string | null;
  product: string | null;
  plan: string | null;
};

export type RevenueMetricState = "ready" | "partial" | "unavailable";

export type RevenueMetric = {
  name:
    | "mrr"
    | "arr"
    | "arpu"
    | "paid_conversion"
    | "revenue_churn"
    | "refund_amount";
  state: RevenueMetricState;
  value: string | number | null;
  currency: string | null;
  reason: string;
};

export type RevenueCurrencyActual = {
  currency: string;
  succeededAmountMinor: string;
  refundedAmountMinor: string | null;
  succeededTransactions: number;
  refundedTransactions: number | null;
  payingAccounts: number;
};

export type RevenueSeriesPoint = {
  date: string;
  currency: string;
  succeededAmountMinor: string;
  refundedAmountMinor: string | null;
};

type RefundAggregate = { amountMinor: string; transactions: number };

function optionalDate(value: string | null, field: string): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    throw new ApiError(
      400,
      "commerce_revenue_range_invalid",
      `${field} must use YYYY-MM-DD.`,
    );
  }
  const parsed = new Date(`${normalized}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== normalized
  ) {
    throw new ApiError(
      400,
      "commerce_revenue_range_invalid",
      `${field} is invalid.`,
    );
  }
  return normalized;
}

function optionalCode(value: string | null, field: string): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (!CODE.test(normalized)) {
    throw new ApiError(
      400,
      "commerce_revenue_filter_invalid",
      `${field} filter is invalid.`,
    );
  }
  return normalized.toLowerCase();
}

export function parseCommerceRevenueQuery(url: URL): CommerceRevenueQuery {
  const from = optionalDate(url.searchParams.get("from"), "from");
  const to = optionalDate(url.searchParams.get("to"), "to");
  if (from && to && from > to) {
    throw new ApiError(
      400,
      "commerce_revenue_range_invalid",
      "Revenue date range is invalid.",
    );
  }
  const rawCurrency = url.searchParams.get("currency")?.trim().toUpperCase() ??
    "";
  if (rawCurrency && !CURRENCY.test(rawCurrency)) {
    throw new ApiError(
      400,
      "commerce_revenue_currency_invalid",
      "Currency filter must be a three-letter code.",
    );
  }
  return {
    from,
    to,
    currency: rawCurrency || null,
    product: optionalCode(url.searchParams.get("product"), "product"),
    plan: optionalCode(url.searchParams.get("plan"), "plan"),
  };
}

function unavailable(
  name: RevenueMetric["name"],
  reason: string,
  currency: string | null,
): RevenueMetric {
  return { name, state: "unavailable", value: null, currency, reason };
}

export function unsupportedRecurringRevenueMetrics(
  currency: string | null,
): RevenueMetric[] {
  return [
    unavailable(
      "mrr",
      "Canonical subscription billing-allocation history is not instrumented; current plan price × subscriber count is forbidden.",
      currency,
    ),
    unavailable(
      "arr",
      "ARR cannot be derived until canonical MRR and billing-period allocation facts exist.",
      currency,
    ),
    unavailable(
      "arpu",
      "ARPU requires canonical recognized recurring revenue and a period-aligned paying-account denominator.",
      currency,
    ),
    unavailable(
      "paid_conversion",
      "A canonical payment conversion funnel linking eligible cohort to successful payer is not instrumented.",
      currency,
    ),
    unavailable(
      "revenue_churn",
      "Revenue churn requires historical recurring-revenue allocation and cancellation/downsell event semantics.",
      currency,
    ),
  ];
}

async function relationAvailability(sql: AdminSql) {
  const rows = await sql`
    select
      to_regclass('commerce.transactions') is not null as transactions,
      to_regclass('commerce.refund_requests') is not null as refunds
  `;
  return {
    transactions: Boolean(rows[0]?.transactions),
    refunds: Boolean(rows[0]?.refunds),
  };
}

async function actuals(
  sql: AdminSql,
  query: CommerceRevenueQuery,
): Promise<RevenueCurrencyActual[]> {
  const rows = await sql`
    select
      t.currency,
      coalesce(sum(t.amount_minor) filter (where t.normalized_status = 'Succeeded'), 0)::text as succeeded_amount_minor,
      count(*) filter (where t.normalized_status = 'Succeeded')::integer as succeeded_transactions,
      count(distinct t.account_id) filter (
        where t.normalized_status = 'Succeeded' and t.account_id is not null
      )::integer as paying_accounts
    from commerce.transactions t
    join commerce.products product on product.id = t.product_id
    left join commerce.subscriptions subscription on subscription.id = t.subscription_id
    left join commerce.plans plan on plan.id = subscription.plan_id
    where (${query.from}::date is null or t.occurred_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran'))
      and (${query.to}::date is null or t.occurred_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran'))
      and (${query.currency}::text is null or t.currency = ${query.currency})
      and (${query.product}::text is null or lower(product.code) = ${query.product})
      and (${query.plan}::text is null or lower(plan.code) = ${query.plan})
    group by t.currency
    order by t.currency asc
  `;
  return rows.map((row) => ({
    currency: String(row.currency),
    succeededAmountMinor: String(row.succeeded_amount_minor ?? "0"),
    refundedAmountMinor: null,
    succeededTransactions: Number(row.succeeded_transactions ?? 0),
    refundedTransactions: null,
    payingAccounts: Number(row.paying_accounts ?? 0),
  }));
}

async function refundActuals(
  sql: AdminSql,
  query: CommerceRevenueQuery,
): Promise<Map<string, RefundAggregate>> {
  const rows = await sql`
    select
      request.currency,
      coalesce(sum(request.amount_minor) filter (where request.status = 'Succeeded'), 0)::text as refunded_amount_minor,
      count(*) filter (where request.status = 'Succeeded')::integer as refunded_transactions
    from commerce.refund_requests request
    join commerce.transactions t on t.id = request.transaction_id
    join commerce.products product on product.id = t.product_id
    left join commerce.subscriptions subscription on subscription.id = t.subscription_id
    left join commerce.plans plan on plan.id = subscription.plan_id
    where (${query.from}::date is null or request.requested_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran'))
      and (${query.to}::date is null or request.requested_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran'))
      and (${query.currency}::text is null or request.currency = ${query.currency})
      and (${query.product}::text is null or lower(product.code) = ${query.product})
      and (${query.plan}::text is null or lower(plan.code) = ${query.plan})
    group by request.currency
    order by request.currency asc
  `;
  return new Map(
    rows.map((row) => [
      String(row.currency),
      {
        amountMinor: String(row.refunded_amount_minor ?? "0"),
        transactions: Number(row.refunded_transactions ?? 0),
      },
    ]),
  );
}

async function transactionSeries(
  sql: AdminSql,
  query: CommerceRevenueQuery,
): Promise<RevenueSeriesPoint[]> {
  const rows = await sql`
    select
      (t.occurred_at_utc at time zone 'Asia/Tehran')::date::text as day,
      t.currency,
      coalesce(sum(t.amount_minor) filter (where t.normalized_status = 'Succeeded'), 0)::text as succeeded_amount_minor
    from commerce.transactions t
    join commerce.products product on product.id = t.product_id
    left join commerce.subscriptions subscription on subscription.id = t.subscription_id
    left join commerce.plans plan on plan.id = subscription.plan_id
    where (${query.from}::date is null or t.occurred_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran'))
      and (${query.to}::date is null or t.occurred_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran'))
      and (${query.currency}::text is null or t.currency = ${query.currency})
      and (${query.product}::text is null or lower(product.code) = ${query.product})
      and (${query.plan}::text is null or lower(plan.code) = ${query.plan})
    group by 1, t.currency
    order by 1 asc, t.currency asc
    limit 4000
  `;
  return rows.map((row) => ({
    date: String(row.day),
    currency: String(row.currency),
    succeededAmountMinor: String(row.succeeded_amount_minor ?? "0"),
    refundedAmountMinor: null,
  }));
}

async function refundSeries(
  sql: AdminSql,
  query: CommerceRevenueQuery,
): Promise<Map<string, string>> {
  const rows = await sql`
    select
      (request.requested_at_utc at time zone 'Asia/Tehran')::date::text as day,
      request.currency,
      coalesce(sum(request.amount_minor) filter (where request.status = 'Succeeded'), 0)::text as refunded_amount_minor
    from commerce.refund_requests request
    join commerce.transactions t on t.id = request.transaction_id
    join commerce.products product on product.id = t.product_id
    left join commerce.subscriptions subscription on subscription.id = t.subscription_id
    left join commerce.plans plan on plan.id = subscription.plan_id
    where (${query.from}::date is null or request.requested_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran'))
      and (${query.to}::date is null or request.requested_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran'))
      and (${query.currency}::text is null or request.currency = ${query.currency})
      and (${query.product}::text is null or lower(product.code) = ${query.product})
      and (${query.plan}::text is null or lower(plan.code) = ${query.plan})
    group by 1, request.currency
    order by 1 asc, request.currency asc
    limit 4000
  `;
  return new Map(
    rows.map((row) => [
      `${String(row.day)}:${String(row.currency)}`,
      String(row.refunded_amount_minor ?? "0"),
    ]),
  );
}

export function createCommerceRevenueStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async read(query: CommerceRevenueQuery) {
      const availability = await relationAvailability(sql);
      const recurring = unsupportedRecurringRevenueMetrics(query.currency);
      if (!availability.transactions) {
        return {
          query,
          kpis: [
            ...recurring,
            unavailable(
              "refund_amount",
              "Canonical commerce transaction/refund ledger is not deployed in this database.",
              query.currency,
            ),
          ],
          actualByCurrency: [] as RevenueCurrencyActual[],
          series: [] as RevenueSeriesPoint[],
          source: {
            state: "unavailable" as const,
            ledger: "commerce.transactions",
            refundLedger: "commerce.refund_requests",
            note:
              "No revenue amount is reconstructed from prices or subscription counts.",
          },
          freshness: {
            status: "unavailable" as const,
            asOfUtc: new Date().toISOString(),
          },
        };
      }

      const [values, baseSeries] = await Promise.all([
        actuals(sql, query),
        transactionSeries(sql, query),
      ]);
      const refundByCurrency: Map<string, RefundAggregate> =
        availability.refunds ? await refundActuals(sql, query) : new Map();
      const refundByDay = availability.refunds
        ? await refundSeries(sql, query)
        : new Map<string, string>();
      const actualByCurrency = values.map((item) => {
        const refund = refundByCurrency.get(item.currency);
        return {
          ...item,
          refundedAmountMinor: availability.refunds
            ? (refund?.amountMinor ?? "0")
            : null,
          refundedTransactions: availability.refunds
            ? (refund?.transactions ?? 0)
            : null,
        };
      });
      const series = baseSeries.map((point) => ({
        ...point,
        refundedAmountMinor: availability.refunds
          ? (refundByDay.get(`${point.date}:${point.currency}`) ?? "0")
          : null,
      }));

      const selectedRefund = query.currency
        ? actualByCurrency.find((item) => item.currency === query.currency)
          ?.refundedAmountMinor ?? "0"
        : null;
      const refundMetric: RevenueMetric = availability.refunds
        ? query.currency
          ? {
            name: "refund_amount",
            state: "ready",
            value: selectedRefund,
            currency: query.currency,
            reason:
              "Succeeded human-review refund workflow amounts only; integer minor units.",
          }
          : {
            name: "refund_amount",
            state: "partial",
            value: null,
            currency: null,
            reason:
              "Refund amounts are available only as the per-currency breakdown below; no FX aggregation is performed.",
          }
        : unavailable(
          "refund_amount",
          "Refund workflow ledger is not deployed; transaction status alone is not treated as a refund amount.",
          query.currency,
        );

      return {
        query,
        kpis: [...recurring, refundMetric],
        actualByCurrency,
        series,
        source: {
          state: "partial" as const,
          ledger: "commerce.transactions",
          refundLedger: availability.refunds
            ? "commerce.refund_requests"
            : null,
          note:
            "Actual successful transaction/refund facts only. MRR/ARR/ARPU/churn/conversion remain unavailable until their canonical semantics are instrumented.",
        },
        freshness: {
          status: "partial" as const,
          asOfUtc: new Date().toISOString(),
        },
      };
    },
  };
}
