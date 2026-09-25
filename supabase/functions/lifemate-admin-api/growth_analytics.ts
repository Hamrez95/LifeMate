import type { AdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export type GrowthWindow =
  | "daily"
  | "weekly"
  | "monthly"
  | "quarterly"
  | "yearly";
export type GrowthMetricState = "ready" | "partial" | "unavailable";

export type GrowthAnalyticsQuery = {
  from: string;
  to: string;
  window: GrowthWindow;
  product: string | null;
};

export type GrowthMetric = {
  key: string;
  stage:
    | "acquisition"
    | "activation"
    | "engagement"
    | "monetization"
    | "retention";
  definitionVersion: number;
  state: GrowthMetricState;
  value: number | string | null;
  unit: "count" | "rate" | "minor_currency";
  source: string;
  freshness: { status: GrowthMetricState; asOfUtc: string };
  reason?: string;
};

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const PRODUCT = /^[a-z0-9][a-z0-9._:-]{0,63}$/;
const WINDOWS = new Set<GrowthWindow>([
  "daily",
  "weekly",
  "monthly",
  "quarterly",
  "yearly",
]);

function date(value: string | null, field: string): string {
  const normalized = value?.trim() ?? "";
  if (!DATE.test(normalized)) {
    throw new ApiError(
      400,
      "growth_range_invalid",
      `${field} must use YYYY-MM-DD.`,
    );
  }
  const parsed = new Date(`${normalized}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== normalized
  ) {
    throw new ApiError(400, "growth_range_invalid", `${field} is invalid.`);
  }
  return normalized;
}

export function parseGrowthAnalyticsQuery(url: URL): GrowthAnalyticsQuery {
  const from = date(url.searchParams.get("from"), "from");
  const to = date(url.searchParams.get("to"), "to");
  if (from > to) {
    throw new ApiError(
      400,
      "growth_range_invalid",
      "from must not be after to.",
    );
  }
  const rawWindow = (url.searchParams.get("window")?.trim().toLowerCase() ||
    "monthly") as GrowthWindow;
  if (!WINDOWS.has(rawWindow)) {
    throw new ApiError(
      400,
      "growth_window_invalid",
      "Unsupported growth window.",
    );
  }
  const product = url.searchParams.get("product")?.trim().toLowerCase() || null;
  if (product && !PRODUCT.test(product)) {
    throw new ApiError(
      400,
      "growth_product_invalid",
      "Product filter is invalid.",
    );
  }
  return { from, to, window: rawWindow, product };
}

function metric(input: Omit<GrowthMetric, "freshness">): GrowthMetric {
  return {
    ...input,
    freshness: { status: input.state, asOfUtc: new Date().toISOString() },
  };
}

function unavailable(
  key: string,
  stage: GrowthMetric["stage"],
  unit: GrowthMetric["unit"],
  reason: string,
): GrowthMetric {
  return metric({
    key,
    stage,
    definitionVersion: 1,
    state: "unavailable",
    value: null,
    unit,
    source: "canonical fact unavailable",
    reason,
  });
}

export function previousPeriod(
  query: GrowthAnalyticsQuery,
): { from: string; to: string } {
  const from = new Date(`${query.from}T00:00:00.000Z`);
  const to = new Date(`${query.to}T00:00:00.000Z`);
  const days = Math.round((to.getTime() - from.getTime()) / 86_400_000) + 1;
  const previousTo = new Date(from.getTime() - 86_400_000);
  const previousFrom = new Date(previousTo.getTime() - (days - 1) * 86_400_000);
  return {
    from: previousFrom.toISOString().slice(0, 10),
    to: previousTo.toISOString().slice(0, 10),
  };
}

async function snapshot(
  sql: AdminSql,
  query: GrowthAnalyticsQuery,
): Promise<GrowthMetric[]> {
  const rows = await sql`
    with account_facts as (
      select count(*)::integer as created
      from identity.accounts a
      where a.status <> 'Deleted'
        and a.created_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran')
        and a.created_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran')
    ), enrollment_facts as (
      select count(distinct e.account_id)::integer as enrolled,
             count(distinct e.account_id) filter (where e.last_active_at_utc is not null and e.last_active_at_utc >= e.enrolled_at_utc)::integer as activated
      from ecosystem.app_enrollments e
      join ecosystem.applications app on app.id = e.application_id
      where app.status = 'Active'
        and e.enrolled_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran')
        and e.enrolled_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran')
        and (${query.product}::text is null or lower(app.code) = ${query.product})
    )
    select account_facts.created, enrollment_facts.enrolled, enrollment_facts.activated
    from account_facts, enrollment_facts
  `;
  const row = rows[0] ?? {};
  const created = Number(row.created ?? 0);
  const enrolled = Number(row.enrolled ?? 0);
  const activated = Number(row.activated ?? 0);
  const activationRate = enrolled > 0
    ? Math.round((activated / enrolled) * 10_000) / 10_000
    : null;
  return [
    metric({
      key: "accounts_created",
      stage: "acquisition",
      definitionVersion: 1,
      state: query.product ? "unavailable" : "partial",
      value: query.product ? null : created,
      unit: "count",
      source: query.product
        ? "account creation has no canonical product attribution"
        : "identity.accounts.created_at_utc",
      reason: query.product
        ? "Product-filtered acquisition would invent attribution."
        : "Deleted-account history is not reconstructed.",
    }),
    metric({
      key: "enrolled_accounts",
      stage: "activation",
      definitionVersion: 1,
      state: "ready",
      value: enrolled,
      unit: "count",
      source: "ecosystem.app_enrollments.enrolled_at_utc",
    }),
    metric({
      key: "activation_observed_rate",
      stage: "activation",
      definitionVersion: 1,
      state: "partial",
      value: activationRate,
      unit: "rate",
      source: "ecosystem.app_enrollments.last_active_at_utc",
      reason: "Current activity snapshot; not canonical app-open history.",
    }),
    unavailable(
      "dau",
      "engagement",
      "count",
      "Canonical app_opened event history is not instrumented.",
    ),
    unavailable(
      "wau",
      "engagement",
      "count",
      "Canonical app_opened event history is not instrumented.",
    ),
    unavailable(
      "mau",
      "engagement",
      "count",
      "Historical active-user event history is not instrumented.",
    ),
    unavailable(
      "paid_conversion",
      "monetization",
      "rate",
      "A canonical eligible-cohort to successful-payment join is not instrumented.",
    ),
    unavailable(
      "ltv",
      "monetization",
      "minor_currency",
      "LTV is forbidden until canonical cohort revenue and retention history exist.",
    ),
    unavailable(
      "cac",
      "monetization",
      "minor_currency",
      "Canonical acquisition spend attribution is not instrumented.",
    ),
    unavailable(
      "renewal_rate",
      "retention",
      "rate",
      "Canonical renewal-eligibility denominator is not instrumented.",
    ),
    unavailable(
      "churn_rate",
      "retention",
      "rate",
      "Canonical subscription cohort history required for churn is not instrumented.",
    ),
  ];
}

export function createGrowthAnalyticsStore(sql: AdminSql) {
  return {
    async read(query: GrowthAnalyticsQuery) {
      const previous = previousPeriod(query);
      const [currentMetrics, previousMetrics] = await Promise.all([
        snapshot(sql, query),
        snapshot(sql, { ...query, ...previous }),
      ]);
      return {
        definitionVersion: 1,
        query,
        current: currentMetrics,
        previous: { range: previous, metrics: previousMetrics },
        policy: {
          accountScoped: [
            "accounts_created",
            "paid_conversion",
            "ltv",
            "cac",
            "renewal_rate",
            "churn_rate",
          ],
          personScoped: ["dau", "wau", "mau"],
          noFabrication: true,
        },
        freshness: {
          asOfUtc: new Date().toISOString(),
          timezone: "Asia/Tehran",
        },
      };
    },
  };
}
