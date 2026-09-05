import type { AdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export type GrowthWindow =
  | "daily"
  | "weekly"
  | "monthly"
  | "quarterly"
  | "yearly";
export type GrowthMetricState = "ready" | "partial" | "unavailable";
export type GrowthMetricAvailability =
  | "ready"
  | "partial"
  | "not_enough_data"
  | "not_instrumented"
  | "delayed"
  | "unavailable";

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
  availability?: GrowthMetricAvailability;
  value: number | string | null;
  unit: "count" | "rate" | "minor_currency";
  source: string;
  freshness: { status: GrowthMetricState; asOfUtc: string };
  numerator?: number | null;
  denominator?: number | null;
  reason?: string;
};

type ActiveUserAggregate = {
  definitionVersion: number;
  firstEventAtUtc: string | null;
  latestEventAtUtc: string | null;
  dayStarted: boolean;
  instrumentedByDayEnd: boolean;
  dauCoverageComplete: boolean;
  wauCoverageComplete: boolean;
  mauCoverageComplete: boolean;
  dau: number;
  wau: number;
  mau: number;
  newDau: number;
  returningDau: number;
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
const ACTIVE_SOURCE = "analytics.product_activity_events / app_opened v1";

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
  const rawWindow = (
    url.searchParams.get("window")?.trim().toLowerCase() || "monthly"
  ) as GrowthWindow;
  if (!WINDOWS.has(rawWindow)) {
    throw new ApiError(
      400,
      "growth_window_invalid",
      "Unsupported growth window.",
    );
  }
  const product = url.searchParams.get("product")?.trim().toLowerCase() ||
    null;
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
  availability: GrowthMetricAvailability = "unavailable",
): GrowthMetric {
  return metric({
    key,
    stage,
    definitionVersion: 1,
    state: "unavailable",
    availability,
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
  const previousFrom = new Date(
    previousTo.getTime() - (days - 1) * 86_400_000,
  );
  return {
    from: previousFrom.toISOString().slice(0, 10),
    to: previousTo.toISOString().slice(0, 10),
  };
}

function number(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function boolean(value: unknown): boolean {
  return value === true || value === "true";
}

async function activeUsers(
  sql: AdminSql,
  query: GrowthAnalyticsQuery,
): Promise<ActiveUserAggregate> {
  const rows = await sql`
    select *
    from admin.read_growth_active_user_metrics_v1(
      ${query.to}::date,
      ${query.product}::varchar
    )
  `;
  const row = rows[0] ?? {};
  return {
    definitionVersion: number(row.definition_version) || 1,
    firstEventAtUtc: row.first_event_at_utc?.toString() ?? null,
    latestEventAtUtc: row.latest_event_at_utc?.toString() ?? null,
    dayStarted: boolean(row.day_started),
    instrumentedByDayEnd: boolean(row.instrumented_by_day_end),
    dauCoverageComplete: boolean(row.dau_coverage_complete),
    wauCoverageComplete: boolean(row.wau_coverage_complete),
    mauCoverageComplete: boolean(row.mau_coverage_complete),
    dau: number(row.dau),
    wau: number(row.wau),
    mau: number(row.mau),
    newDau: number(row.new_dau),
    returningDau: number(row.returning_dau),
  };
}

function activityCountMetric(
  key: "dau" | "wau" | "mau" | "new_dau" | "returning_dau",
  value: number,
  aggregate: ActiveUserAggregate,
  coverageComplete: boolean,
): GrowthMetric {
  if (!aggregate.dayStarted) {
    return unavailable(
      key,
      "engagement",
      "count",
      "The selected activity day has not started yet in Asia/Tehran.",
      "not_enough_data",
    );
  }
  if (!aggregate.instrumentedByDayEnd) {
    return unavailable(
      key,
      "engagement",
      "count",
      "No canonical app_opened coverage exists for the selected activity day.",
      "not_instrumented",
    );
  }

  const state: GrowthMetricState = coverageComplete ? "ready" : "partial";
  return metric({
    key,
    stage: "engagement",
    definitionVersion: aggregate.definitionVersion,
    state,
    availability: state,
    value,
    unit: "count",
    source: ACTIVE_SOURCE,
    reason: coverageComplete
      ? undefined
      : "Canonical app_opened instrumentation began inside this metric window; the count is a partial lower bound and earlier activity is not fabricated.",
  });
}

function stickinessMetric(
  key: "dau_mau_stickiness" | "wau_mau_stickiness",
  numeratorMetric: GrowthMetric,
  denominatorMetric: GrowthMetric,
): GrowthMetric {
  if (
    numeratorMetric.value === null ||
    denominatorMetric.value === null ||
    typeof numeratorMetric.value !== "number" ||
    typeof denominatorMetric.value !== "number"
  ) {
    return unavailable(
      key,
      "engagement",
      "rate",
      "Stickiness requires both canonical numerator and MAU denominator coverage.",
      numeratorMetric.availability === "not_instrumented" ||
        denominatorMetric.availability === "not_instrumented"
        ? "not_instrumented"
        : "unavailable",
    );
  }
  if (denominatorMetric.value <= 0) {
    return unavailable(
      key,
      "engagement",
      "rate",
      "Stickiness is not meaningful while the covered MAU denominator is zero.",
      "not_enough_data",
    );
  }
  const state: GrowthMetricState =
    numeratorMetric.state === "ready" && denominatorMetric.state === "ready"
      ? "ready"
      : "partial";
  return metric({
    key,
    stage: "engagement",
    definitionVersion: 1,
    state,
    availability: state,
    value:
      Math.round((numeratorMetric.value / denominatorMetric.value) * 10_000) /
      10_000,
    unit: "rate",
    source: ACTIVE_SOURCE,
    numerator: numeratorMetric.value,
    denominator: denominatorMetric.value,
    reason: state === "partial"
      ? "One or both activity windows began before canonical instrumentation coverage."
      : undefined,
  });
}

async function snapshot(
  sql: AdminSql,
  query: GrowthAnalyticsQuery,
): Promise<GrowthMetric[]> {
  const [rows, activity] = await Promise.all([
    sql`
      with account_facts as (
        select count(*)::integer as created
        from identity.accounts a
        where a.status <> 'Deleted'
          and a.created_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran')
          and a.created_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran')
      ), enrollment_facts as (
        select count(distinct e.account_id)::integer as enrolled,
               count(distinct e.account_id) filter (
                 where e.last_active_at_utc is not null
                   and e.last_active_at_utc >= e.enrolled_at_utc
               )::integer as activated
        from ecosystem.app_enrollments e
        join ecosystem.applications app on app.id = e.application_id
        where app.status = 'Active'
          and e.enrolled_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran')
          and e.enrolled_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran')
          and (${query.product}::text is null or lower(app.code) = ${query.product})
      )
      select account_facts.created, enrollment_facts.enrolled, enrollment_facts.activated
      from account_facts, enrollment_facts
    `,
    activeUsers(sql, query),
  ]);
  const row = rows[0] ?? {};
  const created = number(row.created);
  const enrolled = number(row.enrolled);
  const activated = number(row.activated);
  const activationRate = enrolled > 0
    ? Math.round((activated / enrolled) * 10_000) / 10_000
    : null;

  const dau = activityCountMetric(
    "dau",
    activity.dau,
    activity,
    activity.dauCoverageComplete,
  );
  const wau = activityCountMetric(
    "wau",
    activity.wau,
    activity,
    activity.wauCoverageComplete,
  );
  const mau = activityCountMetric(
    "mau",
    activity.mau,
    activity,
    activity.mauCoverageComplete,
  );
  const newDau = activityCountMetric(
    "new_dau",
    activity.newDau,
    activity,
    activity.dauCoverageComplete,
  );
  const returningDau = activityCountMetric(
    "returning_dau",
    activity.returningDau,
    activity,
    activity.dauCoverageComplete,
  );

  return [
    metric({
      key: "accounts_created",
      stage: "acquisition",
      definitionVersion: 1,
      state: query.product ? "unavailable" : "partial",
      availability: query.product ? "unavailable" : "partial",
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
      availability: "ready",
      value: enrolled,
      unit: "count",
      source: "ecosystem.app_enrollments.enrolled_at_utc",
    }),
    metric({
      key: "activation_observed_rate",
      stage: "activation",
      definitionVersion: 1,
      state: "partial",
      availability: "partial",
      value: activationRate,
      unit: "rate",
      source: "ecosystem.app_enrollments.last_active_at_utc",
      numerator: activated,
      denominator: enrolled,
      reason: "Current activity snapshot; not canonical app-open history.",
    }),
    dau,
    wau,
    mau,
    newDau,
    returningDau,
    stickinessMetric("dau_mau_stickiness", dau, mau),
    stickinessMetric("wau_mau_stickiness", wau, mau),
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
      const [currentMetrics, previousMetrics, currentCoverage] = await Promise.all([
        snapshot(sql, query),
        snapshot(sql, { ...query, ...previous }),
        activeUsers(sql, query),
      ]);
      return {
        definitionVersion: 2,
        query,
        current: currentMetrics,
        previous: { range: previous, metrics: previousMetrics },
        policy: {
          accountScoped: [
            "accounts_created",
            "dau",
            "wau",
            "mau",
            "new_dau",
            "returning_dau",
            "dau_mau_stickiness",
            "wau_mau_stickiness",
            "paid_conversion",
            "ltv",
            "cac",
            "renewal_rate",
            "churn_rate",
          ],
          personScoped: [],
          noFabrication: true,
        },
        activityCoverage: {
          event: "app_opened",
          definitionVersion: currentCoverage.definitionVersion,
          scope: query.product ?? "company",
          unit: "distinct_account",
          firstEventAtUtc: currentCoverage.firstEventAtUtc,
          latestEventAtUtc: currentCoverage.latestEventAtUtc,
          timezone: "Asia/Tehran",
          note:
            "Company scope deduplicates the same account across products. Historical periods before first canonical coverage are never zero-filled.",
        },
        freshness: {
          asOfUtc: new Date().toISOString(),
          timezone: "Asia/Tehran",
        },
      };
    },
  };
}
