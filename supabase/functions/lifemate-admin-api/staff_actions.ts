import { ApiError, requireUuid } from "./validation.ts";

export type StaffMembershipAction = "activate" | "disable" | "reenable";
export type StaffRoleAction = "assign" | "revoke";

export type StaffActionRoute =
  | { kind: "membership"; accountId: string; action: StaffMembershipAction }
  | { kind: "role"; accountId: string; action: StaffRoleAction };

export type StaffActionRequest = {
  reason: string;
  roleCode: string | null;
};

const MEMBERSHIP_PATH =
  /^\/api\/v1\/staff\/([^/]+)\/actions\/(activate|disable|reenable)$/i;
const ROLE_PATH = /^\/api\/v1\/staff\/([^/]+)\/roles\/(assign|revoke)$/i;
const ROLE_CODE = /^[a-z][a-z0-9_]{1,63}$/;

export function matchStaffActionPath(path: string): StaffActionRoute | null {
  const membership = MEMBERSHIP_PATH.exec(path);
  if (membership) {
    return {
      kind: "membership",
      accountId: requireUuid(membership[1], "accountId"),
      action: membership[2].toLowerCase() as StaffMembershipAction,
    };
  }

  const role = ROLE_PATH.exec(path);
  if (role) {
    return {
      kind: "role",
      accountId: requireUuid(role[1], "accountId"),
      action: role[2].toLowerCase() as StaffRoleAction,
    };
  }

  return null;
}

export async function parseStaffActionRequest(
  request: Request,
  route: StaffActionRoute,
): Promise<StaffActionRequest> {
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

  const record = body as Record<string, unknown>;
  const reason = typeof record.reason === "string" ? record.reason.trim() : "";
  if (reason.length < 10 || reason.length > 1000) {
    throw new ApiError(
      400,
      "staff_action_reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }

  if (route.kind === "membership") {
    if (record.roleCode != null) {
      throw new ApiError(
        400,
        "staff_role_not_allowed",
        "Membership actions do not accept a roleCode.",
      );
    }
    return { reason, roleCode: null };
  }

  const roleCode = typeof record.roleCode === "string"
    ? record.roleCode.trim().toLowerCase()
    : "";
  if (!ROLE_CODE.test(roleCode)) {
    throw new ApiError(
      400,
      "staff_role_invalid",
      "A valid roleCode is required.",
    );
  }
  if (roleCode === "founder" || roleCode === "super_admin") {
    throw new ApiError(
      403,
      "privileged_role_immutable",
      "Privileged roles cannot be changed through the ordinary staff workflow.",
    );
  }

  return { reason, roleCode };
}

export async function hashStaffActionRequest(
  route: StaffActionRoute,
  request: StaffActionRequest,
): Promise<string> {
  const canonical = [
    "v1",
    route.kind,
    route.accountId,
    route.action,
    request.roleCode ?? "-",
    request.reason,
  ].join("\n");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
