import {
  ApiError,
  boundedAdminPage,
  boundedAdminPageSize,
  requireUuid,
} from "./validation.ts";

export const promotionStatuses = ["Draft", "Active", "Paused", "Expired"] as const;
export type PromotionStatus = (typeof promotionStatuses)[number];
export const promotionDiscountTypes = ["Percentage", "FixedAmount"] as const;
export type PromotionDiscountType = (typeof promotionDiscountTypes)[number];
export const discountCodeStatuses = ["Active", "Disabled"] as const;
export type DiscountCodeStatus = (typeof discountCodeStatuses)[number];

export type CommercePromotionsQuery = {
  page: number;
  pageSize: number;
  product: string | null;
  status: PromotionStatus | null;
  q: string | null;
  exactCode: string | null;
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

export type UpdatePromotionPayload = CreatePromotionPayload & {
  codeStatus: DiscountCodeStatus;
};

export type PromotionStatusPayload = {
  status: "Active" | "Paused";
  reason: string;
};

export type IssueDiscountCodesPayload = {
  explicitCodes: string[] | null;
  generateCount: number | null;
  prefix: string | null;
  maxRedemptions: number | null;
  reason: string;
};

export type DiscountCodeStatusPayload = {
  status: DiscountCodeStatus;
  expectedVersion: number;
  reason: string;
};

const PROMOTION_DETAIL_PATH = /^\/api\/v1\/commerce\/promotions\/([^/]+)$/i;
const PROMOTION_STATUS_PATH = /^\/api\/v1\/commerce\/promotions\/([^/]+)\/actions\/status$/i;
const PROMOTION_CODES_PATH = /^\/api\/v1\/commerce\/promotions\/([^/]+)\/discount-codes$/i;
const PROMOTION_CODE_STATUS_PATH = /^\/api\/v1\/commerce\/promotions\/([^/]+)\/discount-codes\/([^/]+)\/actions\/status$/i;
const CODE_PATTERN = /^[A-Z0-9][A-Z0-9._-]{2,63}$/;
const PREFIX_PATTERN = /^[A-Z0-9][A-Z0-9._-]{0,19}$/;
const PRODUCT_CODE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;
const AMOUNT_PATTERN = /^\d+$/;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;

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

function parseFixedAmount(value: unknown): string {
  if (typeof value !== "string" || !AMOUNT_PATTERN.test(value)) {
    throw new ApiError(400, "promotion_discount_invalid", "Fixed amount discount is invalid.");
  }
  const parsed = BigInt(value);
  if (parsed <= 0n || parsed > POSTGRES_BIGINT_MAX) {
    throw new ApiError(400, "promotion_discount_invalid", "Fixed amount discount is outside the supported range.");
  }
  return parsed.toString();
}

async function requestObject(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid");
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be valid JSON object.");
  }
}

function parseSharedPayload(body: Record<string, unknown>): CreatePromotionPayload {
  const discountType = body.discountType;
  if (!promotionDiscountTypes.includes(discountType as PromotionDiscountType)) {
    throw new ApiError(400, "promotion_discount_invalid", "Discount type is invalid.");
  }
  const type = discountType as PromotionDiscountType;
  const productId = body.productId == null || body.productId === "" ? null : requireUuid(String(body.productId), "productId");
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
    if (!Number.isInteger(percent) || Number(percent) < 1 || Number(percent) > 10_000 || body.fixedAmountMinor != null || body.currency != null) {
      throw new ApiError(400, "promotion_discount_invalid", "Percentage discount is invalid.");
    }
    percentageBasisPoints = Number(percent);
  } else {
    fixedAmountMinor = parseFixedAmount(body.fixedAmountMinor);
    if (typeof body.currency !== "string" || !CURRENCY_PATTERN.test(body.currency)) {
      throw new ApiError(400, "promotion_discount_invalid", "Currency is invalid.");
    }
    if (body.percentageBasisPoints != null) {
      throw new ApiError(400, "promotion_discount_invalid", "Fixed-amount promotion cannot include percentageBasisPoints.");
    }
    currency = body.currency;
  }

  const maxRedemptions = optionalPositiveInteger(body.maxRedemptions, "promotion_limit_invalid");
  const codeMaxRedemptions = optionalPositiveInteger(body.codeMaxRedemptions, "promotion_limit_invalid");
  if (maxRedemptions != null && codeMaxRedemptions != null && codeMaxRedemptions > maxRedemptions) {
    throw new ApiError(400, "promotion_limit_invalid", "Discount-code limit cannot exceed promotion limit.");
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
    maxRedemptions,
    primaryCode,
    codeMaxRedemptions,
    reason: requiredText(body.reason, 10, 1000, "promotion_reason_invalid"),
  };
}

