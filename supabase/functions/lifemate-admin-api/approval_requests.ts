import { ApiError } from "./validation.ts";

export type ApprovalDecision = "approve" | "reject";

export type CreateApprovalRequest = {
  requestType: string;
  targetType: string;
  targetId: string;
  before: Record<string, unknown>;
  delta: Record<string, unknown>;
  after: Record<string, unknown>;
  reason: string;
};

export type DecideApprovalRequest = {
  expectedVersion: number;
  decision: ApprovalDecision;
  reason: string;
};

const REQUEST_TYPE = /^[a-z][a-z0-9._-]{2,79}$/;
const TARGET_TYPE = /^[a-z][a-z0-9._-]{1,79}$/;
const TARGET_ID =
  /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|(?=[A-Za-z0-9._:-]{1,180}$)(?=.*[A-Za-z])[A-Za-z0-9][A-Za-z0-9._:-]{0,179})$/i;
const STATE_KEY = /^[a-zA-Z][a-zA-Z0-9_]{0,63}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_STATE_BYTES = 16 * 1024;
const MAX_STATE_DEPTH = 5;
const MAX_STATE_STRING = 240;
const FORBIDDEN_STATE_KEY =
  /(health|medical|medication|treatment|diagnosis|symptom|journal|note|message|content|body|phone|email|address|password|secret|token)/i;

function objectBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "approval_payload_invalid",
      "Approval payload must be an object.",
    );
  }
  return value as Record<string, unknown>;
}

function validateBusinessState(value: unknown, field: string, depth = 0): void {
  if (depth > MAX_STATE_DEPTH) {
    throw new ApiError(
      400,
      "approval_state_invalid",
      `${field} is too deeply nested.`,
    );
  }
  if (value === null || typeof value === "boolean") return;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new ApiError(
        400,
        "approval_state_invalid",
        `${field} contains a non-finite number.`,
      );
    }
    return;
  }
  if (typeof value === "string") {
    if (value.length > MAX_STATE_STRING) {
      throw new ApiError(
        400,
        "approval_state_invalid",
        `${field} contains an oversized string.`,
      );
    }
    return;
  }
  if (Array.isArray(value)) {
    if (value.length > 100) {
      throw new ApiError(
        400,
        "approval_state_invalid",
        `${field} contains too many array entries.`,
      );
    }
    value.forEach((entry, index) =>
      validateBusinessState(entry, `${field}[${index}]`, depth + 1)
    );
    return;
  }
  if (!value || typeof value !== "object") {
    throw new ApiError(
      400,
      "approval_state_invalid",
      `${field} contains an unsupported value.`,
    );
  }
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > 100) {
    throw new ApiError(
      400,
      "approval_state_invalid",
      `${field} contains too many fields.`,
    );
  }
  for (const [key, entry] of entries) {
    if (!STATE_KEY.test(key) || FORBIDDEN_STATE_KEY.test(key)) {
      throw new ApiError(
        400,
        "approval_state_sensitive",
        `${field} contains a forbidden or invalid field.`,
      );
    }
    validateBusinessState(entry, `${field}.${key}`, depth + 1);
  }
}

function boundedObject(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "approval_state_invalid",
      `${field} must be a JSON object.`,
    );
  }
  validateBusinessState(value, field);
  const encoded = JSON.stringify(value);
  if (new TextEncoder().encode(encoded).byteLength > MAX_STATE_BYTES) {
    throw new ApiError(
      413,
      "approval_state_too_large",
      `${field} is too large.`,
    );
  }
  return value as Record<string, unknown>;
}

function boundedReason(value: unknown): string {
  const reason = typeof value === "string" ? value.trim() : "";
  if (reason.length < 10 || reason.length > 1000) {
    throw new ApiError(
      400,
      "approval_reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }
  return reason;
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, canonical(entry)]),
    );
  }
  return value;
}

async function hash(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(canonical(value)));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((entry) =>
    entry.toString(16).padStart(2, "0")
  ).join("");
}

export async function parseCreateApprovalRequest(
  request: Request,
): Promise<CreateApprovalRequest> {
  const body = objectBody(await request.json().catch(() => null));
  const requestType = typeof body.requestType === "string"
    ? body.requestType.trim().toLowerCase()
    : "";
  const targetType = typeof body.targetType === "string"
    ? body.targetType.trim().toLowerCase()
    : "";
  const targetId = typeof body.targetId === "string"
    ? body.targetId.trim()
    : "";
  if (!REQUEST_TYPE.test(requestType)) {
    throw new ApiError(
      400,
      "approval_request_type_invalid",
      "requestType is invalid.",
    );
  }
  if (!TARGET_TYPE.test(targetType) || !TARGET_ID.test(targetId)) {
    throw new ApiError(
      400,
      "approval_target_invalid",
      "Approval target must use an opaque internal identifier.",
    );
  }
  return {
    requestType,
    targetType,
    targetId,
    before: boundedObject(body.before ?? {}, "before"),
    delta: boundedObject(body.delta ?? {}, "delta"),
    after: boundedObject(body.after ?? {}, "after"),
    reason: boundedReason(body.reason),
  };
}

export async function parseDecideApprovalRequest(
  request: Request,
  decision: ApprovalDecision,
): Promise<DecideApprovalRequest> {
  const body = objectBody(await request.json().catch(() => null));
  if (
    !Number.isInteger(body.expectedVersion) || Number(body.expectedVersion) < 1
  ) {
    throw new ApiError(
      400,
      "approval_version_invalid",
      "expectedVersion must be a positive integer.",
    );
  }
  return {
    expectedVersion: Number(body.expectedVersion),
    decision,
    reason: boundedReason(body.reason),
  };
}

export function matchApprovalRequestPath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/operations\/approval-requests\/([^/]+)$/,
  );
  if (!match) return null;
  const id = decodeURIComponent(match[1]);
  if (!UUID.test(id)) {
    throw new ApiError(
      400,
      "approval_request_id_invalid",
      "Approval request id is invalid.",
    );
  }
  return id;
}

export function matchApprovalDecisionPath(
  path: string,
): { id: string; decision: ApprovalDecision } | null {
  const match = path.match(
    /^\/api\/v1\/operations\/approval-requests\/([^/]+)\/actions\/(approve|reject)$/,
  );
  if (!match) return null;
  const id = decodeURIComponent(match[1]);
  if (!UUID.test(id)) {
    throw new ApiError(
      400,
      "approval_request_id_invalid",
      "Approval request id is invalid.",
    );
  }
  return { id, decision: match[2] as ApprovalDecision };
}

export async function hashCreateApprovalRequest(
  payload: CreateApprovalRequest,
): Promise<string> {
  return await hash(["approval-request-v1", payload]);
}

export async function hashDecideApprovalRequest(
  id: string,
  payload: DecideApprovalRequest,
): Promise<string> {
  return await hash(["approval-decision-v1", id, payload]);
}
