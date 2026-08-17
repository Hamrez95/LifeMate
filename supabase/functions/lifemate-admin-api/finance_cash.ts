import { ApiError } from "./validation.ts";
import {
  budgetCurrencyMinorUnitExponent,
  type FinanceBudgetQuery,
  parseFinanceBudgetQuery,
} from "./finance_budget.ts";

export type FinanceCashPlanningQuery = FinanceBudgetQuery & {
  horizonMonths: number;
};

export type FinanceBurnMonthInput = {
  month: string;
  revenueMinor: bigint;
  expenseMinor: bigint;
};

export type FinanceScenarioMonthInput = FinanceBurnMonthInput;

export const DEFAULT_CASH_FORECAST_HORIZON_MONTHS = 6;
export const MAX_CASH_FORECAST_HORIZON_MONTHS = 18;

export function parseFinanceCashPlanningQuery(
  url: URL,
  now = new Date(),
): FinanceCashPlanningQuery {
  const query = parseFinanceBudgetQuery(url, now);
  const rawHorizon = url.searchParams.get("horizonMonths")?.trim() ?? "";
  const horizonMonths = rawHorizon === ""
    ? DEFAULT_CASH_FORECAST_HORIZON_MONTHS
    : Number(rawHorizon);

  if (
    !Number.isInteger(horizonMonths) || horizonMonths < 1 ||
    horizonMonths > MAX_CASH_FORECAST_HORIZON_MONTHS
  ) {
    throw new ApiError(
      400,
      "finance_cash_horizon_invalid",
      `Cash-planning forecast horizon must contain between 1 and ${MAX_CASH_FORECAST_HORIZON_MONTHS} months.`,
    );
  }

  return { ...query, horizonMonths };
}

export function summarizeBurn(
  months: readonly FinanceBurnMonthInput[],
) {
  if (months.length === 0) {
    return null;
  }

  let revenueMinor = 0n;
  let grossBurnMinor = 0n;
  const series = months.map((month) => {
    revenueMinor += month.revenueMinor;
    grossBurnMinor += month.expenseMinor;
    return {
      ...month,
      netBurnMinor: month.expenseMinor - month.revenueMinor,
    };
  });
  const netBurnMinor = grossBurnMinor - revenueMinor;
  const divisor = BigInt(months.length);

  return {
    monthCount: months.length,
    revenueMinor,
    grossBurnMinor,
    netBurnMinor,
    averageGrossBurnMinor: grossBurnMinor / divisor,
    averageNetBurnMinor: netBurnMinor / divisor,
    series,
  };
}

export function runwayMonthsBasisPoints(
  cashBalanceMinor: bigint,
  averageNetBurnMinor: bigint,
): string | null {
  if (cashBalanceMinor < 0n) {
    throw new Error("cash balance cannot be negative");
  }
  if (averageNetBurnMinor <= 0n) return null;
  return ((cashBalanceMinor * 10_000n) / averageNetBurnMinor).toString();
}

export function projectScenario(
  openingCashMinor: bigint,
  months: readonly FinanceScenarioMonthInput[],
) {
  if (openingCashMinor < 0n) {
    throw new Error("cash balance cannot be negative");
  }

  let cash = openingCashMinor;
  let depletionMonth: string | null = null;
  const series = months.map((month) => {
    const netBurnMinor = month.expenseMinor - month.revenueMinor;
    cash -= netBurnMinor;
    if (depletionMonth === null && cash <= 0n && netBurnMinor > 0n) {
      depletionMonth = month.month;
    }
    return {
      ...month,
      netBurnMinor,
      projectedEndingCashMinor: cash,
    };
  });

  return {
    openingCashMinor,
    endingCashMinor: cash,
    depletionMonth,
    series,
  };
}

export function cashCurrencyMinorUnitExponent(currency: string): number {
  return budgetCurrencyMinorUnitExponent(currency);
}
