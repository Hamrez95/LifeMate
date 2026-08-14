import { ApiError, boundedInteger, requireUuid } from "./validation.ts";

export type SupportTicketStatus =
  | "Open"
  | "Pending"
  | "WaitingOnUser"
  | "Resolved"
  | "Closed";
export type SupportTicketPriority = "Low" | "Normal" | "High" | "Urgent";
export type SupportSlaState = "OnTrack" | "DueSoon" | "Breached" | "Completed";

export type SupportQueueQuery = {
  page: number;
  pageSize: number;
  offset: number;
  search: string | null;
  status: SupportTicketStatus | null;
  priority: SupportTicketPriority | null;
  product: string | null;
  sla: SupportSlaState | null;
  assigneeAccountId: string | null;
  unassignedOnly: boolean;
};

const STATUSES = new Set<SupportTicketStatus>([
  "Open",
  "Pending",
  "WaitingOnUser",
  "Resolved",
  "Closed",
]);
const PRIORITIES = new Set<SupportTicketPriority>([
  "Low",
  "Normal",
  "High",
  "Urgent",
]);
const SLA_STATES = new Set<SupportSlaState>([
  "OnTrack",
  "DueSoon",
  "Breached",
  "Completed",
]);

function optionalSearch(value: string | null): string | null {
  if (value == null) return null;
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  if (
    normalized.length < 2 ||
    normalized.length > 120 ||
    /[\u0000-\u001f\u007f]/.test(normalized)
  ) {
    throw new ApiError(400, "invalid_request", "Support search query is invalid.");
  }
  return normalized;
}

function optionalEnum<T extends string>(
  value: string | null,
  allowed: Set<T>,
  label: string,
): T | null {
  if (value == null || value === "") return null;
  if (!allowed.has(value as T)) {
    throw new ApiError(400, "invalid_request", `${label} filter is invalid.`);
  }
  return value as T;
}

function optionalProduct(value: string | null): string | null {
  if (value == null || value === "") return null;
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(value)) {
    throw new ApiError(400, "invalid_request", "Product filter is invalid.");
  }
  return value.toLowerCase();
}

function assigneeFilter(value: string | null): {
  assigneeAccountId: string | null;
  unassignedOnly: boolean;
} {
  if (value == null || value === "") {
    return { assigneeAccountId: null, unassignedOnly: false };
  }
  if (value === "unassigned") {
    return { assigneeAccountId: null, unassignedOnly: true };
  }
  return {
    assigneeAccountId: requireUuid(value, "assignee"),
    unassignedOnly: false,
  };
}

export function parseSupportQueueQuery(url: URL): SupportQueueQuery {
  const page = boundedInteger(url.searchParams.get("page"), 1, 1, 100_000);
  const pageSize = boundedInteger(url.searchParams.get("pageSize"), 25, 5, 100);
  const assignee = assigneeFilter(url.searchParams.get("assignee"));

  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    search: optionalSearch(url.searchParams.get("q")),
    status: optionalEnum(url.searchParams.get("status"), STATUSES, "Status"),
    priority: optionalEnum(
      url.searchParams.get("priority"),
      PRIORITIES,
      "Priority",
    ),
    product: optionalProduct(url.searchParams.get("product")),
    sla: optionalEnum(url.searchParams.get("sla"), SLA_STATES, "SLA"),
    assigneeAccountId: assignee.assigneeAccountId,
    unassignedOnly: assignee.unassignedOnly,
  };
}
