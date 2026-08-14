import { ApiError, boundedInteger } from "./validation.ts";

export type CommerceSubscriptionStatus =
  | "Trial"
  | "Active"
  | "PastDue"
  | "Cancelled"
  | "Expired"
  | "Refunded";

export type CommerceDashboardQuery = {
  page: number;
  pageSize: number;
  offset: number;
  product: string | null;
  plan: string | null;
  status: CommerceSubscriptionStatus | null;
};

const STATUSES = new Set<CommerceSubscriptionStatus>([
  "Trial",
  "Active",
  "PastDue",
  "Cancelled",
  "Expired",
  "Refunded",
]);

function optionalCode(value: string | null, label: string): string | null {
  if (value == null || value === "") return null;
  const normalized = value.trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9_-]{0,63}$/.test(normalized)) {
    throw new ApiError(400, "invalid_request", `${label} filter is invalid.`);
  }
  return normalized;
}

function optionalStatus(
  value: string | null,
): CommerceSubscriptionStatus | null {
  if (value == null || value === "") return null;
  if (!STATUSES.has(value as CommerceSubscriptionStatus)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Subscription status filter is invalid.",
    );
  }
  return value as CommerceSubscriptionStatus;
}

export function parseCommerceDashboardQuery(url: URL): CommerceDashboardQuery {
  const page = boundedInteger(url.searchParams.get("page"), 1, 1, 100_000);
  const pageSize = boundedInteger(url.searchParams.get("pageSize"), 25, 5, 100);
  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    product: optionalCode(url.searchParams.get("product"), "Product"),
    plan: optionalCode(url.searchParams.get("plan"), "Plan"),
    status: optionalStatus(url.searchParams.get("status")),
  };
}
