import { ApiError, boundedInteger, requireUuid } from "./validation.ts";

export type SupportTicketAction =
  | "add_note"
  | "set_status"
  | "set_priority"
  | "set_assignee";

export type SupportTicketActionPayload =
  | { note: string }
  | { status: "Open" | "Pending" | "WaitingOnUser" | "Resolved" | "Closed" }
  | { priority: "Low" | "Normal" | "High" | "Urgent" }
  | { assigneeAccountId: string | null };

export type SupportTicketActionRoute = {
  ticketId: string;
  action: SupportTicketAction;
};

export type SupportTicketEventsQuery = {
  page: number;
  pageSize: number;
  offset: number;
};

export type SupportTicketActionResult = {
  httpStatus: number;
  code: string;
  message?: string;
  ticketId?: string;
  status?: string;
  priority?: string;
  assignedAdminAccountId?: string | null;
  lastActivityAtUtc?: string;
  action?: SupportTicketAction;
  replayed: boolean;
};

const DETAIL_PATH = /^\/api\/v1\/support\/tickets\/([^/]+)$/i;
const EVENTS_PATH = /^\/api\/v1\/support\/tickets\/([^/]+)\/events$/i;
const ACTION_PATH =
  /^\/api\/v1\/support\/tickets\/([^/]+)\/actions\/(note|status|priority|assignee)$/i;

const ACTION_ALIASES: Record<string, SupportTicketAction> = {
  note: "add_note",
  status: "set_status",
  priority: "set_priority",
  assignee: "set_assignee",
};

const STATUSES = new Set(["Open", "Pending", "WaitingOnUser", "Resolved", "Closed"]);
const PRIORITIES = new Set(["Low", "Normal", "High", "Urgent"]);

function matchTicketId(path: string, pattern: RegExp): string | null {
  const match = pattern.exec(path);
  if (!match) return null;
  return requireUuid(match[1], "ticketId");
}

export function matchSupportTicketDetailPath(path: string): string | null {
  return matchTicketId(path, DETAIL_PATH);
}

export function matchSupportTicketEventsPath(path: string): string | null {
  return matchTicketId(path, EVENTS_PATH);
}

export function matchSupportTicketActionPath(
  path: string,
): SupportTicketActionRoute | null {
  const match = ACTION_PATH.exec(path);
  if (!match) return null;
  return {
    ticketId: requireUuid(match[1], "ticketId"),
    action: ACTION_ALIASES[match[2].toLowerCase()],
  };
}

export function parseSupportTicketEventsQuery(url: URL): SupportTicketEventsQuery {
  const page = boundedInteger(url.searchParams.get("page"), 1, 1, 100_000);
  const pageSize = boundedInteger(url.searchParams.get("pageSize"), 20, 5, 50);
  return { page, pageSize, offset: (page - 1) * pageSize };
}

async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be valid JSON.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "invalid_request", "Request body must be an object.");
  }
  return value as Record<string, unknown>;
}

export async function parseSupportTicketActionPayload(
  request: Request,
  action: SupportTicketAction,
): Promise<SupportTicketActionPayload> {
  const body = await readJsonObject(request);

  if (action === "add_note") {
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (note.length < 10 || note.length > 2000) {
      throw new ApiError(
        400,
        "support_note_invalid",
        "Internal note must contain between 10 and 2000 characters.",
      );
    }
    return { note };
  }

  if (action === "set_status") {
    const status = typeof body.status === "string" ? body.status : "";
    if (!STATUSES.has(status)) {
      throw new ApiError(400, "support_status_invalid", "Support status is invalid.");
    }
    return {
      status: status as "Open" | "Pending" | "WaitingOnUser" | "Resolved" | "Closed",
    };
  }

  if (action === "set_priority") {
    const priority = typeof body.priority === "string" ? body.priority : "";
    if (!PRIORITIES.has(priority)) {
      throw new ApiError(
        400,
        "support_priority_invalid",
        "Support priority is invalid.",
      );
    }
    return { priority: priority as "Low" | "Normal" | "High" | "Urgent" };
  }

  const assignee = body.assigneeAccountId;
  if (assignee === null || assignee === "" || assignee === undefined) {
    return { assigneeAccountId: null };
  }
  if (typeof assignee !== "string") {
    throw new ApiError(
      400,
      "support_assignee_invalid",
      "Support assignee is invalid.",
    );
  }
  return { assigneeAccountId: requireUuid(assignee, "assigneeAccountId") };
}

export async function hashSupportTicketActionRequest(
  ticketId: string,
  action: SupportTicketAction,
  payload: SupportTicketActionPayload,
): Promise<string> {
  const canonical = `v1\n${ticketId}\n${action}\n${JSON.stringify(payload)}`;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function assertSupportTicketActionResult(
  value: unknown,
): SupportTicketActionResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "support_action_unavailable",
      "Support ticket action result was unavailable.",
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
      "support_action_unavailable",
      "Support ticket action result was invalid.",
    );
  }
  return row as unknown as SupportTicketActionResult;
}
