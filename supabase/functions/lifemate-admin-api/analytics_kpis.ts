import { ApiError } from "./validation.ts";

export type AnalyticsProduct = "wellmate" | "caremate" | "women_health";

export type AnalyticsKpiQuery = {
  from: string;
  to: string;
  product: AnalyticsProduct | null;
};

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const PRODUCTS = new Set<AnalyticsProduct>([
  "wellmate",
  "caremate",
  "women_health",
]);

function datePartsInTehran(now: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const value = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

function shiftDate(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function validDate(value: string): boolean {
  if (!DATE_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function readDate(value: string | null, fallback: string): string {
  if (value == null || value === "") return fallback;
  if (!validDate(value)) {
    throw new ApiError(400, "invalid_request", "Analytics date filter is invalid.");
  }
  return value;
}

function readProduct(value: string | null): AnalyticsProduct | null {
  if (value == null || value === "") return null;
  const normalized = value.toLowerCase() as AnalyticsProduct;
  if (!PRODUCTS.has(normalized)) {
    throw new ApiError(400, "invalid_request", "Analytics product filter is invalid.");
  }
  return normalized;
}

export function parseAnalyticsKpiQuery(
  url: URL,
  now = new Date(),
): AnalyticsKpiQuery {
  const today = datePartsInTehran(now);
  const to = readDate(url.searchParams.get("to"), today);
  const from = readDate(url.searchParams.get("from"), shiftDate(to, -29));

  const fromMs = Date.parse(`${from}T00:00:00.000Z`);
  const toMs = Date.parse(`${to}T00:00:00.000Z`);
  const daySpan = Math.floor((toMs - fromMs) / 86_400_000) + 1;
  if (daySpan < 1 || daySpan > 366) {
    throw new ApiError(
      400,
      "invalid_request",
      "Analytics date range must contain between 1 and 366 days.",
    );
  }

  return {
    from,
    to,
    product: readProduct(url.searchParams.get("product")),
  };
}

export function tehranToday(now = new Date()): string {
  return datePartsInTehran(now);
}
