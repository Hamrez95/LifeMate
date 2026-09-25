import { ApiError } from "./validation.ts";

export type AccessGrantAction = "extend" | "replace-scopes" | "revoke";

export type AccessGrantActionRoute = {
  grantId: string;
  action: AccessGrantAction;
};

export type AccessGrantActionRequest = {
  expectedVersion: number;
  expiresAtUtc: string | null;
  scopes: string[] | null;
  reason: string;
  confirmation: "confirm-access-grant-change";
};

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SCOPE = /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/;

export function matchAccessGrantActionPath(
  path: string,
): AccessGrantActionRoute | null {
  const match =
    /^\/api\/v1\/relationships\/access-grants\/([^/]+)\/actions\/(extend|replace-scopes|revoke)$/
      .exec(
        path,
      );
  if (!match) return null;
  if (!UUID.test(match[1])) {
    throw new ApiError(
      400,
      "access_grant_id_invalid",
      "Access Grant id is invalid.",
    );
  }
  return {
    grantId: match[1].toLowerCase(),
    action: match[2] as AccessGrantAction,
  };
}

function exactObject(
  value: unknown,
  allowed: ReadonlySet<string>,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "access_grant_request_invalid",
      "Request body must be a JSON object.",
    );
  }
  const object = value as Record<string, unknown>;
  if (Object.keys(object).some((key) => !allowed.has(key))) {
    throw new ApiError(
      400,
      "access_grant_field_unsupported",
      "Request contains an unsupported field.",
    );
  }
  return object;
}

function expectedVersion(value: unknown): number {
  if (
    !Number.isInteger(value) || Number(value) < 1 ||
    Number(value) > 2_147_483_647
  ) {
    throw new ApiError(
      400,
      "access_grant_version_invalid",
      "A positive expectedVersion is required.",
    );
  }
  return Number(value);
}

function reason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "access_grant_reason_invalid",
      "A reason is required.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "access_grant_reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }
  return normalized;
}

function confirmation(value: unknown): "confirm-access-grant-change" {
  if (value !== "confirm-access-grant-change") {
    throw new ApiError(
      400,
      "access_grant_confirmation_required",
      "Explicit Access Grant change confirmation is required.",
    );
  }
  return value;
}

function expiresAtUtc(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "access_grant_expiry_invalid",
      "expiresAtUtc must be an ISO timestamp.",
    );
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString() !== value) {
    throw new ApiError(
      400,
      "access_grant_expiry_invalid",
      "expiresAtUtc must be a canonical UTC ISO timestamp.",
    );
  }
  return value;
}

function scopes(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) {
    throw new ApiError(
      400,
      "access_grant_scopes_invalid",
      "Scopes must contain between 1 and 100 entries.",
    );
  }
  const normalized = value.map((item) => {
    if (typeof item !== "string") {
      throw new ApiError(
        400,
        "access_grant_scope_invalid",
        "Access Grant scope is invalid.",
      );
    }
    const scope = item.trim();
    if (!SCOPE.test(scope)) {
      throw new ApiError(
        400,
        "access_grant_scope_invalid",
        "Access Grant scope is invalid.",
      );
    }
    return scope;
  });
  if (new Set(normalized).size !== normalized.length) {
    throw new ApiError(
      400,
      "access_grant_scope_duplicate",
      "Access Grant scopes must be unique.",
    );
  }
  return [...normalized].sort();
}

export async function parseAccessGrantActionRequest(
  request: Request,
  action: AccessGrantAction,
): Promise<AccessGrantActionRequest> {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    throw new ApiError(
      400,
      "access_grant_request_invalid",
      "Request body must be valid JSON.",
    );
  }

  const allowed = action === "extend"
    ? new Set(["expectedVersion", "expiresAtUtc", "reason", "confirmation"])
    : action === "replace-scopes"
    ? new Set(["expectedVersion", "scopes", "reason", "confirmation"])
    : new Set(["expectedVersion", "reason", "confirmation"]);
  const body = exactObject(raw, allowed);

  return {
    expectedVersion: expectedVersion(body.expectedVersion),
    expiresAtUtc: action === "extend" ? expiresAtUtc(body.expiresAtUtc) : null,
    scopes: action === "replace-scopes" ? scopes(body.scopes) : null,
    reason: reason(body.reason),
    confirmation: confirmation(body.confirmation),
  };
}

export async function hashAccessGrantActionRequest(
  grantId: string,
  action: AccessGrantAction,
  payload: AccessGrantActionRequest,
): Promise<string> {
  const canonical = JSON.stringify({
    version: 1,
    operation: "relationships.access_grant.mutate",
    grantId,
    action,
    expectedVersion: payload.expectedVersion,
    expiresAtUtc: payload.expiresAtUtc,
    scopes: payload.scopes,
    reason: payload.reason,
    confirmation: payload.confirmation,
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
