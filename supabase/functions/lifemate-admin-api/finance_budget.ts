import { ApiError } from "./validation.ts";
import {
  currencyMinorUnitExponent,
  type FinanceProfitLossQuery,
  parseFinanceProfitLossQuery,
} from "./finance.ts";

export type FinanceBudgetQuery = FinanceProfitLossQuery;
export type FinanceEntryKind = "Revenue" | "Expense";

export type FinanceBudgetCategoryInput = {
  kind: FinanceEntryKind;
  code: string;
  label: string;
  budgetMinor: bigint | null;
  actualMinor: bigint;
};

function isCalendarMonthStart(value: string): boolean {
  return value.slice(8, 10) === "01";
}

function isCalendarMonthEnd(value: string): boolean {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.getUTCDate() === 1;
}

function currentTehranMonth(now: Date): { from: string; to: string } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(now);
  const year = Number(parts.find((item) => item.type === "year")?.value);
  const month = Number(parts.find((item) => item.type === "month")?.value);
  if (!Number.isInteger(year) || !Number.isInteger(month)) {
    throw new ApiError(
      503,
      "finance_calendar_unavailable",
      "Finance reporting calendar is unavailable.",
    );
  }
  const monthText = String(month).padStart(2, "0");
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return {
    from: `${year}-${monthText}-01`,
    to: `${year}-${monthText}-${String(lastDay).padStart(2, "0")}`,
  };
}

export function parseFinanceBudgetQuery(
  url: URL,
  now = new Date(),
): FinanceBudgetQuery {
  const requestUrl = new URL(url.toString());
  if (
    !requestUrl.searchParams.has("from") && !requestUrl.searchParams.has("to")
  ) {
    const month = currentTehranMonth(now);
    requestUrl.searchParams.set("from", month.from);
    requestUrl.searchParams.set("to", month.to);
  }
  const query = parseFinanceProfitLossQuery(requestUrl, now);
  if (!isCalendarMonthStart(query.from) || !isCalendarMonthEnd(query.to)) {
    throw new ApiError(
      400,
      "finance_budget_period_alignment_required",
      "Budget comparison requires complete calendar months; partial-month budget prorating is not inferred.",
    );
  }
  return query;
}

export function financeBudgetMonthCount(query: FinanceBudgetQuery): number {
  const [fromYear, fromMonth] = query.from.split("-").map(Number);
  const [toYear, toMonth] = query.to.split("-").map(Number);
  return (toYear - fromYear) * 12 + toMonth - fromMonth + 1;
}

export function varianceBasisPoints(
  actualMinor: bigint,
  budgetMinor: bigint,
): string | null {
  if (budgetMinor <= 0n) return null;
  return (((actualMinor - budgetMinor) * 10_000n) / budgetMinor).toString();
}

export function varianceFavorability(
  kind: FinanceEntryKind | "Net",
  actualMinor: bigint,
  budgetMinor: bigint,
): "favorable" | "unfavorable" | "on_budget" {
  if (actualMinor === budgetMinor) return "on_budget";
  if (kind === "Expense") {
    return actualMinor < budgetMinor ? "favorable" : "unfavorable";
  }
  return actualMinor > budgetMinor ? "favorable" : "unfavorable";
}

export function summarizeBudgetVsActual(
  entries: readonly FinanceBudgetCategoryInput[],
) {
  let budgetRevenue = 0n;
  let budgetExpense = 0n;
  let actualRevenue = 0n;
  let actualExpense = 0n;

  const categories = entries.map((entry) => {
    if (entry.kind === "Revenue") actualRevenue += entry.actualMinor;
    else actualExpense += entry.actualMinor;

    if (entry.budgetMinor !== null) {
      if (entry.kind === "Revenue") budgetRevenue += entry.budgetMinor;
      else budgetExpense += entry.budgetMinor;
    }

    const varianceMinor = entry.budgetMinor === null
      ? null
      : entry.actualMinor - entry.budgetMinor;

    return {
      ...entry,
      varianceMinor,
      varianceBasisPoints: entry.budgetMinor === null
        ? null
        : varianceBasisPoints(entry.actualMinor, entry.budgetMinor),
      favorability: entry.budgetMinor === null ? null : varianceFavorability(
        entry.kind,
        entry.actualMinor,
        entry.budgetMinor,
      ),
    };
  });

  const budgetNet = budgetRevenue - budgetExpense;
  const actualNet = actualRevenue - actualExpense;

  return {
    totals: {
      revenue: {
        budgetMinor: budgetRevenue,
        actualMinor: actualRevenue,
        varianceMinor: actualRevenue - budgetRevenue,
        varianceBasisPoints: varianceBasisPoints(actualRevenue, budgetRevenue),
        favorability: varianceFavorability(
          "Revenue",
          actualRevenue,
          budgetRevenue,
        ),
      },
      expense: {
        budgetMinor: budgetExpense,
        actualMinor: actualExpense,
        varianceMinor: actualExpense - budgetExpense,
        varianceBasisPoints: varianceBasisPoints(actualExpense, budgetExpense),
        favorability: varianceFavorability(
          "Expense",
          actualExpense,
          budgetExpense,
        ),
      },
      net: {
        budgetMinor: budgetNet,
        actualMinor: actualNet,
        varianceMinor: actualNet - budgetNet,
        varianceBasisPoints: varianceBasisPoints(actualNet, budgetNet),
        favorability: varianceFavorability("Net", actualNet, budgetNet),
      },
    },
    categories,
  };
}

export function budgetCurrencyMinorUnitExponent(currency: string): number {
  return currencyMinorUnitExponent(currency);
}
