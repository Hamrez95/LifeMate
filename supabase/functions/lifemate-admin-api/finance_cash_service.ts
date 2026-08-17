import { type AdminSql, getAdminSql } from "./database_client.ts";
import {
  cashCurrencyMinorUnitExponent,
  type FinanceBurnMonthInput,
  type FinanceCashPlanningQuery,
  projectScenario,
  runwayMonthsBasisPoints,
  summarizeBurn,
} from "./finance_cash.ts";
import { financeBudgetMonthCount } from "./finance_budget.ts";

const SCENARIOS = ["Base", "Upside", "Downside"] as const;
type Scenario = typeof SCENARIOS[number];

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function date(value: unknown): string {
  return value instanceof Date
    ? value.toISOString().slice(0, 10)
    : String(value);
}

function minor(value: bigint | null): string | null {
  return value === null ? null : value.toString();
}

function nextMonthStart(monthEnd: string): string {
  const next = new Date(`${monthEnd}T00:00:00.000Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString().slice(0, 10);
}

function monthKey(value: unknown): string {
  return date(value).slice(0, 7);
}

async function distinctCurrencies(
  sql: AdminSql,
  query: FinanceCashPlanningQuery,
): Promise<string[]> {
  const forecastStart = nextMonthStart(query.to);
  const rows = await sql`
    select distinct currency
    from (
      select currency
      from finance.actual_ledger_entries
      where occurred_on >= ${query.from}::date
        and occurred_on <= ${query.to}::date
      union
      select currency
      from finance.cash_balance_snapshots
      where as_of_date <= ${query.to}::date
      union
      select currency
      from finance.cash_plan_versions
      where forecast_start_month = ${forecastStart}::date
        and horizon_months >= ${query.horizonMonths}
    ) currencies
    order by currency asc
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) =>
    String(row.currency)
  );
}

async function burnRows(
  sql: AdminSql,
  query: FinanceCashPlanningQuery,
  currency: string,
) {
  const rows = await sql`
    select
      to_char(date_trunc('month', occurred_on::timestamp), 'YYYY-MM') as month,
      sum(case when entry_kind = 'Revenue' then amount_minor * effect else 0 end) as revenue_minor,
      sum(case when entry_kind = 'Expense' then amount_minor * effect else 0 end) as expense_minor,
      max(posted_at_utc) as as_of_utc
    from finance.actual_ledger_entries
    where occurred_on >= ${query.from}::date
      and occurred_on <= ${query.to}::date
      and currency = ${currency}
    group by date_trunc('month', occurred_on::timestamp)
    order by month asc
  `;
  return rows as unknown as Record<string, unknown>[];
}

async function latestCashSnapshot(
  sql: AdminSql,
  query: FinanceCashPlanningQuery,
  currency: string,
) {
  const rows = await sql`
    select as_of_date, balance_minor, source_kind, observed_at_utc
    from finance.cash_balance_snapshots
    where currency = ${currency}
      and as_of_date <= ${query.to}::date
    order by as_of_date desc, observed_at_utc desc, id desc
    limit 1
  `;
  return (rows as unknown as Record<string, unknown>[])[0] ?? null;
}

async function latestPlan(
  sql: AdminSql,
  query: FinanceCashPlanningQuery,
  currency: string,
) {
  const forecastStart = nextMonthStart(query.to);
  const rows = await sql`
    select id, plan_code, version, label, currency, forecast_start_month,
      horizon_months, approved_at_utc, source_kind
    from finance.cash_plan_versions
    where currency = ${currency}
      and forecast_start_month = ${forecastStart}::date
      and horizon_months >= ${query.horizonMonths}
    order by approved_at_utc desc, version desc, id desc
    limit 1
  `;
  return (rows as unknown as Record<string, unknown>[])[0] ?? null;
}

async function planAssumptions(sql: AdminSql, planId: string) {
  const rows = await sql`
    select scenario, assumption_code, label, value_text
    from finance.cash_plan_assumptions
    where plan_version_id = ${planId}::uuid
    order by scenario asc, sort_order asc, assumption_code asc
  `;
  return rows as unknown as Record<string, unknown>[];
}

