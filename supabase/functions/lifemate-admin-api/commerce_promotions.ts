import {
  ApiError,
  boundedInteger,
  requireUuid,
} from "./validation.ts";

export const promotionStatuses = ["Draft", "Active", "Paused", "Expired"] as const;
export type PromotionStatus = (typeof promotionStatuses)[number];
export const promotionDiscountTypes = ["Percentage", "FixedAmount"] as const;
export type PromotionDiscountType = (typeof promotionDiscountTypes)[number];

export type CommercePromotionsQuery = {
  page: number;
  pageSize: number;
  product: string | null;
  status: PromotionStatus | null;
  q: string | null;
};

export type CreatePromotionPayload = {
  productId: string | null;
  name: string;
  description: string | null;
  discountType: PromotionDiscountType;
  percentageBasisPoints: number | null;
  fixedAmountMinor: string | null;
  currency: string | null;
  startsAtUtc: string;
  endsAtUtc: string | null;
  maxRedemptions: number | null;
  primaryCode: string;
  codeMaxRedemptions: number | null;
  reason: string;
};

export type PromotionStatusPayload = {
  status: "Active" | "Paused";
  reason: string;
};

const PROMOTION_STATUS_PATH = /^\/api\/v1\/commerce\/promotions\/([^/]+)\/actions\/status$/i;
const CODE_PATTERN = /^[A-Z0-9][A-Z0-9._-]{2,63}$/;
const PRODUCT_CODE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;
const AMOUNT_PATTERN = /^\d+$/;

function optionalText(value: unknown, max: number): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || value.trim().length > max) {
    throw new ApiError(400, "invalid_request", "Text field is invalid.");
  }
  return value.trim();
}

function requiredText(value: unknown, min: number, max: number, code: string): string {
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Required text field is invalid.");
  }
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) {
    throw new ApiError(400, code, "Required text field is invalid.");
  }
  return normalized;
}

function optionalPositiveInteger(value: unknown, code: string): number | null {
  if (value == null || value === "") return null;
  if (!Number.isInteger(value) || Number(value) <= 0 || Number(value) > 10_000_000) {
    throw new ApiError(400, code, "Positive integer field is invalid.");
  }
  return Number(value);
}

function requiredInstant(value: unknown, code: string): string {
  if (typeof value !== "string") throw new ApiError(400, code, "Timestamp is invalid.");
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new ApiError(400, code, "Timestamp is invalid.");
  return date.toISOString();
}

function optionalInstant(value: unknown, code: string): string | null {
  if (value == null || value === "") return null;
  return requiredInstant(value, code);
}

export function parseCommercePromotionsQuery(url: URL): CommercePromotionsQuery {
  const statusRaw = url.searchParams.get("status")?.trim() ?? "";
  const productRaw = url.searchParams.get("product")?.trim() ?? "";
  const qRaw = url.searchParams.get("q")?.trim() ?? "";
  if (statusRaw && !promotionStatuses.includes(statusRaw as PromotionStatus)) {
    throw new ApiError(400, "invalid_promotion_status", "Promotion status filter is invalid.");
  }
  if (productRaw && !PRODUCT_CODE_PATTERN.test(productRaw)) {
    throw new ApiError(400, "invalid_product_filter", "Product filter is invalid.");
  }
  if (qRaw.length > 64) {
    throw new ApiError(400, "invalid_promotion_query", "Promotion search is too long.");
  }
  return {
    page: boundedInteger(url.searchParams.get("page"), 1, 1, 100_000),
    pageSize: boundedInteger(url.searchParams.get("pageSize"), 25, 1, 100),
    product: productRaw || null,
    status: statusRaw ? (statusRaw as PromotionStatus) : null,
    q: qRaw || null,
  };
}

export function matchCommercePromotionStatusPath(path: string): string | null {
  const match = PROMOTION_STATUS_PATH.exec(path);
  return match ? requireUuid(match[1], "promotionId") : null;
}

