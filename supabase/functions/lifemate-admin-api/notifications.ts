import { ApiError, boundedInteger } from "./validation.ts";

export const notificationSources = [
  "support",
  "security",
  "operations",
  "finance",
  "product",
] as const;
export type NotificationSource = (typeof notificationSources)[number];

export const notificationSeverities = ["info", "warning", "critical"] as const;
export type NotificationSeverity = (typeof notificationSeverities)[number];

export const notificationPermission: Record<NotificationSource, string> = {
  support: "support.read",
  security: "security.audit.read",
  operations: "operations.read",
  finance: "finance.read",
  product: "analytics.read",
};

export type NotificationQuery = {
  page: number;
  pageSize: number;
  sources: NotificationSource[];
  unreadOnly: boolean;
};

export type NotificationCountQuery = {
  sources: NotificationSource[];
};

export type NotificationReadStateRequest = {
  alertKey: string;
  source: NotificationSource;
  read: boolean;
};

export type NotificationReadStateResult = {
  httpStatus: number;
  code: string;
  message?: string;
  alertKey?: string;
  source?: NotificationSource;
  read?: boolean;
  readAtUtc?: string | null;
  replayed: boolean;
};

const ALERT_KEY_PATTERN = /^[a-z][a-z0-9._:-]{2,179}$/;
const SUPPORT_DEEP_LINK = /^\/support\/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ROOT_DEEP_LINKS: Record<Exclude<NotificationSource, "support">, RegExp> = {
  security: /^\/security(?:[/?#].*)?$/,
  operations: /^\/operations(?:[/?#].*)?$/,
  finance: /^\/finance(?:[/?#].*)?$/,
  product: /^\/analytics(?:[/?#].*)?$/,
};

function parseSources(raw: string | null): NotificationSource[] {
  if (raw == null || raw.trim() === "") return [...notificationSources];
  const values = raw.split(",").map((item) => item.trim()).filter(Boolean);
  if (values.length === 0 || values.length > notificationSources.length) {
    throw new ApiError(
      400,
      "notification_sources_invalid",
      "Notification sources are invalid.",
    );
  }
  const unique = [...new Set(values)];
  if (
    unique.length !== values.length ||
    unique.some((value) => !notificationSources.includes(value as NotificationSource))
  ) {
    throw new ApiError(
      400,
      "notification_sources_invalid",
      "Notification sources are invalid.",
    );
  }
  return unique as NotificationSource[];
}

function assertAllowedParams(url: URL, allowed: ReadonlySet<string>) {
  for (const key of url.searchParams.keys()) {
    if (!allowed.has(key)) {
      throw new ApiError(
        400,
        "invalid_request",
        "Unknown notification query parameter.",
      );
    }
  }
}

export function parseNotificationQuery(url: URL): NotificationQuery {
  assertAllowedParams(
    url,
    new Set(["page", "pageSize", "sources", "unreadOnly"]),
  );
  const unreadRaw = url.searchParams.get("unreadOnly");
  if (unreadRaw != null && unreadRaw !== "true" && unreadRaw !== "false") {
    throw new ApiError(
      400,
      "notification_unread_filter_invalid",
      "Unread filter is invalid.",
    );
  }
  return {
    page: boundedInteger(url.searchParams.get("page"), 1, 1, 10),
    pageSize: boundedInteger(url.searchParams.get("pageSize"), 20, 1, 25),
    sources: parseSources(url.searchParams.get("sources")),
    unreadOnly: unreadRaw === "true",
  };
}

export function parseNotificationCountQuery(url: URL): NotificationCountQuery {
  assertAllowedParams(url, new Set(["sources"]));
  return { sources: parseSources(url.searchParams.get("sources")) };
}

export function authorizedNotificationSources(
  requested: readonly NotificationSource[],
  permissions: readonly string[],
): NotificationSource[] {
  const allowed = new Set(permissions);
  return requested.filter((source) => allowed.has(notificationPermission[source]));
}

export function assertSafeNotificationDeepLink(
  source: NotificationSource,
  value: string | null,
): string | null {
  if (value == null) return null;
  const valid = source === "support"
    ? SUPPORT_DEEP_LINK.test(value)
    : ROOT_DEEP_LINKS[source].test(value);
  if (!valid || value.includes("//") || value.includes("\\")) {
    throw new ApiError(
      503,
      "notification_deep_link_invalid",
      "Notification deep link was invalid.",
    );
  }
  return value;
}

export async function parseNotificationReadStateRequest(
  request: Request,
): Promise<NotificationReadStateRequest> {
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
    throw new ApiError(400, "invalid_request", "Request body must be an object.");
  }

  const row = body as Record<string, unknown>;
  const keys = Object.keys(row).sort();
  if (JSON.stringify(keys) !== JSON.stringify(["alertKey", "read", "source"])) {
    throw new ApiError(
      400,
      "notification_state_invalid",
      "Notification read-state request is invalid.",
    );
  }
  if (
    typeof row.alertKey !== "string" ||
    !ALERT_KEY_PATTERN.test(row.alertKey) ||
    typeof row.source !== "string" ||
    !notificationSources.includes(row.source as NotificationSource) ||
    typeof row.read !== "boolean"
  ) {
    throw new ApiError(
      400,
      "notification_state_invalid",
      "Notification read-state request is invalid.",
    );
  }
  const source = row.source as NotificationSource;
  if (!row.alertKey.startsWith(`${source}:`)) {
    throw new ApiError(
      400,
      "notification_state_invalid",
      "Notification source does not match its key.",
    );
  }
  return { alertKey: row.alertKey, source, read: row.read };
}

export async function hashNotificationReadStateRequest(
  payload: NotificationReadStateRequest,
): Promise<string> {
  const canonical = `v1\n${payload.source}\n${payload.alertKey}\n${payload.read ? "read" : "unread"}`;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function assertNotificationReadStateResult(
  value: unknown,
): NotificationReadStateResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "notification_state_unavailable",
      "Notification state result was unavailable.",
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
      "notification_state_unavailable",
      "Notification state result was invalid.",
    );
  }
  if (row.source != null && !notificationSources.includes(row.source as NotificationSource)) {
    throw new ApiError(
      503,
      "notification_state_unavailable",
      "Notification state source was invalid.",
    );
  }
  return row as unknown as NotificationReadStateResult;
}