async function planScenarioMonths(
  sql: AdminSql,
  planId: string,
  query: FinanceCashPlanningQuery,
) {
  const forecastStart = nextMonthStart(query.to);
  const rows = await sql`
    select scenario, month_start, revenue_minor, expense_minor
    from finance.cash_plan_scenario_months
    where plan_version_id = ${planId}::uuid
      and month_start >= ${forecastStart}::date
      and month_start < (${forecastStart}::date + make_interval(months => ${query.horizonMonths}))::date
    order by scenario asc, month_start asc
  `;
  return rows as unknown as Record<string, unknown>[];
}

function serializeBurn(summary: NonNullable<ReturnType<typeof summarizeBurn>>) {
  return {
    monthCount: summary.monthCount,
    revenueMinor: minor(summary.revenueMinor),
    grossBurnMinor: minor(summary.grossBurnMinor),
    netBurnMinor: minor(summary.netBurnMinor),
    averageGrossBurnMinor: minor(summary.averageGrossBurnMinor),
    averageNetBurnMinor: minor(summary.averageNetBurnMinor),
    series: summary.series.map((row) => ({
      month: row.month,
      revenueMinor: minor(row.revenueMinor),
      expenseMinor: minor(row.expenseMinor),
      netBurnMinor: minor(row.netBurnMinor),
    })),
  };
}

