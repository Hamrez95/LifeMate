import { ApiError, requireUuid } from "./validation.ts";

export type ManualEntitlementOperation =
  | "Grant"
  | "Extend"
  | "Reduce"
  | "Revoke";
export type ManualEntitlementTarget = "Product" | "Offer";
export type ManualEntitlementSchedule =
  | "ExactExpiry"
  | "AddDays"
  | "AddMonths"
  | "Immediate";

export type ManualEntitlementPayload = {
  subjectAccountId: string;
  targetType: ManualEntitlementTarget;
  targetId: string;
  entitlementId: string | null;
  expectedEntitlementVersion: number | null;
  operation: ManualEntitlementOperation;
  scheduleMode: ManualEntitlementSchedule;
  scheduleAmount: number | null;
  exactExpiresAtUtc: string | null;
  referenceAtUtc: string;
  reason: string;
  confirmed: boolean;
  approvalRequestId: string | null;
  approvalExpectedVersion: number | null;
};

const targetTypes = new Set(["Product", "Offer"]);
const operations = new Set(["Grant", "Extend", "Reduce", "Revoke"]);
const schedules = new Set(["ExactExpiry", "AddDays", "AddMonths", "Immediate"]);

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be a JSON object.",
    );
  }
}
function optionalUuid(value: unknown, field: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return requireUuid(value, field);
}
function positiveInt(
  value: unknown,
  field: string,
  max: number,
): number | null {
  if (value == null) return null;
  if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > max) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return Number(value);
}
function boundedReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "reason_invalid", "A reason is required.");
  }
  const result = value.trim();
  if (result.length < 10 || result.length > 1000) {
    throw new ApiError(
      400,
      "reason_invalid",
      "Reason must be between 10 and 1000 characters.",
    );
  }
  return result;
}
function iso(value: unknown, field: string, required: boolean): string | null {
  if (value == null || value === "") {
    if (required) {
      throw new ApiError(400, `${field}_invalid`, `${field} is required.`);
    }
    return null;
  }
  if (typeof value !== "string") {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return parsed.toISOString();
}

export async function parseManualEntitlementPayload(
  request: Request,
  options: { requireReference?: boolean; requireConfirmation?: boolean } = {},
): Promise<ManualEntitlementPayload> {
  const body = await objectBody(request);
  const targetType = String(body.targetType ?? "");
  const operation = String(body.operation ?? "");
  const scheduleMode = String(body.scheduleMode ?? "");
  if (!targetTypes.has(targetType)) {
    throw new ApiError(400, "target_type_invalid", "targetType is invalid.");
  }
  if (!operations.has(operation)) {
    throw new ApiError(400, "operation_invalid", "operation is invalid.");
  }
  if (!schedules.has(scheduleMode)) {
    throw new ApiError(
      400,
      "schedule_mode_invalid",
      "scheduleMode is invalid.",
    );
  }
  const entitlementId = optionalUuid(body.entitlementId, "entitlement_id");
  const expectedEntitlementVersion = positiveInt(
    body.expectedEntitlementVersion,
    "expected_entitlement_version",
    Number.MAX_SAFE_INTEGER,
  );
  if (operation === "Grant" && (entitlementId || expectedEntitlementVersion)) {
    throw new ApiError(
      400,
      "grant_existing_invalid",
      "Grant must not include an existing entitlement.",
    );
  }
  if (
    operation !== "Grant" && (!entitlementId || !expectedEntitlementVersion)
  ) {
    throw new ApiError(
      400,
      "entitlement_version_required",
      "Existing adjustments require entitlementId and expectedEntitlementVersion.",
    );
  }
  const maxAmount = scheduleMode === "AddMonths" ? 120 : 3650;
  const scheduleAmount = positiveInt(
    body.scheduleAmount,
    "schedule_amount",
    maxAmount,
  );
  const exactExpiresAtUtc = iso(
    body.exactExpiresAtUtc,
    "exact_expires_at_utc",
    false,
  );
  if (
    (scheduleMode === "AddDays" || scheduleMode === "AddMonths") &&
    !scheduleAmount
  ) {
    throw new ApiError(
      400,
      "schedule_amount_required",
      "Selected schedule requires scheduleAmount.",
    );
  }
  if (scheduleMode === "ExactExpiry" && !exactExpiresAtUtc) {
    throw new ApiError(
      400,
      "exact_expiry_required",
      "ExactExpiry requires exactExpiresAtUtc.",
    );
  }
  if (scheduleMode === "Immediate" && operation !== "Revoke") {
    throw new ApiError(
      400,
      "immediate_mode_invalid",
      "Immediate mode is reserved for Revoke.",
    );
  }
  if (operation === "Reduce" && scheduleMode !== "ExactExpiry") {
    throw new ApiError(
      400,
      "reduce_schedule_invalid",
      "Reduce requires ExactExpiry.",
    );
  }
  const referenceAtUtc = iso(
    body.referenceAtUtc,
    "reference_at_utc",
    options.requireReference === true,
  ) ?? new Date().toISOString();
  const confirmed = body.confirmed === true;
  if (
    options.requireConfirmation &&
    (operation === "Reduce" || operation === "Revoke") && !confirmed
  ) {
    throw new ApiError(
      400,
      "confirmation_required",
      "Reduce and Revoke require explicit confirmation.",
    );
  }
  const approvalRequestId = optionalUuid(
    body.approvalRequestId,
    "approval_request_id",
  );
  const approvalExpectedVersion = positiveInt(
    body.approvalExpectedVersion,
    "approval_expected_version",
    Number.MAX_SAFE_INTEGER,
  );
  if ((approvalRequestId == null) !== (approvalExpectedVersion == null)) {
    throw new ApiError(
      400,
      "approval_pair_invalid",
      "Approval id and expected version must be supplied together.",
    );
  }
  return {
    subjectAccountId: requireUuid(
      String(body.subjectAccountId ?? ""),
      "subjectAccountId",
    ),
    targetType: targetType as ManualEntitlementTarget,
    targetId: requireUuid(String(body.targetId ?? ""), "targetId"),
    entitlementId,
    expectedEntitlementVersion,
    operation: operation as ManualEntitlementOperation,
    scheduleMode: scheduleMode as ManualEntitlementSchedule,
    scheduleAmount,
    exactExpiresAtUtc,
    referenceAtUtc,
    reason: boundedReason(body.reason),
    confirmed,
    approvalRequestId,
    approvalExpectedVersion,
  };
}
function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${
    Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
      a.localeCompare(b)
    ).map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(",")
  }}`;
}
export async function hashManualEntitlementPayload(
  payload: ManualEntitlementPayload,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stable(payload)),
  );
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}
export function matchManualEntitlementHistoryPath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/commerce\/accounts\/([^/]+)\/entitlement-adjustments$/i,
  );
  return match ? requireUuid(match[1], "accountId") : null;
}
