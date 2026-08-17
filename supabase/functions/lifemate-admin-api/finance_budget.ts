import { ApiError } from "./validation.ts";
import {
  currencyMinorUnitExponent,
  parseFinanceProfitLossQuery,
  type FinanceProfitLossQuery,
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

export function parseFinanceBudgetQuery(url: URL, now = new Date()): FinanceBudgetQuery {
  const query = parseFinanceProfitLossQuery(url, now);
  if (!isCalendarMonthStart(query.from) || !isCalendarMonthEnd(query.to)) {
    throw new ApiError(
      400,
      "finance_budget_period_alignment_required",
      "Budget comparison requires complete calendar months; partial-month budget prorating is not inferred.",
    );
  }
  return query;
}

export function varianceBasisPoints(actualMinor: bigint, budgetMinor: bigint): string | null {
  if (budgetMinor === 0n) return null;
  return (((actualMinor - budgetMinor) * 10_000n) / budgetMinor).toString();
}

export function varianceFavorability(
  kind: FinanceEntryKind | "Net",
  actualMinor: bigint,
  budgetMinor: bigint,
): "favorable" | "unfavorable" | "on_budget" {
  if (actualMinor === budgetMinor) return "on_budget";
  if (kind === "Expense") return actualMinor < budgetMinor ? "favorable" : "unfavorable";
  return actualMinor > budgetMinor ? "favorable" : "unfavorable";
}

export function summarizeBudgetVsActual(entries: readonly FinanceBudgetCategoryInput[]) {
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
      favorability: entry.budgetMinor === null
        ? null
        : varianceFavorability(entry.kind, entry.actualMinor, entry.budgetMinor),
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
        favorability: varianceFavorability("Revenue", actualRevenue, budgetRevenue),
      },
      expense: {
        budgetMinor: budgetExpense,
        actualMinor: actualExpense,
        varianceMinor: actualExpense - budgetExpense,
        varianceBasisPoints: varianceBasisPoints(actualExpense, budgetExpense),
        favorability: varianceFavorability("Expense", actualExpense, budgetExpense),
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