export function parseCommercePromotionsQuery(url: URL): CommercePromotionsQuery {
  const statusRaw = url.searchParams.get("status")?.trim() ?? "";
  const productRaw = url.searchParams.get("product")?.trim() ?? "";
  const qRaw = url.searchParams.get("q")?.trim() ?? "";
  const codeRaw = url.searchParams.get("code")?.trim().toUpperCase() ?? "";
  if (statusRaw && !promotionStatuses.includes(statusRaw as PromotionStatus)) {
    throw new ApiError(400, "invalid_promotion_status", "Promotion status filter is invalid.");
  }
  if (productRaw && !PRODUCT_CODE_PATTERN.test(productRaw)) {
    throw new ApiError(400, "invalid_product_filter", "Product filter is invalid.");
  }
  if (qRaw.length > 80) throw new ApiError(400, "invalid_promotion_query", "Promotion search is too long.");
  if (codeRaw && !CODE_PATTERN.test(codeRaw)) {
    throw new ApiError(400, "invalid_discount_code_filter", "Exact discount-code filter is invalid.");
  }
  return {
    page: boundedAdminPage(url.searchParams.get("page")),
    pageSize: boundedAdminPageSize(url.searchParams.get("pageSize"), 25),
    product: productRaw || null,
    status: statusRaw ? (statusRaw as PromotionStatus) : null,
    q: qRaw || null,
    exactCode: codeRaw || null,
  };
}

export function matchCommercePromotionDetailPath(path: string): string | null {
  const match = PROMOTION_DETAIL_PATH.exec(path);
  return match ? requireUuid(match[1], "promotionId") : null;
}

export function matchCommercePromotionStatusPath(path: string): string | null {
  const match = PROMOTION_STATUS_PATH.exec(path);
  return match ? requireUuid(match[1], "promotionId") : null;
}

export function matchCommercePromotionCodesPath(path: string): string | null {
  const match = PROMOTION_CODES_PATH.exec(path);
  return match ? requireUuid(match[1], "promotionId") : null;
}

export function matchCommerceDiscountCodeStatusPath(path: string): { promotionId: string; codeId: string } | null {
  const match = PROMOTION_CODE_STATUS_PATH.exec(path);
  return match ? {
    promotionId: requireUuid(match[1], "promotionId"),
    codeId: requireUuid(match[2], "codeId"),
  } : null;
}

export async function parseCreatePromotionPayload(request: Request): Promise<CreatePromotionPayload> {
  return parseSharedPayload(await requestObject(request));
}

export async function parseUpdatePromotionPayload(request: Request): Promise<UpdatePromotionPayload> {
  const body = await requestObject(request);
  const shared = parseSharedPayload(body);
  if (!discountCodeStatuses.includes(body.codeStatus as DiscountCodeStatus)) {
    throw new ApiError(400, "discount_code_status_invalid", "Discount-code status is invalid.");
  }
  return { ...shared, codeStatus: body.codeStatus as DiscountCodeStatus };
}

export async function parsePromotionStatusPayload(request: Request): Promise<PromotionStatusPayload> {
  const body = await requestObject(request);
  if (body.status !== "Active" && body.status !== "Paused") {
    throw new ApiError(400, "promotion_status_invalid", "Target promotion status is invalid.");
  }
  return {
    status: body.status,
    reason: requiredText(body.reason, 10, 1000, "promotion_reason_invalid"),
  };
}