export function createFinanceCashPlanningStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getCashPlanning(query: FinanceCashPlanningQuery) {
      const currencies = await distinctCurrencies(sql, query);
      if (!query.currency && currencies.length > 1) {
        return {
          state: "currency_required" as const,
          query,
          currency: null,
          minorUnitExponent: null,
          availableCurrencies: currencies,
          actual: null,
          cash: null,
          runway: null,
          forecast: null,
          reason:
            "Multiple finance currencies exist. Select one currency; silent FX conversion is forbidden.",
        };
      }

      const currency = query.currency ?? currencies[0] ?? null;
      if (!currency || !currencies.includes(currency)) {
        return {
          state: "unavailable" as const,
          query,
          currency,
          minorUnitExponent: currency
            ? cashCurrencyMinorUnitExponent(currency)
            : null,
          availableCurrencies: currencies,
          actual: {
            state: "unavailable" as const,
            burn: null,
            source: null,
            freshness: { status: "unavailable" as const, asOfUtc: null },
            reason:
              "No canonical finance actual, cash-balance or forecast source exists for the selected currency and period.",
          },
          cash: {
            state: "unavailable" as const,
            balanceMinor: null,
            asOfDate: null,
            source: null,
            freshness: { status: "unavailable" as const, asOfUtc: null },
            reason: "No canonical cash-balance snapshot is available.",
          },
          runway: {
            state: "unavailable" as const,
            trailingMonthsBasisPoints: null,
            formula:
              "observed cash balance / positive average monthly net burn over the selected completed-month actual period",
            reason:
              "Runway requires both an observed canonical cash balance and complete canonical actual burn history.",
          },
          forecast: {
            state: "unavailable" as const,
            plan: null,
            assumptions: [],
            scenarios: [],
            reason:
              "No canonical versioned cash forecast plan is available for the requested bounded horizon.",
          },
          reason:
            "Cash planning is unavailable because no canonical source exists for the selected currency and period.",
        };
      }

      const [rawBurnRows, cashSnapshot, plan] = await Promise.all([
        burnRows(sql, query, currency),
        latestCashSnapshot(sql, query, currency),
        latestPlan(sql, query, currency),
      ]);

      let actualAsOfUtc: string | null = null;
      const burnInputs: FinanceBurnMonthInput[] = rawBurnRows.map((row) => {
        const asOfUtc = row.as_of_utc == null ? null : iso(row.as_of_utc);
        if (asOfUtc && (!actualAsOfUtc || asOfUtc > actualAsOfUtc)) {
          actualAsOfUtc = asOfUtc;
        }
        return {
          month: String(row.month),
          revenueMinor: BigInt(String(row.revenue_minor)),
          expenseMinor: BigInt(String(row.expense_minor)),
        };
      });
      const expectedActualMonths = financeBudgetMonthCount(query);
      const burnSummary = burnInputs.length === expectedActualMonths
        ? summarizeBurn(burnInputs)
        : null;
      const actual = burnSummary
        ? {
          state: "ready" as const,
          burn: serializeBurn(burnSummary),
          source: {
            kind: "canonical" as const,
            label: "LifeMate posted finance actual ledger",
            definitionVersion: 1,
          },
          freshness: {
            status: actualAsOfUtc
              ? ("fresh" as const)
              : ("unavailable" as const),
            asOfUtc: actualAsOfUtc,
          },
          reason: null,
        }
        : {
          state: "unavailable" as const,
          burn: null,
          source: rawBurnRows.length > 0
            ? {
              kind: "canonical" as const,
              label: "LifeMate posted finance actual ledger",
              definitionVersion: 1,
            }
            : null,
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason: rawBurnRows.length === 0
            ? "No posted actual ledger entries exist for the selected completed-month period."
            : "Actual burn history does not cover every selected completed calendar month; missing months are not treated as zero.",
        };

      const cash = cashSnapshot
        ? {
          state: "ready" as const,
          balanceMinor: String(cashSnapshot.balance_minor),
          asOfDate: date(cashSnapshot.as_of_date),
          source: {
            kind: "canonical" as const,
            label: "LifeMate observed management cash balance",
            sourceKind: String(cashSnapshot.source_kind),
            observedAtUtc: iso(cashSnapshot.observed_at_utc),
          },
          freshness: {
            status: date(cashSnapshot.as_of_date) === query.to
              ? ("fresh" as const)
              : ("stale" as const),
            asOfUtc: iso(cashSnapshot.observed_at_utc),
          },
          reason: date(cashSnapshot.as_of_date) === query.to
            ? null
            : "The latest canonical cash snapshot predates the selected actual-period end date.",
        }
        : {
          state: "unavailable" as const,
          balanceMinor: null,
          asOfDate: null,
          source: null,
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason:
            "No canonical cash-balance snapshot exists on or before the selected actual-period end date.",
        };

      const runway = burnSummary && cashSnapshot
        ? burnSummary.averageNetBurnMinor <= 0n
          ? {
            state: "not_burning" as const,
            trailingMonthsBasisPoints: null,
            formula:
              "observed cash balance / positive average monthly net burn over the selected completed-month actual period",
            reason:
              "Average net burn is zero or negative, so finite trailing runway is not asserted.",
          }
          : {
            state: "ready" as const,
            trailingMonthsBasisPoints: runwayMonthsBasisPoints(
              BigInt(String(cashSnapshot.balance_minor)),
              burnSummary.averageNetBurnMinor,
            ),
            formula:
              "observed cash balance / positive average monthly net burn over the selected completed-month actual period",
            reason: null,
          }
        : {
          state: "unavailable" as const,
          trailingMonthsBasisPoints: null,
          formula:
            "observed cash balance / positive average monthly net burn over the selected completed-month actual period",
          reason:
            "Runway requires both an observed canonical cash balance and complete canonical actual burn history.",
        };

      let forecast: {
        state: "ready" | "unavailable";
        plan: Record<string, unknown> | null;
        assumptions: Record<string, unknown>[];
        scenarios: Record<string, unknown>[];
        reason: string | null;
      };

      if (!plan) {
        forecast = {
          state: "unavailable",
          plan: null,
          assumptions: [],
          scenarios: [],
          reason:
            "No canonical versioned cash forecast plan starts at the requested forecast boundary and covers the requested bounded horizon.",
        };
      } else {
        const planId = String(plan.id);
        const [assumptionRows, scenarioRows] = await Promise.all([
          planAssumptions(sql, planId),
          planScenarioMonths(sql, planId, query),
        ]);
        const assumptionsByScenario = new Map<
          Scenario,
          Record<string, unknown>[]
        >();
        const monthsByScenario = new Map<Scenario, FinanceBurnMonthInput[]>();
        for (const scenario of SCENARIOS) {
          assumptionsByScenario.set(scenario, []);
          monthsByScenario.set(scenario, []);
        }

        for (const row of assumptionRows) {
          const scenario = String(row.scenario) as Scenario;
          if (!SCENARIOS.includes(scenario)) continue;
          assumptionsByScenario.get(scenario)?.push({
            scenario,
            code: String(row.assumption_code),
            label: String(row.label),
            value: String(row.value_text),
          });
        }
        for (const row of scenarioRows) {
          const scenario = String(row.scenario) as Scenario;
          if (!SCENARIOS.includes(scenario)) continue;
          monthsByScenario.get(scenario)?.push({
            month: monthKey(row.month_start),
            revenueMinor: BigInt(String(row.revenue_minor)),
            expenseMinor: BigInt(String(row.expense_minor)),
          });
        }

        const complete = SCENARIOS.every((scenario) =>
          (assumptionsByScenario.get(scenario)?.length ?? 0) > 0 &&
          (monthsByScenario.get(scenario)?.length ?? 0) === query.horizonMonths
        );

        if (!complete) {
          forecast = {
            state: "unavailable",
            plan: {
              code: String(plan.plan_code),
              version: Number(plan.version),
              label: String(plan.label),
              forecastStartMonth: date(plan.forecast_start_month),
              declaredHorizonMonths: Number(plan.horizon_months),
              approvedAtUtc: iso(plan.approved_at_utc),
              sourceKind: String(plan.source_kind),
            },
            assumptions: assumptionRows.map((row) => ({
              scenario: String(row.scenario),
              code: String(row.assumption_code),
              label: String(row.label),
              value: String(row.value_text),
            })),
            scenarios: [],
            reason:
              "The selected forecast plan does not contain all three scenarios, visible assumptions and every requested forecast month; missing forecast data is not treated as zero.",
          };
        } else {
          const openingCash = cashSnapshot
            ? BigInt(String(cashSnapshot.balance_minor))
            : null;
          const assumptions = SCENARIOS.flatMap((scenario) =>
            assumptionsByScenario.get(scenario) ?? []
          );
          const scenarios = SCENARIOS.map((scenario) => {
            const months = monthsByScenario.get(scenario) ?? [];
            const projection = openingCash === null
              ? null
              : projectScenario(openingCash, months);
            return {
              scenario,
              months: months.map((row) => ({
                month: row.month,
                revenueMinor: minor(row.revenueMinor),
                expenseMinor: minor(row.expenseMinor),
                netBurnMinor: minor(row.expenseMinor - row.revenueMinor),
              })),
              projectedCash: projection
                ? {
                  openingCashMinor: minor(projection.openingCashMinor),
                  endingCashMinor: minor(projection.endingCashMinor),
                  depletionMonth: projection.depletionMonth,
                  runwayState: projection.depletionMonth
                    ? "depletes_within_horizon"
                    : "beyond_horizon",
                  series: projection.series.map((row) => ({
                    month: row.month,
                    projectedEndingCashMinor: minor(
                      row.projectedEndingCashMinor,
                    ),
                  })),
                }
                : {
                  openingCashMinor: null,
                  endingCashMinor: null,
                  depletionMonth: null,
                  runwayState: "unavailable",
                  series: [],
                },
            };
          });
          forecast = {
            state: "ready",
            plan: {
              code: String(plan.plan_code),
              version: Number(plan.version),
              label: String(plan.label),
              forecastStartMonth: date(plan.forecast_start_month),
              requestedHorizonMonths: query.horizonMonths,
              declaredHorizonMonths: Number(plan.horizon_months),
              approvedAtUtc: iso(plan.approved_at_utc),
              sourceKind: String(plan.source_kind),
            },
            assumptions,
            scenarios,
            reason: openingCash === null
              ? "Forecast plan is available, but projected cash/runway is unavailable until a canonical cash balance exists."
              : null,
          };
        }
      }

      const readyCount =
        [actual.state, cash.state, forecast.state].filter((state) =>
          state === "ready"
        ).length;
      const state = readyCount === 3
        ? ("ready" as const)
        : readyCount > 0
        ? ("partial" as const)
        : ("unavailable" as const);

      return {
        state,
        query,
        currency,
        minorUnitExponent: cashCurrencyMinorUnitExponent(currency),
        availableCurrencies: currencies,
        actual,
        cash,
        runway,
        forecast,
        reason: state === "ready"
          ? null
          : state === "partial"
          ? "Cash planning is partially available; unavailable or stale sources are disclosed and no missing value is inferred."
          : "Cash planning is unavailable because required canonical sources are missing for the selected period.",
      };
    },
  };
}
