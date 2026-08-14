import { KPI_DEFINITIONS } from "./analytics_catalog.ts";
import type { AdminSql } from "./database_client.ts";
import { type AnalyticsKpiQuery, tehranToday } from "./analytics_kpis.ts";

export type KpiValueState = "ready" | "partial" | "unavailable";

export type KpiSeriesPoint = {
  date: string;
  value: number;
};

export type KpiValue = {
  name: string;
  definitionVersion: number;
  state: KpiValueState;
  value: number | null;
  numerator: number | null;
  denominator: number | null;
  source: string;
  freshness: {
    status: "fresh" | "partial" | "unavailable";
    asOfUtc: string;
  };
  series?: KpiSeriesPoint[];
  reason?: string;
};

function definitionVersion(name: string): number {
  return KPI_DEFINITIONS.find((definition) => definition.name === name)
    ?.definitionVersion ?? 1;
}

function unavailable(name: string, reason: string): KpiValue {
  return {
    name,
    definitionVersion: definitionVersion(name),
    state: "unavailable",
    value: null,
    numerator: null,
    denominator: null,
    source: "canonical source not yet instrumented",
    freshness: {
      status: "unavailable",
      asOfUtc: new Date().toISOString(),
    },
    reason,
  };
}

async function accountsCreated(
  sql: AdminSql,
  query: AnalyticsKpiQuery,
): Promise<KpiValue> {
  if (query.product) {
    return unavailable(
      "accounts_created",
      "Taxonomy v1 does not attribute account creation to a product, so a product-filtered count would be misleading.",
    );
  }

  const countRows = await sql`
    select count(*)::integer as total
    from identity.accounts
    where status <> 'Deleted'
      and created_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran')
      and created_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran')
  `;
  const seriesRows = await sql`
    with days as (
      select generate_series(
        ${query.from}::date,
        ${query.to}::date,
        interval '1 day'
      )::date as day
    ), created as (
      select (created_at_utc at time zone 'Asia/Tehran')::date as day,
             count(*)::integer as total
      from identity.accounts
      where status <> 'Deleted'
        and created_at_utc >= (${query.from}::date::timestamp at time zone 'Asia/Tehran')
        and created_at_utc < ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran')
      group by 1
    )
    select days.day::text as day, coalesce(created.total, 0)::integer as total
    from days
    left join created using (day)
    order by days.day asc
  `;

  const total = Number(countRows[0]?.total ?? 0);
  return {
    name: "accounts_created",
    definitionVersion: definitionVersion("accounts_created"),
    state: "partial",
    value: total,
    numerator: total,
    denominator: null,
    source:
      "identity.accounts.created_at_utc; excludes accounts currently marked Deleted",
    freshness: {
      status: "partial",
      asOfUtc: new Date().toISOString(),
    },
    series: seriesRows.map((row) => ({
      date: String(row.day),
      value: Number(row.total ?? 0),
    })),
    reason:
      "This is a truthful relational fallback, not a fabricated event backfill. Deleted-account history is not reconstructed.",
  };
}

async function monthlyActiveAccounts(
  sql: AdminSql,
  query: AnalyticsKpiQuery,
): Promise<KpiValue> {
  if (query.to !== tehranToday()) {
    return unavailable(
      "monthly_active_accounts",
      "Historical MAU cannot be reconstructed from the current last-active snapshot without canonical app_opened history.",
    );
  }

  const rows = await sql`
    select count(distinct enrollment.account_id)::integer as total
    from ecosystem.app_enrollments enrollment
    join ecosystem.applications application
      on application.id = enrollment.application_id
    join identity.accounts account
      on account.id = enrollment.account_id
    where enrollment.status = 'Active'
      and application.status = 'Active'
      and account.status = 'Active'
      and (${query.product}::text is null or lower(application.code) = ${query.product})
      and enrollment.last_active_at_utc is not null
      and enrollment.last_active_at_utc >= (
        ((${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran') - interval '30 days'
      )
      and enrollment.last_active_at_utc < (
        (${query.to}::date + 1)::timestamp at time zone 'Asia/Tehran'
      )
  `;
  const total = Number(rows[0]?.total ?? 0);
  return {
    name: "monthly_active_accounts",
    definitionVersion: definitionVersion("monthly_active_accounts"),
    state: "partial",
    value: total,
    numerator: total,
    denominator: null,
    source: "ecosystem.app_enrollments.last_active_at_utc current snapshot",
    freshness: {
      status: "partial",
      asOfUtc: new Date().toISOString(),
    },
    reason:
      "Current trailing-30-day snapshot only. Canonical app_opened history is still required for historical cohorts.",
  };
}

export async function getKpiValues(
  sql: AdminSql,
  query: AnalyticsKpiQuery,
): Promise<KpiValue[]> {
  const values = new Map<string, KpiValue>();
  values.set("accounts_created", await accountsCreated(sql, query));
  values.set(
    "monthly_active_accounts",
    await monthlyActiveAccounts(sql, query),
  );

  return KPI_DEFINITIONS.map(
    (definition) =>
      values.get(definition.name) ??
        unavailable(
          definition.name,
          "The canonical lifecycle event history required by this KPI is not yet instrumented.",
        ),
  );
}