export async function parseIssueDiscountCodesPayload(request: Request): Promise<IssueDiscountCodesPayload> {
  const body = await requestObject(request);
  const rawCodes = body.codes;
  const hasExplicit = Array.isArray(rawCodes) && rawCodes.length > 0;
  const hasGenerated = body.generateCount != null;
  if (hasExplicit === hasGenerated) {
    throw new ApiError(400, "discount_code_mode_invalid", "Choose explicit codes or generated codes.");
  }

  let explicitCodes: string[] | null = null;
  let generateCount: number | null = null;
  let prefix: string | null = null;
  if (hasExplicit) {
    if (!Array.isArray(rawCodes) || rawCodes.length > 50) {
      throw new ApiError(400, "discount_code_batch_too_large", "At most 50 discount codes may be issued per request.");
    }
    explicitCodes = rawCodes.map((value) => {
      if (typeof value !== "string") throw new ApiError(400, "discount_code_invalid", "Discount code is invalid.");
      const code = value.trim().toUpperCase();
      if (!CODE_PATTERN.test(code)) throw new ApiError(400, "discount_code_invalid", "Discount code is invalid.");
      return code;
    });
    if (new Set(explicitCodes).size !== explicitCodes.length) {
      throw new ApiError(400, "discount_code_duplicate", "The request contains a duplicate discount code.");
    }
  } else {
    if (!Number.isInteger(body.generateCount) || Number(body.generateCount) < 1 || Number(body.generateCount) > 50) {
      throw new ApiError(400, "discount_code_batch_invalid", "Generated discount-code count must be between 1 and 50.");
    }
    generateCount = Number(body.generateCount);
    const rawPrefix = body.prefix == null || body.prefix === "" ? null : String(body.prefix).trim().toUpperCase();
    if (rawPrefix && !PREFIX_PATTERN.test(rawPrefix)) {
      throw new ApiError(400, "discount_code_prefix_invalid", "Discount-code prefix is invalid.");
    }
    prefix = rawPrefix;
  }

  return {
    explicitCodes,
    generateCount,
    prefix,
    maxRedemptions: optionalPositiveInteger(body.maxRedemptions, "discount_code_limit_invalid"),
    reason: requiredText(body.reason, 10, 1000, "discount_code_reason_invalid"),
  };
}

export async function parseDiscountCodeStatusPayload(request: Request): Promise<DiscountCodeStatusPayload> {
  const body = await requestObject(request);
  if (!discountCodeStatuses.includes(body.status as DiscountCodeStatus)) {
    throw new ApiError(400, "discount_code_status_invalid", "Discount-code status is invalid.");
  }
  if (!Number.isInteger(body.expectedVersion) || Number(body.expectedVersion) < 1) {
    throw new ApiError(400, "discount_code_version_invalid", "Expected discount-code version is invalid.");
  }
  return {
    status: body.status as DiscountCodeStatus,
    expectedVersion: Number(body.expectedVersion),
    reason: requiredText(body.reason, 10, 1000, "discount_code_reason_invalid"),
  };
}

async function sha256(canonical: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function hashCreatePromotionRequest(payload: CreatePromotionPayload): Promise<string> {
  return sha256(`v1\ncreate\n${JSON.stringify(payload)}`);
}

export async function hashUpdatePromotionRequest(promotionId: string, payload: UpdatePromotionPayload): Promise<string> {
  return sha256(`v1\nupdate\n${promotionId}\n${JSON.stringify(payload)}`);
}

export async function hashPromotionStatusRequest(promotionId: string, payload: PromotionStatusPayload): Promise<string> {
  return sha256(`v1\nstatus\n${promotionId}\n${payload.status}\n${payload.reason}`);
}

export async function hashIssueDiscountCodesRequest(promotionId: string, payload: IssueDiscountCodesPayload): Promise<string> {
  return sha256(`v1\ndiscount-code-issue\n${promotionId}\n${JSON.stringify(payload)}`);
}

export async function hashDiscountCodeStatusRequest(promotionId: string, codeId: string, payload: DiscountCodeStatusPayload): Promise<string> {
  return sha256(`v1\ndiscount-code-status\n${promotionId}\n${codeId}\n${JSON.stringify(payload)}`);
}
