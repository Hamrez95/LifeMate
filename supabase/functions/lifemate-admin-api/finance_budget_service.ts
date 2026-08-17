import { type AdminSql, getAdminSql } from "./database_client.ts";
import {
  budgetCurrencyMinorUnitExponent,
  type FinanceBudgetCategoryInput,
  financeBudgetMonthCount,
  type FinanceBudgetQuery,
  summarizeBudgetVsActual,
} from "./finance_budget.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function minor(value: bigint | null): string | null {
  return value === null ? null : value.toString();
}

function categoryKey(kind: string, code: string): string {
  return `${kind}|${code}`;
}

async function actualCurrencies(
  sql: AdminSql,
  query: FinanceBudgetQuery,
): Promise<string[]> {
  const rows = await sql`
    select distinct currency
    from finance.actual_ledger_entries
    where occurred_on >= ${query.from}::date
      and occurred_on <= ${query.to}::date
    order by currency asc
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) =>
    String(row.currency)
  );
}

async function budgetCurrencies(
  sql: AdminSql,
  query: FinanceBudgetQuery,
): Promise<string[]> {
  const rows = await sql`
    select distinct currency
    from finance.approved_budget_sets
    where period_start <= ${query.from}::date
      and period_end >= ${query.to}::date
    order by currency asc
  `;
  return (rows as unknown as Record<string, unknown>[]).map((row) =>
    String(row.currency)
  );
}

async function latestBudgetSet(
  sql: AdminSql,
  query: FinanceBudgetQuery,
  currency: string,
) {
  const rows = await sql`
    select id, budget_code, version, label, approved_at_utc
    from finance.approved_budget_sets
    where currency = ${currency}
      and period_start <= ${query.from}::date
      and period_end >= ${query.to}::date
    order by approved_at_utc desc, version desc, id desc
    limit 1
  `;
  return (rows as unknown as Record<string, unknown>[])[0] ?? null;
}

async function actualRows(
  sql: AdminSql,
  query: FinanceBudgetQuery,
  currency: string,
) {
  const rows = await sql`
    select
      entry_kind,
      category_code,
      max(category_label) as category_label,
      sum(amount_minor * effect) as amount_minor,
      max(posted_at_utc) as as_of_utc
    from finance.actual_ledger_entries
    where occurred_on >= ${query.from}::date
      and occurred_on <= ${query.to}::date
      and currency = ${currency}
    group by entry_kind, category_code
    having sum(amount_minor * effect) <> 0
    order by entry_kind asc, category_code asc
  `;
  return rows as unknown as Record<string, unknown>[];
}

async function budgetRows(
  sql: AdminSql,
  budgetSetId: string,
  query: FinanceBudgetQuery,
) {
  const rows = await sql`
    select
      entry_kind,
      category_code,
      max(category_label) as category_label,
      sum(amount_minor) as amount_minor
    from finance.approved_budget_allocations
    where budget_set_id = ${budgetSetId}::uuid
      and month_start >= ${query.from}::date
      and month_start <= ${query.to}::date
    group by entry_kind, category_code
    order by entry_kind asc, category_code asc
  `;
  return rows as unknown as Record<string, unknown>[];
}

async function coveredBudgetMonths(
  sql: AdminSql,
  budgetSetId: string,
  query: FinanceBudgetQuery,
): Promise<number> {
  const rows = await sql`
    select count(distinct month_start)::integer as month_count
    from finance.approved_budget_allocations
    where budget_set_id = ${budgetSetId}::uuid
      and month_start >= ${query.from}::date
      and month_start <= ${query.to}::date
  `;
  const row = (rows as unknown as Record<string, unknown>[])[0];
  return Number(row?.month_count ?? 0);
}

function serializeSummary(summary: ReturnType<typeof summarizeBudgetVsActual>) {
  const serializeVariance = (value: {
    budgetMinor: bigint;
    actualMinor: bigint;
    varianceMinor: bigint;
    varianceBasisPoints: string | null;
    favorability: "favorable" | "unfavorable" | "on_budget";
  }) => ({
    ...value,
    budgetMinor: minor(value.budgetMinor),
    actualMinor: minor(value.actualMinor),
    varianceMinor: minor(value.varianceMinor),
  });

  return {
    totals: {
      revenue: serializeVariance(summary.totals.revenue),
      expense: serializeVariance(summary.totals.expense),
      net: serializeVariance(summary.totals.net),
    },
    categories: summary.categories.map((row) => ({
      kind: row.kind,
      code: row.code,
      label: row.label,
      budgetMinor: minor(row.budgetMinor),
      actualMinor: minor(row.actualMinor),
      varianceMinor: minor(row.varianceMinor),
      varianceBasisPoints: row.varianceBasisPoints,
      favorability: row.favorability,
    })),
  };
}

export function createFinanceBudgetStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getBudgetVsActual(query: FinanceBudgetQuery) {
      const [actualCurrencyList, budgetCurrencyList] = await Promise.all([
        actualCurrencies(sql, query),
        budgetCurrencies(sql, query),
      ]);
      const comparableCurrencies = actualCurrencyList.filter((currency) =>
        budgetCurrencyList.includes(currency)
      );

      if (!query.currency && comparableCurrencies.length > 1) {
        return {
          state: "currency_required" as const,
          query,
          currency: null,
          minorUnitExponent: null,
          availableCurrencies: comparableCurrencies,
          comparison: null,
          budgetSource: null,
          actualSource: null,
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason:
            "Multiple comparable currencies exist. Select one currency; silent FX conversion is forbidden.",
        };
      }

      const currency = query.currency ?? comparableCurrencies[0] ?? null;
      if (!currency || !comparableCurrencies.includes(currency)) {
        return {
          state: "unavailable" as const,
          query,
          currency,
          minorUnitExponent: currency
            ? budgetCurrencyMinorUnitExponent(currency)
            : null,
          availableCurrencies: comparableCurrencies,
          comparison: null,
          budgetSource: null,
          actualSource: actualCurrencyList.length > 0
            ? {
              kind: "canonical" as const,
              label: "LifeMate posted finance actual ledger",
              definitionVersion: 1,
            }
            : null,
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason: budgetCurrencyList.length === 0
            ? "No approved canonical budget covers the selected complete-month period."
            : actualCurrencyList.length === 0
            ? "No posted actual ledger entries exist for the selected period."
            : "No currency has both approved budget and posted actual data for the selected period.",
        };
      }

      const budgetSet = await latestBudgetSet(sql, query, currency);
      if (!budgetSet) {
        throw new Error(
          "comparable budget currency resolved without an approved budget set",
        );
      }

      const budgetSetId = String(budgetSet.id);
      const [actual, budget, coveredMonths] = await Promise.all([
        actualRows(sql, query, currency),
        budgetRows(sql, budgetSetId, query),
        coveredBudgetMonths(sql, budgetSetId, query),
      ]);
      const expectedMonths = financeBudgetMonthCount(query);

      if (budget.length === 0 || coveredMonths !== expectedMonths) {
        return {
          state: "unavailable" as const,
          query,
          currency,
          minorUnitExponent: budgetCurrencyMinorUnitExponent(currency),
          availableCurrencies: comparableCurrencies,
          comparison: null,
          budgetSource: {
            kind: "canonical" as const,
            label: String(budgetSet.label),
            code: String(budgetSet.budget_code),
            version: Number(budgetSet.version),
            approvedAtUtc: iso(budgetSet.approved_at_utc),
          },
          actualSource: {
            kind: "canonical" as const,
            label: "LifeMate posted finance actual ledger",
            definitionVersion: 1,
          },
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason: budget.length === 0
            ? "The approved budget set contains no allocations for the selected period; missing budget allocations are not treated as zero."
            : "The approved budget set does not cover every selected calendar month; missing months are not treated as zero.",
        };
      }

      const actualMap = new Map<
        string,
        { amountMinor: bigint; label: string }
      >();
      let actualAsOfUtc: string | null = null;
      for (const row of actual) {
        const kind = String(row.entry_kind);
        const code = String(row.category_code);
        const asOfUtc = row.as_of_utc == null ? null : iso(row.as_of_utc);
        actualMap.set(categoryKey(kind, code), {
          amountMinor: BigInt(String(row.amount_minor)),
          label: String(row.category_label),
        });
        if (asOfUtc && (!actualAsOfUtc || asOfUtc > actualAsOfUtc)) {
          actualAsOfUtc = asOfUtc;
        }
      }

      const entries: FinanceBudgetCategoryInput[] = budget.map((row) => {
        const kind = String(row.entry_kind) as "Revenue" | "Expense";
        const code = String(row.category_code);
        const key = categoryKey(kind, code);
        const actualValue = actualMap.get(key);
        actualMap.delete(key);
        return {
          kind,
          code,
          label: String(row.category_label),
          budgetMinor: BigInt(String(row.amount_minor)),
          actualMinor: actualValue?.amountMinor ?? 0n,
        };
      });

      for (const [key, value] of actualMap) {
        const separator = key.indexOf("|");
        if (separator < 1) throw new Error("invalid finance category key");
        const kind = key.slice(0, separator) as "Revenue" | "Expense";
        const code = key.slice(separator + 1);
        entries.push({
          kind,
          code,
          label: value.label,
          budgetMinor: null,
          actualMinor: value.amountMinor,
        });
      }

      entries.sort((a, b) =>
        `${a.kind}:${a.code}`.localeCompare(`${b.kind}:${b.code}`)
      );
      const summary = summarizeBudgetVsActual(entries);
      const approvedAtUtc = iso(budgetSet.approved_at_utc);
      const freshnessAsOf = actualAsOfUtc && actualAsOfUtc < approvedAtUtc
        ? actualAsOfUtc
        : approvedAtUtc;

      return {
        state: "ready" as const,
        query,
        currency,
        minorUnitExponent: budgetCurrencyMinorUnitExponent(currency),
        availableCurrencies: comparableCurrencies,
        comparison: serializeSummary(summary),
        budgetSource: {
          kind: "canonical" as const,
          label: String(budgetSet.label),
          code: String(budgetSet.budget_code),
          version: Number(budgetSet.version),
          approvedAtUtc,
        },
        actualSource: {
          kind: "canonical" as const,
          label: "LifeMate posted finance actual ledger",
          definitionVersion: 1,
        },
        freshness: {
          status: freshnessAsOf ? ("fresh" as const) : ("unavailable" as const),
          asOfUtc: freshnessAsOf,
        },
        reason: null,
      };
    },
  };
}
