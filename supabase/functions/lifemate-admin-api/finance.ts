import { ApiError } from "./validation.ts";

export type FinanceProfitLossQuery = {
  from: string;
  to: string;
  currency: string | null;
};

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const CURRENCY = /^[A-Z]{3}$/;
const MAX_DAYS = 366;

function tehranDate(now: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const part = (type: string) =>
    parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

function shiftDate(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function validDate(value: string): boolean {
  if (!DATE.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

export function currencyMinorUnitExponent(currency: string): number {
  const exponent = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
  }).resolvedOptions().maximumFractionDigits;
  if (exponent === undefined) {
    throw new ApiError(
      400,
      "finance_currency_unsupported",
      "Finance currency minor-unit metadata is unavailable.",
    );
  }
  return exponent;
}

export function parseFinanceProfitLossQuery(
  url: URL,
  now = new Date(),
): FinanceProfitLossQuery {
  const today = tehranDate(now);
  const to = url.searchParams.get("to")?.trim() || today;
  const from = url.searchParams.get("from")?.trim() || shiftDate(to, -29);
  const rawCurrency = url.searchParams.get("currency")?.trim().toUpperCase() ||
    "";

  if (!validDate(from) || !validDate(to)) {
    throw new ApiError(
      400,
      "finance_date_invalid",
      "Finance date filter is invalid.",
    );
  }

  const fromMs = Date.parse(`${from}T00:00:00.000Z`);
  const toMs = Date.parse(`${to}T00:00:00.000Z`);
  const days = Math.floor((toMs - fromMs) / 86_400_000) + 1;
  if (days < 1 || days > MAX_DAYS) {
    throw new ApiError(
      400,
      "finance_range_invalid",
      `Finance date range must contain between 1 and ${MAX_DAYS} days.`,
    );
  }

  if (rawCurrency && !CURRENCY.test(rawCurrency)) {
    throw new ApiError(
      400,
      "finance_currency_invalid",
      "Finance currency filter is invalid.",
    );
  }

  return { from, to, currency: rawCurrency || null };
}

export type FinanceActualEntry = {
  kind: "Revenue" | "Expense";
  categoryCode: string;
  categoryLabel: string;
  month: string;
  amountMinor: bigint;
};

export function summarizeActualEntries(entries: readonly FinanceActualEntry[]) {
  let revenue = 0n;
  let expense = 0n;
  const categories = new Map<
    string,
    {
      code: string;
      label: string;
      kind: "Revenue" | "Expense";
      amountMinor: bigint;
    }
  >();
  const months = new Map<
    string,
    { revenueMinor: bigint; expenseMinor: bigint }
  >();

  for (const entry of entries) {
    if (entry.kind === "Revenue") revenue += entry.amountMinor;
    else expense += entry.amountMinor;

    const categoryKey = `${entry.kind}:${entry.categoryCode}`;
    const currentCategory = categories.get(categoryKey);
    categories.set(categoryKey, {
      code: entry.categoryCode,
      label: entry.categoryLabel,
      kind: entry.kind,
      amountMinor: (currentCategory?.amountMinor ?? 0n) + entry.amountMinor,
    });

    const currentMonth = months.get(entry.month) ??
      { revenueMinor: 0n, expenseMinor: 0n };
    if (entry.kind === "Revenue") {
      currentMonth.revenueMinor += entry.amountMinor;
    } else currentMonth.expenseMinor += entry.amountMinor;
    months.set(entry.month, currentMonth);
  }

  return {
    revenueMinor: revenue,
    expenseMinor: expense,
    netResultMinor: revenue - expense,
    categories: [...categories.values()].sort((a, b) =>
      a.code.localeCompare(b.code)
    ),
    series: [...months.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([month, values]) => ({
        month,
        ...values,
        netResultMinor: values.revenueMinor - values.expenseMinor,
      })),
  };
}
