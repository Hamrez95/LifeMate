import {
  ApiError,
  boundedAdminPage,
  boundedAdminPageSize,
} from "./validation.ts";

export const SUBSCRIPTION_STATUSES = [
  "Trial",
  "Active",
  "PastDue",
  "Cancelled",
  "Expired",
  "Refunded",
] as const;

export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

export type CommerceOverviewQuery = {
  page: number;
  pageSize: number;
  offset: number;
  product: string | null;
  status: SubscriptionStatus | null;
};

const PRODUCT_CODE = /^[a-z0-9][a-z0-9_-]{0,63}$/i;
const STATUS_SET = new Set<string>(SUBSCRIPTION_STATUSES);

export function parseCommerceOverviewQuery(url: URL): CommerceOverviewQuery {
  const page = boundedAdminPage(url.searchParams.get("page"));
  const pageSize = boundedAdminPageSize(
    url.searchParams.get("pageSize"),
    25,
    5,
  );

  const rawProduct = url.searchParams.get("product")?.trim() ?? "";
  if (rawProduct && !PRODUCT_CODE.test(rawProduct)) {
    throw new ApiError(
      400,
      "commerce_product_invalid",
      "Commerce product filter is invalid.",
    );
  }

  const rawStatus = url.searchParams.get("status")?.trim() ?? "";
  if (rawStatus && !STATUS_SET.has(rawStatus)) {
    throw new ApiError(
      400,
      "commerce_status_invalid",
      "Subscription status filter is invalid.",
    );
  }

  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    product: rawProduct || null,
    status: rawStatus ? (rawStatus as SubscriptionStatus) : null,
  };
}
