import { ApiError, requireUuid } from "./validation.ts";

export type CatalogLifecycle = "Hidden" | "Published" | "Retired";

export type UpdateCatalogProductPayload = {
  name: string;
  status: CatalogLifecycle;
  expectedVersion: number;
  reason: string;
};

export type CreateCatalogOfferPayload = {
  productId: string;
  code: string;
  name: string;
  durationMonths: number;
  status: CatalogLifecycle;
  giftEligible: boolean;
  reason: string;
};

export type UpdateCatalogOfferPayload = {
  name: string;
  durationMonths: number;
  status: CatalogLifecycle;
  giftEligible: boolean;
  expectedVersion: number;
  reason: string;
};

export type ScheduleOfferPricePayload = {
  countryCode: string | null;
  currency: string;
  storeProvider: string;
  amountMinor: string;
  effectiveFromUtc: string;
  reason: string;
};

export type UpsertCatalogPolicyPayload = {
  valueType: "integer" | "boolean" | "string" | "json";
  value: unknown;
  status: "Active" | "Retired";
  expectedVersion: number | null;
  reason: string;
};

export type CreateCatalogBundlePayload = {
  code: string;
  name: string;
  status: CatalogLifecycle;
  giftEligible: boolean;
  offerIds: string[];
  reason: string;
};

export type UpdateCatalogBundlePayload = {
  name: string;
  status: CatalogLifecycle;
  giftEligible: boolean;
  offerIds: string[];
  expectedVersion: number;
  reason: string;
};

const PRODUCT_PATH = /^\/api\/v1\/commerce\/catalog-v2\/products\/([^/]+)$/i;
const OFFER_CREATE_PATH = /^\/api\/v1\/commerce\/catalog-v2\/offers$/i;
const OFFER_PATH = /^\/api\/v1\/commerce\/catalog-v2\/offers\/([^/]+)$/i;
const OFFER_PRICES_PATH =
  /^\/api\/v1\/commerce\/catalog-v2\/offers\/([^/]+)\/prices$/i;
const POLICY_PATH =
  /^\/api\/v1\/commerce\/catalog-v2\/products\/([^/]+)\/policies\/([^/]+)$/i;
const BUNDLE_CREATE_PATH = /^\/api\/v1\/commerce\/catalog-v2\/bundles$/i;
const BUNDLE_PATH = /^\/api\/v1\/commerce\/catalog-v2\/bundles\/([^/]+)$/i;
const CODE = /^[a-z0-9][a-z0-9._-]{1,63}$/;
const POLICY_KEY = /^[a-z0-9][a-z0-9._-]{1,127}$/;
const COUNTRY = /^[A-Z]{2}$/;
const CURRENCY = /^[A-Z]{3}$/;
const PROVIDER = /^[a-z0-9][a-z0-9._:-]{1,39}$/;
const AMOUNT = /^\d+$/;
const BIGINT_MAX = 9_223_372_036_854_775_807n;

async function objectBody(request: Request): Promise<Record<string, unknown>> {
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

function text(value: unknown, min: number, max: number, code: string): string {
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Required text field is invalid.");
  }
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) {
    throw new ApiError(400, code, "Required text field is invalid.");
  }
  return normalized;
}

function version(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new ApiError(
      400,
      "catalog_version_invalid",
      "Expected version is invalid.",
    );
  }
  return Number(value);
}

function lifecycle(value: unknown): CatalogLifecycle {
  if (value !== "Hidden" && value !== "Published" && value !== "Retired") {
    throw new ApiError(
      400,
      "catalog_status_invalid",
      "Catalog lifecycle status is invalid.",
    );
  }
  return value;
}

function bool(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") {
    throw new ApiError(400, code, "Boolean field is invalid.");
  }
  return value;
}

function instant(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "price_effective_time_invalid",
      "Price effective time is invalid.",
    );
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new ApiError(
      400,
      "price_effective_time_invalid",
      "Price effective time is invalid.",
    );
  }
  return parsed.toISOString();
}

function amountMinor(value: unknown): string {
  if (typeof value !== "string" || !AMOUNT.test(value)) {
    throw new ApiError(
      400,
      "price_amount_invalid",
      "Price amount must be a non-negative minor-unit integer string.",
    );
  }
  const parsed = BigInt(value);
  if (parsed < 0n || parsed > BIGINT_MAX) {
    throw new ApiError(
      400,
      "price_amount_invalid",
      "Price amount is outside the supported range.",
    );
  }
  return parsed.toString();
}

