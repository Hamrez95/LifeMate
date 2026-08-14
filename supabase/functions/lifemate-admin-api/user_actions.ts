import { ApiError, requireUuid } from "./validation.ts";

export type UserAccountAction = "suspend" | "restore";

export type UserAccountActionRoute = {
  accountId: string;
  action: UserAccountAction;
};

export type UserAccountActionRequest = {
  reason: string;
};

export type UserAccountActionResult = {
  httpStatus: number;
  code: string;
  message?: string;
  accountId?: string;
  previousStatus?: string;
  status?: string;
  action?: UserAccountAction;
  replayed: boolean;
};

const ACTION_PATH = /^\/api\/v1\/users\/([^/]+)\/actions\/(suspend|restore)$/i;

export function matchUserAccountActionPath(
  path: string,
): UserAccountActionRoute | null {
  const match = ACTION_PATH.exec(path);
  if (!match) return null;
  return {
    accountId: requireUuid(match[1], "accountId"),
    action: match[2].toLowerCase() as UserAccountAction,
  };
}

export async function parseUserAccountActionRequest(
  request: Request,
): Promise<UserAccountActionRequest> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be valid JSON.");
  }

  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(400, "invalid_request", "Request body must be an object.");
  }

  const reason = (body as Record<string, unknown>).reason;
  if (typeof reason !== "string") {
    throw new ApiError(400, "action_reason_required", "A reason is required.");
  }

  const normalized = reason.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "action_reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }

  return { reason: normalized };
}

export async function hashUserAccountActionRequest(
  accountId: string,
  action: UserAccountAction,
  reason: string,
): Promise<string> {
  const canonical = `v1\n${accountId}\n${action}\n${reason}`;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function assertUserAccountActionResult(
  value: unknown,
): UserAccountActionResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "user_action_unavailable",
      "User action result was unavailable.",
    );
  }

  const row = value as Record<string, unknown>;
  if (
    !Number.isInteger(row.httpStatus) ||
    typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "user_action_unavailable",
      "User action result was invalid.",
    );
  }

  return row as unknown as UserAccountActionResult;
}
