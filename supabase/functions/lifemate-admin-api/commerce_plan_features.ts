import { ApiError, requireUuid } from "./validation.ts";

export type ConfigureCommercePlanFeaturePayload = {
  featureId: string;
  assigned: boolean;
  expectedVersion: number;
  reason: string;
};

const PLAN_FEATURES_PATH =
  /^\/api\/v1\/commerce\/plans\/([^/]+)\/features$/i;

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

function requiredReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "plan_feature_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "plan_feature_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  return normalized;
}

function expectedVersion(value: unknown): number {
  if (
    !Number.isInteger(value) || Number(value) < 0 ||
    Number(value) > 1_000_000_000
  ) {
    throw new ApiError(
      400,
      "plan_feature_version_invalid",
      "Plan feature version is invalid.",
    );
  }
  return Number(value);
}

export function matchCommercePlanFeaturesPath(path: string): string | null {
  const match = PLAN_FEATURES_PATH.exec(path);
  return match ? requireUuid(match[1], "planId") : null;
}

export async function parseConfigureCommercePlanFeaturePayload(
  request: Request,
): Promise<ConfigureCommercePlanFeaturePayload> {
  const body = await requestObject(request);
  if (typeof body.assigned !== "boolean") {
    throw new ApiError(
      400,
      "plan_feature_assignment_invalid",
      "Plan feature assignment state is invalid.",
    );
  }
  return {
    featureId: requireUuid(body.featureId, "featureId"),
    assigned: body.assigned,
    expectedVersion: expectedVersion(body.expectedVersion),
    reason: requiredReason(body.reason),
  };
}

export async function hashConfigureCommercePlanFeatureRequest(
  planId: string,
  payload: ConfigureCommercePlanFeaturePayload,
): Promise<string> {
  const canonical = [
    "v1",
    "commerce.plan_feature.configure",
    planId,
    payload.featureId,
    payload.assigned ? "assigned" : "unassigned",
    payload.expectedVersion,
    payload.reason,
  ].join("\n");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