function reason(value: unknown): string {
  return text(value, 10, 1000, "catalog_reason_invalid");
}

function offerIds(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 32) {
    throw new ApiError(
      400,
      "catalog_bundle_items_invalid",
      "Bundle must contain between 1 and 32 offers.",
    );
  }
  const ids = value.map((item) => requireUuid(item, "offerId"));
  if (new Set(ids).size !== ids.length) {
    throw new ApiError(
      400,
      "catalog_bundle_items_duplicate",
      "Bundle offers must be unique.",
    );
  }
  return ids;
}

export function matchCatalogProductPath(path: string): string | null {
  const match = PRODUCT_PATH.exec(path);
  return match ? requireUuid(match[1], "productId") : null;
}
export function isCatalogOfferCreatePath(path: string): boolean {
  return OFFER_CREATE_PATH.test(path);
}
export function matchCatalogOfferPath(path: string): string | null {
  const match = OFFER_PATH.exec(path);
  return match ? requireUuid(match[1], "offerId") : null;
}
export function matchCatalogOfferPricesPath(path: string): string | null {
  const match = OFFER_PRICES_PATH.exec(path);
  return match ? requireUuid(match[1], "offerId") : null;
}
export function matchCatalogPolicyPath(
  path: string,
): { productId: string; policyKey: string } | null {
  const match = POLICY_PATH.exec(path);
  if (!match) return null;
  const policyKey = decodeURIComponent(match[2]).trim().toLowerCase();
  if (!POLICY_KEY.test(policyKey)) {
    throw new ApiError(
      400,
      "catalog_policy_key_invalid",
      "Catalog policy key is invalid.",
    );
  }
  return { productId: requireUuid(match[1], "productId"), policyKey };
}
export function isCatalogBundleCreatePath(path: string): boolean {
  return BUNDLE_CREATE_PATH.test(path);
}
export function matchCatalogBundlePath(path: string): string | null {
  const match = BUNDLE_PATH.exec(path);
  return match ? requireUuid(match[1], "bundleId") : null;
}

export async function parseUpdateCatalogProduct(
  request: Request,
): Promise<UpdateCatalogProductPayload> {
  const body = await objectBody(request);
  return {
    name: text(body.name, 2, 120, "catalog_product_name_invalid"),
    status: lifecycle(body.status),
    expectedVersion: version(body.expectedVersion),
    reason: reason(body.reason),
  };
}

export async function parseCreateCatalogOffer(
  request: Request,
): Promise<CreateCatalogOfferPayload> {
  const body = await objectBody(request);
  const code = text(body.code, 2, 64, "catalog_offer_code_invalid")
    .toLowerCase();
  if (!CODE.test(code)) {
    throw new ApiError(
      400,
      "catalog_offer_code_invalid",
      "Offer code is invalid.",
    );
  }
  if (
    !Number.isInteger(body.durationMonths) || Number(body.durationMonths) < 1 ||
    Number(body.durationMonths) > 120
  ) {
    throw new ApiError(
      400,
      "catalog_offer_duration_invalid",
      "Offer duration is invalid.",
    );
  }
  return {
    productId: requireUuid(body.productId, "productId"),
    code,
    name: text(body.name, 2, 120, "catalog_offer_name_invalid"),
    durationMonths: Number(body.durationMonths),
    status: lifecycle(body.status),
    giftEligible: bool(body.giftEligible, "catalog_offer_gift_invalid"),
    reason: reason(body.reason),
  };
}

export async function parseUpdateCatalogOffer(
  request: Request,
): Promise<UpdateCatalogOfferPayload> {
  const body = await objectBody(request);
  if (
    !Number.isInteger(body.durationMonths) || Number(body.durationMonths) < 1 ||
    Number(body.durationMonths) > 120
  ) {
    throw new ApiError(
      400,
      "catalog_offer_duration_invalid",
      "Offer duration is invalid.",
    );
  }
  return {
    name: text(body.name, 2, 120, "catalog_offer_name_invalid"),
    durationMonths: Number(body.durationMonths),
    status: lifecycle(body.status),
    giftEligible: bool(body.giftEligible, "catalog_offer_gift_invalid"),
    expectedVersion: version(body.expectedVersion),
    reason: reason(body.reason),
  };
}

