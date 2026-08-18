import { ApiError, requireUuid } from "./validation.ts";

export type CreateCommercePlanPayload = {
  productId: string;
  code: string;
  name: string;
  reason: string;
};

export type UpdateCommercePlanPayload = {
  name: string;
  status: "Active" | "Retired";
  reason: string;
};

export type ScheduleCommercePricePayload = {
  countryCode: string | null;
  currency: string;
  storeProvider: string;
  billingPeriodMonths: number;
  amountMinor: string;
  effectiveFromUtc: string;
  reason: string;
};

const PLAN_DETAIL_PATH = /^\/api\/v1\/commerce\/plans\/([^/]+)$/i;
const PLAN_PRICES_PATH = /^\/api\/v1\/commerce\/plans\/([^/]+)\/prices$/i;
const PLAN_CODE_PATTERN = /^[a-z0-9][a-z0-9._-]{1,63}$/;
const COUNTRY_PATTERN = /^[A-Z]{2}$/;
const CURRENCY_PATTERN = /^[A-Z]{3}$/;
const PROVIDER_PATTERN = /^[a-z0-9][a-z0-9._:-]{1,39}$/;
const AMOUNT_PATTERN = /^\d+$/;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;

async function requestObject(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be a valid JSON object.");
  }
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

function instant(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "price_effective_time_invalid", "Price effective time is invalid.");
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new ApiError(400, "price_effective_time_invalid", "Price effective time is invalid.");
  }
  return parsed.toISOString();
}

function amountMinor(value: unknown): string {
  if (typeof value !== "string" || !AMOUNT_PATTERN.test(value)) {
    throw new ApiError(400, "price_amount_invalid", "Price amount must be a non-negative minor-unit integer string.");
  }
  const parsed = BigInt(value);
  if (parsed < 0n || parsed > POSTGRES_BIGINT_MAX) {
    throw new ApiError(400, "price_amount_invalid", "Price amount is outside the supported range.");
  }
  return parsed.toString();
}

export function matchCommerceCatalogPlanPath(path: string): string | null {
  const match = PLAN_DETAIL_PATH.exec(path);
  return match ? requireUuid(match[1], "planId") : null;
}

export function matchCommercePlanPricesPath(path: string): string | null {
  const match = PLAN_PRICES_PATH.exec(path);
  return match ? requireUuid(match[1], "planId") : null;
}

export async function parseCreateCommercePlanPayload(
  request: Request,
): Promise<CreateCommercePlanPayload> {
  const body = await requestObject(request);
  const code = requiredText(body.code, 2, 64, "plan_code_invalid").toLowerCase();
  if (!PLAN_CODE_PATTERN.test(code)) {
    throw new ApiError(400, "plan_code_invalid", "Plan code is invalid.");
  }
  return {
    productId: requireUuid(body.productId, "productId"),
    code,
    name: requiredText(body.name, 2, 120, "plan_name_invalid"),
    reason: requiredText(body.reason, 10, 1000, "plan_reason_invalid"),
  };
}

export async function parseUpdateCommercePlanPayload(
  request: Request,
): Promise<UpdateCommercePlanPayload> {
  const body = await requestObject(request);
  if (body.status !== "Active" && body.status !== "Retired") {
    throw new ApiError(400, "plan_status_invalid", "Plan status is invalid.");
  }
  return {
    name: requiredText(body.name, 2, 120, "plan_name_invalid"),
    status: body.status,
    reason: requiredText(body.reason, 10, 1000, "plan_reason_invalid"),
  };
}

export async function parseScheduleCommercePricePayload(
  request: Request,
): Promise<ScheduleCommercePricePayload> {
  const body = await requestObject(request);

  let countryCode: string | null = null;
  if (body.countryCode != null && body.countryCode !== "") {
    if (typeof body.countryCode !== "string") {
      throw new ApiError(400, "price_country_invalid", "Country code is invalid.");
    }
    countryCode = body.countryCode.trim().toUpperCase();
    if (!COUNTRY_PATTERN.test(countryCode)) {
      throw new ApiError(400, "price_country_invalid", "Country code is invalid.");
    }
  }

  const currency = requiredText(body.currency, 3, 3, "price_currency_invalid").toUpperCase();
  if (!CURRENCY_PATTERN.test(currency)) {
    throw new ApiError(400, "price_currency_invalid", "Currency is invalid.");
  }

  const storeProvider = requiredText(body.storeProvider, 2, 40, "price_provider_invalid").toLowerCase();
  if (!PROVIDER_PATTERN.test(storeProvider)) {
    throw new ApiError(400, "price_provider_invalid", "Store provider is invalid.");
  }

  if (
    !Number.isInteger(body.billingPeriodMonths) ||
    Number(body.billingPeriodMonths) < 1 ||
    Number(body.billingPeriodMonths) > 120
  ) {
    throw new ApiError(400, "price_period_invalid", "Billing period is invalid.");
  }

  return {
    countryCode,
    currency,
    storeProvider,
    billingPeriodMonths: Number(body.billingPeriodMonths),
    amountMinor: amountMinor(body.amountMinor),
    effectiveFromUtc: instant(body.effectiveFromUtc),
    reason: requiredText(body.reason, 10, 1000, "price_reason_invalid"),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}

export async function hashCreateCommercePlanRequest(
  payload: CreateCommercePlanPayload,
): Promise<string> {
  return sha256(`v1\ncommerce.plan.create\n${JSON.stringify(payload)}`);
}

export async function hashUpdateCommercePlanRequest(
  planId: string,
  payload: UpdateCommercePlanPayload,
): Promise<string> {
  return sha256(`v1\ncommerce.plan.update\n${planId}\n${JSON.stringify(payload)}`);
}

export async function hashScheduleCommercePriceRequest(
  planId: string,
  payload: ScheduleCommercePricePayload,
): Promise<string> {
  return sha256(`v1\ncommerce.price.schedule\n${planId}\n${JSON.stringify(payload)}`);
}
