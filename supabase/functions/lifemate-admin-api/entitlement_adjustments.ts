import { ApiError } from "./validation.ts";

export type EntitlementAdjustmentPayload = {
  accountId: string;
  targetType: "Product" | "Offer";
  targetId: string;
  action: "Grant" | "Extend" | "Reduce" | "Revoke";
  scheduleMode: "ExactExpiry" | "AddDays" | "AddMonths" | "Immediate";
  scheduleAmount: number | null;
  exactExpiresAtUtc: string | null;
  reason: string;
  confirmed: boolean;
  approvalRequestId: string | null;
  approvalExpectedVersion: number | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TARGET_TYPES = new Set(["Product", "Offer"]);
const ACTIONS = new Set(["Grant", "Extend", "Reduce", "Revoke"]);
const SCHEDULE_MODES = new Set(["ExactExpiry", "AddDays", "AddMonths", "Immediate"]);

async function bodyObject(request: Request): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid");
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "json_invalid", "Request body must be a valid JSON object.");
  }
}

function uuid(value: unknown, field: string, nullable = false): string | null {
  if (nullable && (value === null || value === undefined || value === "")) return null;
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return value.toLowerCase();
}

function integer(
  value: unknown,
  field: string,
  min: number,
  max: number,
  nullable = false,
): number | null {
  if (nullable && (value === null || value === undefined)) return null;
  if (!Number.isSafeInteger(value) || Number(value) < min || Number(value) > max) {
    throw new ApiError(400, `${field}_invalid`, `${field} is outside the allowed range.`);
  }
  return Number(value);
}

function boundedReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "reason_invalid", "A meaningful reason is required.");
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(400, "reason_invalid", "Reason must be between 10 and 1000 characters.");
  }
  return normalized;
}

function exactExpiry(value: unknown): string | null {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, "exact_expires_at_invalid", "exactExpiresAtUtc is invalid.");
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new ApiError(400, "exact_expires_at_invalid", "exactExpiresAtUtc is invalid.");
  }
  return parsed.toISOString();
}

export async function parseEntitlementAdjustmentPayload(
  request: Request,
): Promise<EntitlementAdjustmentPayload> {
  const body = await bodyObject(request);
  const targetType = String(body.targetType ?? "");
  const action = String(body.action ?? "");
  const scheduleMode = String(body.scheduleMode ?? "");

  if (!TARGET_TYPES.has(targetType)) {
    throw new ApiError(400, "target_type_invalid", "targetType is invalid.");
  }
  if (!ACTIONS.has(action)) {
    throw new ApiError(400, "adjustment_action_invalid", "action is invalid.");
  }
  if (!SCHEDULE_MODES.has(scheduleMode)) {
    throw new ApiError(400, "schedule_mode_invalid", "scheduleMode is invalid.");
  }

  const scheduleAmount = integer(body.scheduleAmount, "schedule_amount", 1, 3650, true);
  const expiresAt = exactExpiry(body.exactExpiresAtUtc);
  if (scheduleMode === "AddMonths" && scheduleAmount !== null && scheduleAmount > 120) {
    throw new ApiError(400, "schedule_amount_invalid", "AddMonths cannot exceed 120 months.");
  }
  if (scheduleMode === "Immediate" && (scheduleAmount !== null || expiresAt !== null)) {
    throw new ApiError(400, "schedule_mode_invalid", "Immediate mode must not include expiry parameters.");
  }
  if (scheduleMode === "ExactExpiry" && expiresAt === null) {
    throw new ApiError(400, "exact_expires_at_invalid", "ExactExpiry requires exactExpiresAtUtc.");
  }
  if ((scheduleMode === "AddDays" || scheduleMode === "AddMonths") && scheduleAmount === null) {
    throw new ApiError(400, "schedule_amount_invalid", `${scheduleMode} requires scheduleAmount.`);
  }
  if (action === "Revoke" && scheduleMode !== "Immediate") {
    throw new ApiError(400, "entitlement_revoke_mode_invalid", "Revoke requires Immediate mode.");
  }
  if (action === "Reduce" && scheduleMode !== "ExactExpiry") {
    throw new ApiError(400, "entitlement_reduce_mode_invalid", "Reduce requires ExactExpiry mode.");
  }
  if ((action === "Reduce" || action === "Revoke") && body.confirmed !== true) {
    throw new ApiError(
      400,
      "entitlement_adjustment_confirmation_required",
      "Reduce and Revoke require explicit confirmation.",
    );
  }

  const approvalRequestId = uuid(body.approvalRequestId, "approval_request_id", true);
  const approvalExpectedVersion = integer(
    body.approvalExpectedVersion,
    "approval_expected_version",
    1,
    Number.MAX_SAFE_INTEGER,
    true,
  );
  if ((approvalRequestId === null) !== (approvalExpectedVersion === null)) {
    throw new ApiError(
      400,
      "approval_reference_invalid",
      "approvalRequestId and approvalExpectedVersion must be provided together.",
    );
  }

  return {
    accountId: uuid(body.accountId, "account_id")!,
    targetType: targetType as EntitlementAdjustmentPayload["targetType"],
    targetId: uuid(body.targetId, "target_id")!,
    action: action as EntitlementAdjustmentPayload["action"],
    scheduleMode: scheduleMode as EntitlementAdjustmentPayload["scheduleMode"],
    scheduleAmount,
    exactExpiresAtUtc: expiresAt,
    reason: boundedReason(body.reason),
    confirmed: body.confirmed === true,
    approvalRequestId,
    approvalExpectedVersion,
  };
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`)
    .join(",")}}`;
}

export async function hashEntitlementAdjustmentPayload(
  payload: EntitlementAdjustmentPayload,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stable(payload)),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
