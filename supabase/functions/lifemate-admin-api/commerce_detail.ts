import { ApiError, boundedInteger, requireUuid } from "./validation.ts";

export type CommerceDetailQuery = {
  page: number;
  pageSize: number;
  offset: number;
};

const PLAN_PATH = /^\/api\/v1\/commerce\/plans\/([^/]+)$/i;
const ENTITLEMENT_PATH = /^\/api\/v1\/commerce\/entitlements\/([^/]+)$/i;
const FEATURE_CODE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;

export function matchCommercePlanDetailPath(path: string): string | null {
  const match = PLAN_PATH.exec(path);
  if (!match) return null;
  return requireUuid(match[1], "planId");
}

export function matchCommerceEntitlementDetailPath(
  path: string,
): string | null {
  const match = ENTITLEMENT_PATH.exec(path);
  if (!match) return null;

  let featureCode: string;
  try {
    featureCode = decodeURIComponent(match[1]).trim();
  } catch {
    throw new ApiError(
      400,
      "commerce_feature_invalid",
      "Commerce feature code is invalid.",
    );
  }

  if (!FEATURE_CODE.test(featureCode)) {
    throw new ApiError(
      400,
      "commerce_feature_invalid",
      "Commerce feature code is invalid.",
    );
  }
  return featureCode;
}

export function parseCommerceDetailQuery(url: URL): CommerceDetailQuery {
  const page = boundedInteger(url.searchParams.get("page"), 1, 1, 100_000);
  const pageSize = boundedInteger(url.searchParams.get("pageSize"), 25, 5, 100);
  return { page, pageSize, offset: (page - 1) * pageSize };
}
