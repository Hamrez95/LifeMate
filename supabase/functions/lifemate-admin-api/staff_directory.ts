import { ApiError, boundedAdminPageSize, requireUuid } from "./validation.ts";

export type StaffMembershipStatus = "Active" | "Disabled" | "Revoked";

export type StaffDirectoryCursor = {
  createdAtUtc: string;
  accountId: string;
};

export type StaffDirectoryQuery = {
  pageSize: number;
  status: StaffMembershipStatus | null;
  roleCode: string | null;
  q: string | null;
  cursor: StaffDirectoryCursor | null;
};

const STAFF_DETAIL_PATH = /^\/api\/v1\/staff\/([^/]+)$/i;
const ROLE_CODE = /^[a-z][a-z0-9_]{1,63}$/;
const STATUS = new Set<StaffMembershipStatus>([
  "Active",
  "Disabled",
  "Revoked",
]);

function decodeCursor(value: string): StaffDirectoryCursor {
  try {
    const decoded = JSON.parse(
      new TextDecoder().decode(
        Uint8Array.from(
          atob(value.replace(/-/g, "+").replace(/_/g, "/")),
          (char) => char.charCodeAt(0),
        ),
      ),
    ) as Record<string, unknown>;
    const createdAtUtc = typeof decoded.createdAtUtc === "string"
      ? decoded.createdAtUtc
      : "";
    const accountId = typeof decoded.accountId === "string"
      ? decoded.accountId
      : "";
    const date = new Date(createdAtUtc);
    if (Number.isNaN(date.getTime())) throw new Error("invalid date");
    return {
      createdAtUtc: date.toISOString(),
      accountId: requireUuid(accountId, "cursor.accountId"),
    };
  } catch {
    throw new ApiError(
      400,
      "staff_cursor_invalid",
      "Staff directory cursor is invalid.",
    );
  }
}

export function encodeStaffDirectoryCursor(
  cursor: StaffDirectoryCursor,
): string {
  const bytes = new TextEncoder().encode(JSON.stringify(cursor));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/g,
    "",
  );
}

export function matchStaffDetailPath(path: string): string | null {
  const match = STAFF_DETAIL_PATH.exec(path);
  return match ? requireUuid(match[1], "accountId") : null;
}

export function parseStaffDirectoryQuery(url: URL): StaffDirectoryQuery {
  const rawStatus = url.searchParams.get("status");
  if (rawStatus && !STATUS.has(rawStatus as StaffMembershipStatus)) {
    throw new ApiError(
      400,
      "staff_status_invalid",
      "Staff membership status filter is invalid.",
    );
  }

  const rawRole = url.searchParams.get("role")?.trim().toLowerCase() || null;
  if (rawRole && !ROLE_CODE.test(rawRole)) {
    throw new ApiError(
      400,
      "staff_role_invalid",
      "Staff role filter is invalid.",
    );
  }

  const rawQ = url.searchParams.get("q")?.trim() || null;
  if (rawQ && (rawQ.length < 2 || rawQ.length > 80)) {
    throw new ApiError(
      400,
      "staff_query_invalid",
      "Staff query must contain between 2 and 80 characters.",
    );
  }

  const rawCursor = url.searchParams.get("cursor")?.trim() || null;
  return {
    pageSize: boundedAdminPageSize(url.searchParams.get("pageSize"), 25, 5, 50),
    status: rawStatus as StaffMembershipStatus | null,
    roleCode: rawRole,
    q: rawQ,
    cursor: rawCursor ? decodeCursor(rawCursor) : null,
  };
}
