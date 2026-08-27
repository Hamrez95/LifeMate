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
  approvalRequestId: string | null;
  approvalExpectedVersion: number | null;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const targetTypes = new Set(["Product", "Offer"]);
const actions = new Set(["Grant", "Extend", "Reduce", "Revoke"]);
const scheduleModes = new Set(["ExactExpiry", "AddDays", "AddMonths", "Immediate"]);

async function bodyObject(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(400, "json_invalid", "Request body must be valid JSON.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(400, "body_invalid", "Request body must be a JSON object.");
  }
  return body as Record<string, unknown>;
}

function uuid(value: unknown, field: string, nullable = false): string | null {
  if (nullable && (value === null || value === undefined || value === "")) return null;
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return value.toLowerCase();
}

function integer(value: unknown, field: string, min: number, max: number, nullable = false): number | null {
  if (nullable && (value === null || value === undefined)) return null;
  if (!Number.isInteger(value) || Number(value) < min || Number(value) > max) {
    throw new ApiError(400, `${field}_invalid`, `${field} is outside the allowed range.`);
  }
  return Number(value);
}

function reason(value: unknown): string {
  if (typeof value !== "string") throw new ApiError(400, "reason_invalid", "A reason is required.");
  const trimmed = value.trim();
  if (trimmed.length < 10 || trimmed.length > 1000) throw new ApiError(400, "reason_invalid", "Reason must be between 10 and 1000 characters.");
  return trimmed;
}

export async function parseEntitlementAdjustmentPayload(request: Request): Promise<EntitlementAdjustmentPayload> {
  const body = await bodyObject(request);
  const targetType = String(body.targetType ?? "");
  const action = String(body.action ?? "");
  const scheduleMode = String(body.scheduleMode ?? "");
  if (!targetTypes.has(targetType)) throw new ApiError(400, "target_type_invalid", "targetType is invalid.");
  if (!actions.has(action)) throw new ApiError(400, "adjustment_action_invalid", "action is invalid.");
  if (!scheduleModes.has(scheduleMode)) throw new ApiError(400, "schedule_mode_invalid", "scheduleMode is invalid.");

  const scheduleAmount = integer(body.scheduleAmount, "schedule_amount", 1, 3650, true);
  let exactExpiresAtUtc: string | null = null;
  if (body.exactExpiresAtUtc !== null && body.exactExpiresAtUtc !== undefined && body.exactExpiresAtUtc !== "") {
    if (typeof body.exactExpiresAtUtc !== "string" || Number.isNaN(Date.parse(body.exactExpiresAtUtc))) {
      throw new ApiError(400, "exact_expires_at_invalid", "exactExpiresAtUtc is invalid.");
    }
    exactExpiresAtUtc = new Date(body.exactExpiresAtUtc).toISOString();
  }
  if (scheduleMode === "AddMonths" && scheduleAmount !== null && scheduleAmount > 120) {
    throw new ApiError(400, "schedule_amount_invalid", "AddMonths cannot exceed 120 months.");
  }

  return {
    accountId: uuid(body.accountId, "account_id")!,
    targetType: targetType as EntitlementAdjustmentPayload["targetType"],
    targetId: uuid(body.targetId, "target_id")!,
    action: action as EntitlementAdjustmentPayload["action"],
    scheduleMode: scheduleMode as EntitlementAdjustmentPayload["scheduleMode"],
    scheduleAmount,
    exactExpiresAtUtc,
    reason: reason(body.reason),
    approvalRequestId: uuid(body.approvalRequestId, "approval_request_id", true),
    approvalExpectedVersion: integer(body.approvalExpectedVersion, "approval_expected_version", 1, Number.MAX_SAFE_INTEGER, true),
  };
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${Object.entries(value as Record<string, unknown>).sort(([a],[b]) => a.localeCompare(b)).map(([k,v]) => `${JSON.stringify(k)}:${stable(v)}`).join(",")}}`;
}

export async function hashEntitlementAdjustmentPayload(payload: EntitlementAdjustmentPayload): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(stable(payload)));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}
