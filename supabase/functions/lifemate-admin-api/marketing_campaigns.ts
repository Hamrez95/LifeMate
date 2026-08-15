import {
  ApiError,
  boundedAdminPage,
  boundedAdminPageSize,
  requireUuid,
} from "./validation.ts";

export const MARKETING_CAMPAIGN_STATUSES = [
  "Draft",
  "Ready",
  "Active",
  "Paused",
  "Completed",
  "Cancelled",
] as const;

export type MarketingCampaignStatus = (typeof MARKETING_CAMPAIGN_STATUSES)[number];

export type MarketingCampaignQuery = {
  page: number;
  pageSize: number;
  offset: number;
  search: string | null;
  product: string | null;
  status: MarketingCampaignStatus | null;
  ownerAdminAccountId: string | null;
};

export type MarketingCampaignItem = {
  id: string;
  name: string;
  objective: string | null;
  productCode: string | null;
  status: MarketingCampaignStatus;
  startsAtUtc: string | null;
  endsAtUtc: string | null;
  ownerAdminAccountId: string | null;
  createdAtUtc: string;
  updatedAtUtc: string;
};

const STATUS_SET = new Set<string>(MARKETING_CAMPAIGN_STATUSES);
const PRODUCT_PATTERN = /^[a-z0-9][a-z0-9_-]{0,63}$/;

function optionalSearch(value: string | null): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (
    normalized.length < 2 ||
    normalized.length > 120 ||
    /[\u0000-\u001f\u007f]/.test(normalized)
  ) {
    throw new ApiError(400, "marketing_campaign_search_invalid", "Campaign search query is invalid.");
  }
  return normalized;
}

function optionalProduct(value: string | null): string | null {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (!normalized) return null;
  if (!PRODUCT_PATTERN.test(normalized)) {
    throw new ApiError(400, "marketing_campaign_product_invalid", "Campaign product filter is invalid.");
  }
  return normalized;
}

function optionalStatus(value: string | null): MarketingCampaignStatus | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (!STATUS_SET.has(normalized)) {
    throw new ApiError(400, "marketing_campaign_status_invalid", "Campaign status filter is invalid.");
  }
  return normalized as MarketingCampaignStatus;
}

function optionalOwner(value: string | null): string | null {
  const normalized = value?.trim() ?? "";
  return normalized ? requireUuid(normalized, "owner") : null;
}

export function parseMarketingCampaignQuery(url: URL): MarketingCampaignQuery {
  const page = boundedAdminPage(url.searchParams.get("page"));
  const pageSize = boundedAdminPageSize(url.searchParams.get("pageSize"), 25, 5, 100);
  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    search: optionalSearch(url.searchParams.get("q")),
    product: optionalProduct(url.searchParams.get("product")),
    status: optionalStatus(url.searchParams.get("status")),
    ownerAdminAccountId: optionalOwner(url.searchParams.get("owner")),
  };
}
