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

export type MarketingCampaignStatus =
  (typeof MARKETING_CAMPAIGN_STATUSES)[number];

export type MarketingCampaignQuery = {
  page: number;
  pageSize: number;
  offset: number;
  search: string | null;
  product: string | null;
  status: MarketingCampaignStatus | null;
  ownerAdminAccountId: string | null;
  startsFromUtc: string | null;
  startsToUtc: string | null;
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

export type MarketingCampaignCreatePayload = {
  name: string;
  objective: string | null;
  productCode: string | null;
  ownerAdminAccountId: string | null;
  startsAtUtc: string | null;
  endsAtUtc: string | null;
  reason: string;
};

const STATUS_SET = new Set<string>(MARKETING_CAMPAIGN_STATUSES);
const CODE_PATTERN = /^[a-z0-9][a-z0-9_.:-]{0,63}$/;

function optionalSearch(value: string | null): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (
    normalized.length < 2 ||
    normalized.length > 120 ||
    /[\u0000-\u001f\u007f]/.test(normalized)
  ) {
    throw new ApiError(
      400,
      "marketing_campaign_search_invalid",
      "Campaign search query is invalid.",
    );
  }
  return normalized;
}

function optionalCode(
  value: string | null,
  code: string,
  label: string,
): string | null {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (!normalized) return null;
  if (!CODE_PATTERN.test(normalized)) {
    throw new ApiError(400, code, `${label} is invalid.`);
  }
  return normalized;
}

function optionalStatus(value: string | null): MarketingCampaignStatus | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  if (!STATUS_SET.has(normalized)) {
    throw new ApiError(
      400,
      "marketing_campaign_status_invalid",
      "Campaign status filter is invalid.",
    );
  }
  return normalized as MarketingCampaignStatus;
}

function optionalOwner(value: string | null): string | null {
  const normalized = value?.trim() ?? "";
  return normalized ? requireUuid(normalized, "owner") : null;
}

function optionalInstant(value: unknown, code: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Timestamp is invalid.");
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new ApiError(400, code, "Timestamp is invalid.");
  }
  return parsed.toISOString();
}

function requiredText(
  value: unknown,
  min: number,
  max: number,
  code: string,
): string {
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Required text field is invalid.");
  }
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) {
    throw new ApiError(400, code, "Required text field is invalid.");
  }
  return normalized;
}

function optionalText(value: unknown, max: number): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, "invalid_request", "Text field is invalid.");
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > max) {
    throw new ApiError(400, "invalid_request", "Text field is invalid.");
  }
  return normalized;
}

async function requestObject(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be a valid JSON object.",
    );
  }
}

export function parseMarketingCampaignQuery(url: URL): MarketingCampaignQuery {
  const page = boundedAdminPage(url.searchParams.get("page"));
  const pageSize = boundedAdminPageSize(
    url.searchParams.get("pageSize"),
    25,
    5,
    100,
  );
  const startsFromUtc = optionalInstant(
    url.searchParams.get("from"),
    "marketing_campaign_date_filter_invalid",
  );
  const startsToUtc = optionalInstant(
    url.searchParams.get("to"),
    "marketing_campaign_date_filter_invalid",
  );
  if (
    startsFromUtc &&
    startsToUtc &&
    new Date(startsToUtc).getTime() < new Date(startsFromUtc).getTime()
  ) {
    throw new ApiError(
      400,
      "marketing_campaign_date_filter_invalid",
      "Campaign start-date range is invalid.",
    );
  }

  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    search: optionalSearch(url.searchParams.get("q")),
    product: optionalCode(
      url.searchParams.get("product"),
      "marketing_campaign_product_invalid",
      "Campaign product filter",
    ),
    status: optionalStatus(url.searchParams.get("status")),
    ownerAdminAccountId: optionalOwner(url.searchParams.get("owner")),
    startsFromUtc,
    startsToUtc,
  };
}

export async function parseMarketingCampaignCreatePayload(
  request: Request,
): Promise<MarketingCampaignCreatePayload> {
  const body = await requestObject(request);
  const startsAtUtc = optionalInstant(
    body.startsAtUtc,
    "marketing_campaign_window_invalid",
  );
  const endsAtUtc = optionalInstant(
    body.endsAtUtc,
    "marketing_campaign_window_invalid",
  );
  if (
    startsAtUtc &&
    endsAtUtc &&
    new Date(endsAtUtc).getTime() < new Date(startsAtUtc).getTime()
  ) {
    throw new ApiError(
      400,
      "marketing_campaign_window_invalid",
      "Campaign end cannot be before its start.",
    );
  }

  return {
    name: requiredText(
      body.name,
      2,
      160,
      "marketing_campaign_name_invalid",
    ),
    objective: optionalText(body.objective, 500),
    productCode: optionalCode(
      typeof body.productCode === "string" ? body.productCode : null,
      "marketing_campaign_product_invalid",
      "Campaign product code",
    ),
    ownerAdminAccountId: body.ownerAdminAccountId == null ||
        body.ownerAdminAccountId === ""
      ? null
      : requireUuid(String(body.ownerAdminAccountId), "ownerAdminAccountId"),
    startsAtUtc,
    endsAtUtc,
    reason: requiredText(
      body.reason,
      10,
      1000,
      "marketing_campaign_reason_invalid",
    ),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function hashCreateMarketingCampaignRequest(
  payload: MarketingCampaignCreatePayload,
): Promise<string> {
  return sha256(`v1\ncreate\n${JSON.stringify(payload)}`);
}
