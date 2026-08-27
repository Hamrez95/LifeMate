import { ApiError, requireUuid } from "./validation.ts";

export type EntitlementAdjustmentOperation =
  | "Grant"
  | "Extend"
  | "Reduce"
  | "Revoke";

export type ExecuteEntitlementAdjustmentPayload = {
  subjectAccountId: string;
  entitlementId: string | null;
  expectedEntitlementVersion: number | null;
  featureId: string | null;
  offerId: string | null;
  operation: EntitlementAdjustmentOperation;
  exactExpiresAtUtc: string | null;
  addDays: number | null;
  addMonths: number | null;
  reason: string;
  confirmed: boolean;
  approvalRequestId: string | null;
  approvalExpectedVersion: number | null;
};

const ACCOUNT_HISTORY_PATH =
  /^\/api\/v1\/commerce\/accounts\/([^/]+)\/entitlement-adjustments$/i;

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

function optionalUuid(value: unknown, field: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, "entitlement_adjust_uuid_invalid", `${field} is invalid.`);
  }
  return requireUuid(value, field);
}

function optionalPositiveInteger(
  value: unknown,
  field: string,
  maximum: number,
): number | null {
  if (value == null) return null;
  if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > maximum) {
    throw new ApiError(
      400,
      "entitlement_adjust_integer_invalid",
      `${field} is invalid.`,
    );
  }
  return Number(value);
}

function reason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "entitlement_adjust_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "entitlement_adjust_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  return normalized;
}

function operation(value: unknown): EntitlementAdjustmentOperation {
  if (
    value === "Grant" || value === "Extend" || value === "Reduce" ||
    value === "Revoke"
  ) return value;
  throw new ApiError(
    400,
    "entitlement_adjust_operation_invalid",
    "Adjustment operation is invalid.",
  );
}

function exactExpiry(value: unknown): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "entitlement_adjust_expiry_invalid",
      "exactExpiresAtUtc is invalid.",
    );
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString() !== value) {
    throw new ApiError(
      400,
      "entitlement_adjust_expiry_invalid",
      "exactExpiresAtUtc must be canonical ISO-8601 UTC.",
    );
  }
  return value;
}

export function matchEntitlementAdjustmentHistoryPath(
  path: string,
): string | null {
  const match = ACCOUNT_HISTORY_PATH.exec(path);
  return match ? requireUuid(match[1], "accountId") : null;
}

export async function parseExecuteEntitlementAdjustmentPayload(
  request: Request,
): Promise<ExecuteEntitlementAdjustmentPayload> {
  const body = await requestObject(request);
  const op = operation(body.operation);
  const entitlementId = optionalUuid(body.entitlementId, "entitlementId");
  const featureId = optionalUuid(body.featureId, "featureId");
  const offerId = optionalUuid(body.offerId, "offerId");
  const expectedEntitlementVersion = optionalPositiveInteger(
    body.expectedEntitlementVersion,
    "expectedEntitlementVersion",
    2_147_483_647,
  );
  const addDays = optionalPositiveInteger(body.addDays, "addDays", 3650);
  const addMonths = optionalPositiveInteger(body.addMonths, "addMonths", 120);
  const exactExpiresAtUtc = exactExpiry(body.exactExpiresAtUtc);

  if ([addDays, addMonths, exactExpiresAtUtc].filter((v) => v != null).length > 1) {
    throw new ApiError(
      400,
      "entitlement_adjust_expiry_invalid",
      "Use exactly one expiry adjustment mode.",
    );
  }
  if (op === "Grant" && entitlementId) {
    throw new ApiError(
      400,
      "entitlement_grant_target_invalid",
      "Grant must not include entitlementId.",
    );
  }
  if (op === "Grant" && !featureId && !offerId) {
    throw new ApiError(
      400,
      "entitlement_grant_feature_required",
      "Grant requires featureId or offerId.",
    );
  }
  if (op !== "Grant" && (!entitlementId || !expectedEntitlementVersion)) {
    throw new ApiError(
      400,
      "entitlement_adjust_version_required",
      "Existing entitlement adjustments require entitlementId and expectedEntitlementVersion.",
    );
  }
  if ((op === "Extend" || op === "Reduce") && addDays == null && addMonths == null && exactExpiresAtUtc == null) {
    throw new ApiError(
      400,
      "entitlement_adjust_expiry_required",
      "Extend or Reduce requires an expiry change.",
    );
  }
  if ((op === "Reduce" || op === "Revoke") && body.confirmed !== true) {
    throw new ApiError(
      400,
      "entitlement_adjust_confirmation_required",
      "Reduce and Revoke require explicit confirmation.",
    );
  }

  const approvalRequestId = optionalUuid(body.approvalRequestId, "approvalRequestId");
  const approvalExpectedVersion = optionalPositiveInteger(
    body.approvalExpectedVersion,
    "approvalExpectedVersion",
    2_147_483_647,
  );
  if ((approvalRequestId == null) !== (approvalExpectedVersion == null)) {
    throw new ApiError(
      400,
      "entitlement_adjust_approval_invalid",
      "approvalRequestId and approvalExpectedVersion must be supplied together.",
    );
  }

  return {
    subjectAccountId: requireUuid(String(body.subjectAccountId ?? ""), "subjectAccountId"),
    entitlementId,
    expectedEntitlementVersion,
    featureId,
    offerId,
    operation: op,
    exactExpiresAtUtc,
    addDays,
    addMonths,
    reason: reason(body.reason),
    confirmed: body.confirmed === true,
    approvalRequestId,
    approvalExpectedVersion,
  };
}

export async function hashEntitlementAdjustmentRequest(
  payload: ExecuteEntitlementAdjustmentPayload,
): Promise<string> {
  const canonical = [
    "v1",
    "commerce.entitlement.adjust.execute",
    payload.subjectAccountId,
    payload.entitlementId ?? "",
    payload.expectedEntitlementVersion ?? "",
    payload.featureId ?? "",
    payload.offerId ?? "",
    payload.operation,
    payload.exactExpiresAtUtc ?? "",
    payload.addDays ?? "",
    payload.addMonths ?? "",
    payload.reason,
    payload.confirmed ? "1" : "0",
    payload.approvalRequestId ?? "",
    payload.approvalExpectedVersion ?? "",
  ].join("\n");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