export async function parseCreatePromotionPayload(request: Request): Promise<CreatePromotionPayload> {
  let body: Record<string, unknown>;
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid");
    body = value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be valid JSON object.");
  }

  const discountType = body.discountType;
  if (!promotionDiscountTypes.includes(discountType as PromotionDiscountType)) {
    throw new ApiError(400, "promotion_discount_invalid", "Discount type is invalid.");
  }
  const type = discountType as PromotionDiscountType;
  const productId = body.productId == null || body.productId === ""
    ? null
    : requireUuid(String(body.productId), "productId");
  const primaryCode = requiredText(body.primaryCode, 3, 64, "discount_code_invalid").toUpperCase();
  if (!CODE_PATTERN.test(primaryCode)) {
    throw new ApiError(400, "discount_code_invalid", "Discount code format is invalid.");
  }
  const startsAtUtc = requiredInstant(body.startsAtUtc, "promotion_window_invalid");
  const endsAtUtc = optionalInstant(body.endsAtUtc, "promotion_window_invalid");
  if (endsAtUtc && new Date(endsAtUtc).getTime() <= new Date(startsAtUtc).getTime()) {
    throw new ApiError(400, "promotion_window_invalid", "Promotion end must be after start.");
  }

  let percentageBasisPoints: number | null = null;
  let fixedAmountMinor: string | null = null;
  let currency: string | null = null;
  if (type === "Percentage") {
    const percent = body.percentageBasisPoints;
    if (!Number.isInteger(percent) || Number(percent) < 1 || Number(percent) > 10_000) {
      throw new ApiError(400, "promotion_discount_invalid", "Percentage discount is invalid.");
    }
    percentageBasisPoints = Number(percent);
  } else {
    if (typeof body.fixedAmountMinor !== "string" || !AMOUNT_PATTERN.test(body.fixedAmountMinor) || BigInt(body.fixedAmountMinor) <= 0n) {
      throw new ApiError(400, "promotion_discount_invalid", "Fixed amount discount is invalid.");
    }
    if (typeof body.currency !== "string" || !CURRENCY_PATTERN.test(body.currency)) {
      throw new ApiError(400, "promotion_discount_invalid", "Currency is invalid.");
    }
    fixedAmountMinor = body.fixedAmountMinor;
    currency = body.currency;
  }

  return {
    productId,
    name: requiredText(body.name, 2, 160, "promotion_name_invalid"),
    description: optionalText(body.description, 1000),
    discountType: type,
    percentageBasisPoints,
    fixedAmountMinor,
    currency,
    startsAtUtc,
    endsAtUtc,
    maxRedemptions: optionalPositiveInteger(body.maxRedemptions, "promotion_limit_invalid"),
    primaryCode,
    codeMaxRedemptions: optionalPositiveInteger(body.codeMaxRedemptions, "promotion_limit_invalid"),
    reason: requiredText(body.reason, 10, 1000, "promotion_reason_invalid"),
  };
}

export async function parsePromotionStatusPayload(request: Request): Promise<PromotionStatusPayload> {
  let body: Record<string, unknown>;
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid");
    body = value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be valid JSON object.");
  }
  if (body.status !== "Active" && body.status !== "Paused") {
    throw new ApiError(400, "promotion_status_invalid", "Target promotion status is invalid.");
  }
  return {
    status: body.status,
    reason: requiredText(body.reason, 10, 1000, "promotion_reason_invalid"),
  };
}

async function sha256(canonical: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function hashCreatePromotionRequest(payload: CreatePromotionPayload): Promise<string> {
  return sha256(`v1\ncreate\n${JSON.stringify(payload)}`);
}

export async function hashPromotionStatusRequest(
  promotionId: string,
  payload: PromotionStatusPayload,
): Promise<string> {
  return sha256(`v1\n${promotionId}\n${payload.status}\n${payload.reason}`);
}
