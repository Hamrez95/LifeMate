import { ApiError } from "./validation.ts";

export type CustomRoleMutationAction = "create" | "update" | "retire";
export type CustomRolePermissionAction = "assign" | "revoke";

export type CustomRoleMutationRequest = {
  code: string;
  displayName: string | null;
  rank: number | null;
  expectedVersion: number | null;
  reason: string;
};

export type CustomRolePermissionRequest = {
  permissionCode: string;
  expectedVersion: number;
  reason: string;
};

const ROLE_CODE = /^[a-z][a-z0-9_]{1,63}$/;
const PERMISSION_CODE = /^[a-z][a-z0-9_.]{1,119}$/;

function objectBody(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "custom_role_payload_invalid",
      "Custom role payload must be an object.",
    );
  }
  return value as Record<string, unknown>;
}

function reason(value: unknown): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length < 10 || text.length > 1000) {
    throw new ApiError(
      400,
      "custom_role_reason_invalid",
      "Reason must contain between 10 and 1000 characters.",
    );
  }
  return text;
}

function roleCode(value: unknown): string {
  const code = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (!ROLE_CODE.test(code) || code === "founder" || code === "super_admin") {
    throw new ApiError(
      400,
      "custom_role_code_invalid",
      "Custom role code is invalid or reserved.",
    );
  }
  return code;
}

function expectedVersion(value: unknown): number {
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new ApiError(
      400,
      "custom_role_version_invalid",
      "expectedVersion must be a positive integer.",
    );
  }
  return Number(value);
}

export async function parseCustomRoleMutationRequest(
  request: Request,
  action: CustomRoleMutationAction,
  pathRoleCode?: string,
): Promise<CustomRoleMutationRequest> {
  const body = objectBody(await request.json().catch(() => null));
  const code = roleCode(action === "create" ? body.code : pathRoleCode);
  const parsedReason = reason(body.reason);
  if (action === "retire") {
    return {
      code,
      displayName: null,
      rank: null,
      expectedVersion: expectedVersion(body.expectedVersion),
      reason: parsedReason,
    };
  }

  const displayName = typeof body.displayName === "string"
    ? body.displayName.trim()
    : "";
  if (displayName.length < 2 || displayName.length > 120) {
    throw new ApiError(
      400,
      "custom_role_name_invalid",
      "Display name must contain between 2 and 120 characters.",
    );
  }
  if (
    !Number.isInteger(body.rank) || Number(body.rank) < 1 ||
    Number(body.rank) > 1000
  ) {
    throw new ApiError(
      400,
      "custom_role_rank_invalid",
      "rank must be an integer between 1 and 1000.",
    );
  }
  return {
    code,
    displayName,
    rank: Number(body.rank),
    expectedVersion: action === "create"
      ? null
      : expectedVersion(body.expectedVersion),
    reason: parsedReason,
  };
}

export async function parseCustomRolePermissionRequest(
  request: Request,
): Promise<CustomRolePermissionRequest> {
  const body = objectBody(await request.json().catch(() => null));
  const permissionCode = typeof body.permissionCode === "string"
    ? body.permissionCode.trim().toLowerCase()
    : "";
  if (!PERMISSION_CODE.test(permissionCode)) {
    throw new ApiError(
      400,
      "custom_role_permission_invalid",
      "permissionCode is invalid.",
    );
  }
  return {
    permissionCode,
    expectedVersion: expectedVersion(body.expectedVersion),
    reason: reason(body.reason),
  };
}

async function hashCanonical(values: unknown[]): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(values)),
  );
  return Array.from(new Uint8Array(digest)).map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

export async function hashCustomRoleMutationRequest(
  action: CustomRoleMutationAction,
  payload: CustomRoleMutationRequest,
): Promise<string> {
  return await hashCanonical([
    "v1",
    action,
    payload.code,
    payload.displayName,
    payload.rank,
    payload.expectedVersion,
    payload.reason,
  ]);
}

export async function hashCustomRolePermissionRequest(
  roleCodeValue: string,
  action: CustomRolePermissionAction,
  payload: CustomRolePermissionRequest,
): Promise<string> {
  return await hashCanonical([
    "v1",
    roleCodeValue,
    action,
    payload.permissionCode,
    payload.expectedVersion,
    payload.reason,
  ]);
}

export function matchCustomRolePath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/security\/custom-roles\/([a-z][a-z0-9_]{1,63})$/,
  );
  return match ? match[1] : null;
}

export function matchCustomRoleRetirePath(path: string): string | null {
  const match = path.match(
    /^\/api\/v1\/security\/custom-roles\/([a-z][a-z0-9_]{1,63})\/actions\/retire$/,
  );
  return match ? match[1] : null;
}

export function matchCustomRolePermissionPath(
  path: string,
): { roleCode: string; action: CustomRolePermissionAction } | null {
  const match = path.match(
    /^\/api\/v1\/security\/custom-roles\/([a-z][a-z0-9_]{1,63})\/permissions\/(assign|revoke)$/,
  );
  return match
    ? { roleCode: match[1], action: match[2] as CustomRolePermissionAction }
    : null;
}
