import { ApiError, requireUuid } from "./validation.ts";

export type ConfigureCommerceTrialPayload = {
  durationDays: number;
  eligibilityRule: "NoPriorTrialForProduct";
  status: "Active" | "Disabled";
  expectedVersion: number;
  reason: string;
};

const TRIAL_POLICY_PATH =
  /^\/api\/v1\/commerce\/plans\/([^/]+)\/trial-policy$/i;

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
      "Request body must be valid JSON object.",
    );
  }
}

function requiredReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "trial_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "trial_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  return normalized;
}

function boundedInteger(
  value: unknown,
  code: string,
  minimum: number,
  maximum: number,
): number {
  if (
    !Number.isInteger(value) || Number(value) < minimum ||
    Number(value) > maximum
  ) {
    throw new ApiError(400, code, "Trial configuration value is invalid.");
  }
  return Number(value);
}

export function matchCommerceTrialPolicyPath(path: string): string | null {
  const match = TRIAL_POLICY_PATH.exec(path);
  return match ? requireUuid(match[1], "planId") : null;
}

export async function parseConfigureCommerceTrialPayload(
  request: Request,
): Promise<ConfigureCommerceTrialPayload> {
  const body = await requestObject(request);
  if (body.status !== "Active" && body.status !== "Disabled") {
    throw new ApiError(
      400,
      "trial_status_invalid",
      "Trial policy status is invalid.",
    );
  }
  return {
    durationDays: boundedInteger(
      body.durationDays,
      "trial_duration_invalid",
      1,
      365,
    ),
    eligibilityRule: body.eligibilityRule === "NoPriorTrialForProduct"
      ? body.eligibilityRule
      : (() => {
        throw new ApiError(
          400,
          "trial_eligibility_invalid",
          "Trial eligibility rule is invalid.",
        );
      })(),
    status: body.status,
    expectedVersion: boundedInteger(
      body.expectedVersion,
      "trial_version_invalid",
      0,
      1_000_000_000,
    ),
    reason: requiredReason(body.reason),
  };
}

export async function hashConfigureCommerceTrialRequest(
  planId: string,
  payload: ConfigureCommerceTrialPayload,
): Promise<string> {
  const canonical = [
    "v1",
    "commerce.trial.configure",
    planId,
    payload.durationDays,
    payload.eligibilityRule,
    payload.status,
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
