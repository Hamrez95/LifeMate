import { ApiError } from "./validation.ts";

export type ProductUpdatePolicyMutation = {
  product: "wellmate" | "caremate";
  platform: "android" | "ios" | "web" | "windows" | "macos" | "linux";
  minimumSupportedVersion: string;
  recommendedVersion: string | null;
  mode: "Soft" | "Force";
  reasonCode: "Routine" | "Critical" | "Security" | "BreakingCompatibility";
  messageKey: string | null;
  status: "Active" | "Disabled";
  effectiveAtUtc: string;
  expectedVersion: number;
  reason: string;
};

const VERSION = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/;
const MESSAGE_KEY = /^[a-z][a-z0-9._-]{2,95}$/;

function requiredEnum<T extends string>(
  value: unknown,
  allowed: readonly T[],
  code: string,
): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new ApiError(400, code, "Request value is invalid.");
  }
  return value as T;
}

function version(value: unknown, nullable: boolean): string | null {
  if (nullable && (value == null || value === "")) return null;
  if (typeof value !== "string" || !VERSION.test(value)) {
    throw new ApiError(
      400,
      "update_policy_version_invalid",
      "Version value is invalid.",
    );
  }
  return value;
}

export async function parseProductUpdatePolicyMutation(
  request: Request,
): Promise<ProductUpdatePolicyMutation> {
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be valid JSON.",
    );
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be an object.",
    );
  }
  const body = value as Record<string, unknown>;
  const product = requiredEnum(
    body.product,
    ["wellmate", "caremate"] as const,
    "product_invalid",
  );
  const platform = requiredEnum(
    body.platform,
    ["android", "ios", "web", "windows", "macos", "linux"] as const,
    "platform_invalid",
  );
  const minimumSupportedVersion = version(body.minimumSupportedVersion, false)!;
  const recommendedVersion = version(body.recommendedVersion, true);
  const mode = requiredEnum(
    body.mode,
    ["Soft", "Force"] as const,
    "update_mode_invalid",
  );
  const reasonCode = requiredEnum(
    body.reasonCode,
    ["Routine", "Critical", "Security", "BreakingCompatibility"] as const,
    "update_reason_invalid",
  );
  if (
    mode === "Force" &&
    !["Critical", "Security", "BreakingCompatibility"].includes(reasonCode)
  ) {
    throw new ApiError(
      400,
      "update_mode_invalid",
      "Force update requires a critical, security, or compatibility reason.",
    );
  }
  const status = requiredEnum(
    body.status,
    ["Active", "Disabled"] as const,
    "status_invalid",
  );
  const messageKey = body.messageKey == null || body.messageKey === ""
    ? null
    : body.messageKey;
  if (
    messageKey !== null &&
    (typeof messageKey !== "string" || !MESSAGE_KEY.test(messageKey))
  ) {
    throw new ApiError(400, "message_key_invalid", "Message key is invalid.");
  }
  if (typeof body.effectiveAtUtc !== "string") {
    throw new ApiError(
      400,
      "effective_at_invalid",
      "effectiveAtUtc is required.",
    );
  }
  const effective = new Date(body.effectiveAtUtc);
  if (Number.isNaN(effective.getTime())) {
    throw new ApiError(
      400,
      "effective_at_invalid",
      "effectiveAtUtc is invalid.",
    );
  }
  if (
    !Number.isInteger(body.expectedVersion) || Number(body.expectedVersion) < 0
  ) {
    throw new ApiError(
      400,
      "expected_version_invalid",
      "expectedVersion must be zero or greater.",
    );
  }
  if (
    typeof body.reason !== "string" || body.reason.trim().length < 10 ||
    body.reason.trim().length > 1000
  ) {
    throw new ApiError(
      400,
      "reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }
  return {
    product,
    platform,
    minimumSupportedVersion,
    recommendedVersion,
    mode,
    reasonCode,
    messageKey: messageKey as string | null,
    status,
    effectiveAtUtc: effective.toISOString(),
    expectedVersion: Number(body.expectedVersion),
    reason: body.reason.trim(),
  };
}

export async function hashProductUpdatePolicyMutation(
  input: ProductUpdatePolicyMutation,
): Promise<string> {
  const canonical = JSON.stringify([
    "product-update-policy-v1",
    input.product,
    input.platform,
    input.minimumSupportedVersion,
    input.recommendedVersion,
    input.mode,
    input.reasonCode,
    input.messageKey,
    input.status,
    input.effectiveAtUtc,
    input.expectedVersion,
    input.reason,
  ]);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
