import { ApiError, requireUuid } from "./validation.ts";

export type BreakGlassCapability =
  | "health.read.elevated"
  | "women_health.read.elevated";
export type BreakGlassDecision = "approve" | "deny" | "revoke";

export type BreakGlassCreateRequest = {
  subjectPersonId: string;
  capability: BreakGlassCapability;
  ttlMinutes: number;
  reason: string;
};

export type BreakGlassActionRequest = {
  expectedVersion: number;
  reason: string;
};

const ACTION_PATH =
  /^\/api\/v1\/security\/break-glass\/requests\/([^/]+)\/actions\/(approve|deny|revoke)$/i;

function reason(value: unknown): string {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "break_glass_reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }
  return normalized;
}

function capability(value: unknown): BreakGlassCapability {
  if (
    value !== "health.read.elevated" &&
    value !== "women_health.read.elevated"
  ) {
    throw new ApiError(
      400,
      "break_glass_capability_invalid",
      "Break-glass capability is invalid.",
    );
  }
  return value;
}

function ttl(value: unknown, selected: BreakGlassCapability): number {
  if (!Number.isInteger(value)) {
    throw new ApiError(
      400,
      "break_glass_ttl_invalid",
      "TTL must be an integer number of minutes.",
    );
  }
  const minutes = Number(value);
  const maximum = selected === "women_health.read.elevated" ? 30 : 60;
  if (minutes < 5 || minutes > maximum) {
    throw new ApiError(
      400,
      "break_glass_ttl_invalid",
      `TTL must be between 5 and ${maximum} minutes for this capability.`,
    );
  }
  return minutes;
}

async function jsonObject(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be valid JSON.",
    );
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be an object.",
    );
  }
  return body as Record<string, unknown>;
}

export async function parseBreakGlassCreateRequest(
  request: Request,
): Promise<BreakGlassCreateRequest> {
  const body = await jsonObject(request);
  const allowed = new Set([
    "subjectPersonId",
    "capability",
    "ttlMinutes",
    "reason",
  ]);
  if (Object.keys(body).some((key) => !allowed.has(key))) {
    throw new ApiError(
      400,
      "break_glass_field_unsupported",
      "Request contains an unsupported field.",
    );
  }
  const selected = capability(body.capability);
  return {
    subjectPersonId: requireUuid(
      String(body.subjectPersonId ?? ""),
      "subjectPersonId",
    ),
    capability: selected,
    ttlMinutes: ttl(body.ttlMinutes, selected),
    reason: reason(body.reason),
  };
}

export function matchBreakGlassActionPath(
  path: string,
): { requestId: string; action: BreakGlassDecision } | null {
  const match = ACTION_PATH.exec(path);
  if (!match) return null;
  return {
    requestId: requireUuid(match[1], "requestId"),
    action: match[2].toLowerCase() as BreakGlassDecision,
  };
}

export async function parseBreakGlassActionRequest(
  request: Request,
): Promise<BreakGlassActionRequest> {
  const body = await jsonObject(request);
  const allowed = new Set(["expectedVersion", "reason"]);
  if (Object.keys(body).some((key) => !allowed.has(key))) {
    throw new ApiError(
      400,
      "break_glass_field_unsupported",
      "Request contains an unsupported field.",
    );
  }
  if (
    !Number.isInteger(body.expectedVersion) || Number(body.expectedVersion) < 1
  ) {
    throw new ApiError(
      400,
      "break_glass_version_invalid",
      "A positive expectedVersion is required.",
    );
  }
  return {
    expectedVersion: Number(body.expectedVersion),
    reason: reason(body.reason),
  };
}

async function hash(parts: Array<string | number>): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(["v1", ...parts].join("\n")),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function hashBreakGlassCreateRequest(
  request: BreakGlassCreateRequest,
): Promise<string> {
  return hash([
    request.subjectPersonId,
    request.capability,
    request.ttlMinutes,
    request.reason,
  ]);
}

export function hashBreakGlassActionRequest(
  requestId: string,
  action: BreakGlassDecision,
  request: BreakGlassActionRequest,
): Promise<string> {
  return hash([requestId, action, request.expectedVersion, request.reason]);
}
