import { type AdminSql, getAdminSql } from "./database_client.ts";
import {
  currencyMinorUnitExponent,
  type FinanceActualEntry,
  type FinanceProfitLossQuery,
  summarizeActualEntries,
} from "./finance.ts";

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

function minor(value: bigint): string {
  return value.toString();
}

function serializeSummary(summary: ReturnType<typeof summarizeActualEntries>) {
  return {
    revenueMinor: minor(summary.revenueMinor),
    expenseMinor: minor(summary.expenseMinor),
    netResultMinor: minor(summary.netResultMinor),
    categories: summary.categories.map((item) => ({
      ...item,
      amountMinor: minor(item.amountMinor),
    })),
    series: summary.series.map((item) => ({
      ...item,
      revenueMinor: minor(item.revenueMinor),
      expenseMinor: minor(item.expenseMinor),
      netResultMinor: minor(item.netResultMinor),
    })),
  };
}

async function availableCurrencies(
  sql: AdminSql,
  query: FinanceProfitLossQuery,
) {
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

async function aggregateEntries(
  sql: AdminSql,
  query: FinanceProfitLossQuery,
  currency: string,
): Promise<{ entries: FinanceActualEntry[]; asOfUtc: string | null }> {
  const rows = await sql`
    select
      entry_kind,
      category_code,
      category_label,
      to_char(date_trunc('month', occurred_on::timestamp), 'YYYY-MM') as month,
      sum(amount_minor * effect) as amount_minor,
      max(posted_at_utc) as as_of_utc
    from finance.actual_ledger_entries
    where occurred_on >= ${query.from}::date
      and occurred_on <= ${query.to}::date
      and currency = ${currency}
    group by entry_kind, category_code, category_label, date_trunc('month', occurred_on::timestamp)
    having sum(amount_minor * effect) <> 0
    order by month asc, entry_kind asc, category_code asc
  `;

  const mapped = (rows as unknown as Record<string, unknown>[]).map((row) => ({
    kind: String(row.entry_kind) as "Revenue" | "Expense",
    categoryCode: String(row.category_code),
    categoryLabel: String(row.category_label),
    month: String(row.month),
    amountMinor: BigInt(String(row.amount_minor)),
    asOfUtc: row.as_of_utc == null ? null : iso(row.as_of_utc),
  }));

  return {
    entries: mapped.map(({ asOfUtc: _asOfUtc, ...entry }) => entry),
    asOfUtc: mapped.reduce<string | null>((latest, row) => {
      if (!row.asOfUtc) return latest;
      return latest == null || row.asOfUtc > latest ? row.asOfUtc : latest;
    }, null),
  };
}

export function createFinanceProfitLossStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async getProfitLoss(query: FinanceProfitLossQuery) {
      const currencies = await availableCurrencies(sql, query);
      if (currencies.length === 0) {
        return {
          state: "unavailable" as const,
          query,
          currency: query.currency,
          minorUnitExponent: query.currency
            ? currencyMinorUnitExponent(query.currency)
            : null,
          availableCurrencies: [],
          actual: null,
          forecast: {
            state: "unavailable" as const,
            reason:
              "No canonical forecast source is configured. Forecast is never inferred from actuals.",
          },
          source: {
            kind: "canonical" as const,
            label: "LifeMate posted finance actual ledger",
            definitionVersion: 1,
          },
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason:
            "No posted actual ledger entries exist for the selected period.",
        };
      }

      if (!query.currency && currencies.length > 1) {
        return {
          state: "currency_required" as const,
          query,
          currency: null,
          minorUnitExponent: null,
          availableCurrencies: currencies,
          actual: null,
          forecast: {
            state: "unavailable" as const,
            reason:
              "No canonical forecast source is configured. Forecast is never inferred from actuals.",
          },
          source: {
            kind: "canonical" as const,
            label: "LifeMate posted finance actual ledger",
            definitionVersion: 1,
          },
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason:
            "Multiple currencies exist in this period. Select one currency; silent FX conversion is forbidden.",
        };
      }

      const currency = query.currency ?? currencies[0];
      const minorUnitExponent = currencyMinorUnitExponent(currency);
      if (!currencies.includes(currency)) {
        return {
          state: "unavailable" as const,
          query,
          currency,
          minorUnitExponent,
          availableCurrencies: currencies,
          actual: null,
          forecast: {
            state: "unavailable" as const,
            reason:
              "No canonical forecast source is configured. Forecast is never inferred from actuals.",
          },
          source: {
            kind: "canonical" as const,
            label: "LifeMate posted finance actual ledger",
            definitionVersion: 1,
          },
          freshness: { status: "unavailable" as const, asOfUtc: null },
          reason:
            "No posted actual ledger entries exist for the selected currency and period.",
        };
      }

      const aggregate = await aggregateEntries(sql, query, currency);
      const summary = summarizeActualEntries(aggregate.entries);
      return {
        state: "ready" as const,
        query,
        currency,
        minorUnitExponent,
        availableCurrencies: currencies,
        actual: serializeSummary(summary),
        forecast: {
          state: "unavailable" as const,
          reason:
            "No canonical forecast source is configured. Forecast is never inferred from actuals.",
        },
        source: {
          kind: "canonical" as const,
          label: "LifeMate posted finance actual ledger",
          definitionVersion: 1,
        },
        freshness: {
          status: aggregate.asOfUtc
            ? ("fresh" as const)
            : ("unavailable" as const),
          asOfUtc: aggregate.asOfUtc,
        },
        reason: null,
      };
    },
  };
}