export async function parseScheduleOfferPrice(
  request: Request,
): Promise<ScheduleOfferPricePayload> {
  const body = await objectBody(request);
  let countryCode: string | null = null;
  if (body.countryCode != null && body.countryCode !== "") {
    if (typeof body.countryCode !== "string") {
      throw new ApiError(
        400,
        "price_country_invalid",
        "Country code is invalid.",
      );
    }
    countryCode = body.countryCode.trim().toUpperCase();
    if (!COUNTRY.test(countryCode)) {
      throw new ApiError(
        400,
        "price_country_invalid",
        "Country code is invalid.",
      );
    }
  }
  const currency = text(body.currency, 3, 3, "price_currency_invalid")
    .toUpperCase();
  if (!CURRENCY.test(currency)) {
    throw new ApiError(400, "price_currency_invalid", "Currency is invalid.");
  }
  const storeProvider = text(
    body.storeProvider,
    2,
    40,
    "price_provider_invalid",
  ).toLowerCase();
  if (!PROVIDER.test(storeProvider)) {
    throw new ApiError(
      400,
      "price_provider_invalid",
      "Store provider is invalid.",
    );
  }
  return {
    countryCode,
    currency,
    storeProvider,
    amountMinor: amountMinor(body.amountMinor),
    effectiveFromUtc: instant(body.effectiveFromUtc),
    reason: reason(body.reason),
  };
}

function policyValue(
  valueType: UpsertCatalogPolicyPayload["valueType"],
  value: unknown,
): unknown {
  if (valueType === "integer") {
    if (!Number.isSafeInteger(value) || Number(value) < 0) {
      throw new ApiError(
        400,
        "catalog_policy_value_invalid",
        "Integer policy value is invalid.",
      );
    }
    return Number(value);
  }
  if (valueType === "boolean") {
    if (typeof value !== "boolean") {
      throw new ApiError(
        400,
        "catalog_policy_value_invalid",
        "Boolean policy value is invalid.",
      );
    }
    return value;
  }
  if (valueType === "string") {
    return text(value, 1, 512, "catalog_policy_value_invalid");
  }
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "catalog_policy_value_invalid",
      "JSON policy value is invalid.",
    );
  }
  return value;
}

export async function parseUpsertCatalogPolicy(
  request: Request,
): Promise<UpsertCatalogPolicyPayload> {
  const body = await objectBody(request);
  if (
    body.valueType !== "integer" && body.valueType !== "boolean" &&
    body.valueType !== "string" && body.valueType !== "json"
  ) {
    throw new ApiError(
      400,
      "catalog_policy_type_invalid",
      "Catalog policy value type is invalid.",
    );
  }
  if (body.status !== "Active" && body.status !== "Retired") {
    throw new ApiError(
      400,
      "catalog_policy_status_invalid",
      "Catalog policy status is invalid.",
    );
  }
  return {
    valueType: body.valueType,
    value: policyValue(body.valueType, body.value),
    status: body.status,
    expectedVersion: body.expectedVersion == null
      ? null
      : version(body.expectedVersion),
    reason: reason(body.reason),
  };
}

export async function parseCreateCatalogBundle(
  request: Request,
): Promise<CreateCatalogBundlePayload> {
  const body = await objectBody(request);
  const code = text(body.code, 2, 64, "catalog_bundle_code_invalid")
    .toLowerCase();
  if (!CODE.test(code)) {
    throw new ApiError(
      400,
      "catalog_bundle_code_invalid",
      "Bundle code is invalid.",
    );
  }
  return {
    code,
    name: text(body.name, 2, 120, "catalog_bundle_name_invalid"),
    status: lifecycle(body.status),
    giftEligible: bool(body.giftEligible, "catalog_bundle_gift_invalid"),
    offerIds: offerIds(body.offerIds),
    reason: reason(body.reason),
  };
}

export async function parseUpdateCatalogBundle(
  request: Request,
): Promise<UpdateCatalogBundlePayload> {
  const body = await objectBody(request);
  return {
    name: text(body.name, 2, 120, "catalog_bundle_name_invalid"),
    status: lifecycle(body.status),
    giftEligible: bool(body.giftEligible, "catalog_bundle_gift_invalid"),
    offerIds: offerIds(body.offerIds),
    expectedVersion: version(body.expectedVersion),
    reason: reason(body.reason),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((part) =>
    part.toString(16).padStart(2, "0")
  ).join("");
}

export function hashCatalogMutation(
  operation: string,
  resourceId: string | null,
  payload: unknown,
): Promise<string> {
  return sha256(
    `v1\n${operation}\n${resourceId ?? ""}\n${JSON.stringify(payload)}`,
  );
}
