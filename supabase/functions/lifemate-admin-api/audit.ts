import { ApiError, boundedInteger } from "./validation.ts";

export type AuditCursor = {
  occurredAtUtc: string;
  id: string;
};

export type AuditQuery = {
  limit: number;
  fromUtc: string | null;
  toUtc: string | null;
  cursor: AuditCursor | null;
};

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function optionalDate(value: string | null, field: "from" | "to"): string | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  const date = new Date(normalized);
  if (Number.isNaN(date.getTime())) {
    throw new ApiError(
      400,
      `audit_${field}_invalid`,
      `Audit ${field} filter is invalid.`,
    );
  }
  return date.toISOString();
}

function base64UrlEncode(value: string): string {
  return btoa(value).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function base64UrlDecode(value: string): string {
  if (!/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw new ApiError(400, "audit_cursor_invalid", "Audit cursor is invalid.");
  }
  const standard = value.replaceAll("-", "+").replaceAll("_", "/");
  const padding = standard.length % 4 === 0 ? "" : "=".repeat(4 - (standard.length % 4));
  try {
    return atob(`${standard}${padding}`);
  } catch {
    throw new ApiError(400, "audit_cursor_invalid", "Audit cursor is invalid.");
  }
}

export function encodeAuditCursor(cursor: AuditCursor): string {
  return base64UrlEncode(JSON.stringify([cursor.occurredAtUtc, cursor.id]));
}

export function decodeAuditCursor(value: string | null): AuditCursor | null {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(base64UrlDecode(normalized));
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "audit_cursor_invalid", "Audit cursor is invalid.");
  }

  if (
    !Array.isArray(parsed) ||
    parsed.length !== 2 ||
    typeof parsed[0] !== "string" ||
    typeof parsed[1] !== "string" ||
    Number.isNaN(Date.parse(parsed[0])) ||
    !UUID.test(parsed[1])
  ) {
    throw new ApiError(400, "audit_cursor_invalid", "Audit cursor is invalid.");
  }

  return {
    occurredAtUtc: new Date(parsed[0]).toISOString(),
    id: parsed[1].toLowerCase(),
  };
}

export function parseAuditQuery(url: URL): AuditQuery {
  const limit = boundedInteger(url.searchParams.get("limit"), 50, 1, 100);
  const fromUtc = optionalDate(url.searchParams.get("from"), "from");
  const toUtc = optionalDate(url.searchParams.get("to"), "to");
  if (fromUtc && toUtc && fromUtc > toUtc) {
    throw new ApiError(
      400,
      "audit_range_invalid",
      "Audit date range is invalid.",
    );
  }

  return {
    limit,
    fromUtc,
    toUtc,
    cursor: decodeAuditCursor(url.searchParams.get("cursor")),
  };
}
