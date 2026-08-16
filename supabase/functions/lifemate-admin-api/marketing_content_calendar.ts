import { ApiError, requireUuid } from "./validation.ts";

export const marketingCalendarTimezones = ["Asia/Tehran", "UTC"] as const;
export type MarketingCalendarTimezone = (typeof marketingCalendarTimezones)[number];

export const marketingCalendarPublishStatuses = [
  "Scheduled",
  "Queued",
  "Processing",
  "Published",
  "Failed",
  "OutcomeUnknown",
  "Cancelled",
] as const;
export type MarketingCalendarPublishStatus =
  (typeof marketingCalendarPublishStatuses)[number];

export type MarketingContentCalendarQuery = {
  from: string;
  to: string;
  timezone: MarketingCalendarTimezone;
  status: MarketingCalendarPublishStatus | null;
};

export type MarketingSchedulePayload = {
  scheduledLocal: string;
  timezone: MarketingCalendarTimezone;
  reason: string;
};

export type MarketingExecutionActionPayload = { reason: string };

const SCHEDULE_PATH =
  /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/actions\/schedule-publish$/i;
const CANCEL_PATH =
  /^\/api\/v1\/marketing\/publish-executions\/([^/]+)\/actions\/cancel$/i;
const RETRY_PATH =
  /^\/api\/v1\/marketing\/publish-executions\/([^/]+)\/actions\/retry$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const LOCAL_DATE_TIME_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/;

function dateOnly(value: string, field: string): string {
  if (!DATE_PATTERN.test(value)) {
    throw new ApiError(400, "marketing_calendar_date_invalid", `${field} date is invalid.`);
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new ApiError(400, "marketing_calendar_date_invalid", `${field} date is invalid.`);
  }
  return value;
}

function timezone(value: string | null): MarketingCalendarTimezone {
  const normalized = value?.trim() || "Asia/Tehran";
  if (!marketingCalendarTimezones.includes(normalized as MarketingCalendarTimezone)) {
    throw new ApiError(
      400,
      "marketing_calendar_timezone_invalid",
      "Calendar timezone is not allowlisted.",
    );
  }
  return normalized as MarketingCalendarTimezone;
}

function reason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(400, "marketing_campaign_reason_invalid", "Reason is invalid.");
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "marketing_campaign_reason_invalid",
      "A reason between 10 and 1000 characters is required.",
    );
  }
  return normalized;
}

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("invalid");
    return body as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "invalid_request", "Request body must be a valid JSON object.");
  }
}

export function parseMarketingContentCalendarQuery(
  url: URL,
  now = new Date(),
): MarketingContentCalendarQuery {
  const defaultFrom = new Date(now.getTime() - 7 * 86_400_000).toISOString().slice(0, 10);
  const defaultTo = new Date(now.getTime() + 30 * 86_400_000).toISOString().slice(0, 10);
  const from = dateOnly(url.searchParams.get("from")?.trim() || defaultFrom, "from");
  const to = dateOnly(url.searchParams.get("to")?.trim() || defaultTo, "to");
  const fromMs = Date.parse(`${from}T00:00:00Z`);
  const toMs = Date.parse(`${to}T00:00:00Z`);
  if (toMs < fromMs || toMs - fromMs > 180 * 86_400_000) {
    throw new ApiError(
      400,
      "marketing_calendar_range_invalid",
      "Calendar range must be ordered and no longer than 180 days.",
    );
  }
  const rawStatus = url.searchParams.get("status")?.trim() || "";
  if (
    rawStatus &&
    !marketingCalendarPublishStatuses.includes(rawStatus as MarketingCalendarPublishStatus)
  ) {
    throw new ApiError(
      400,
      "marketing_calendar_status_invalid",
      "Calendar publish status is invalid.",
    );
  }
  return {
    from,
    to,
    timezone: timezone(url.searchParams.get("timezone")),
    status: rawStatus ? (rawStatus as MarketingCalendarPublishStatus) : null,
  };
}

export function matchMarketingSchedulePublishPath(path: string): string | null {
  const value = SCHEDULE_PATH.exec(path)?.[1];
  return value ? requireUuid(value, "campaignId") : null;
}

export function matchMarketingCancelExecutionPath(path: string): string | null {
  const value = CANCEL_PATH.exec(path)?.[1];
  return value ? requireUuid(value, "executionId") : null;
}

export function matchMarketingRetryExecutionPath(path: string): string | null {
  const value = RETRY_PATH.exec(path)?.[1];
  return value ? requireUuid(value, "executionId") : null;
}

export async function parseMarketingSchedulePayload(
  request: Request,
): Promise<MarketingSchedulePayload> {
  const body = await objectBody(request);
  if (typeof body.scheduledLocal !== "string" || !LOCAL_DATE_TIME_PATTERN.test(body.scheduledLocal)) {
    throw new ApiError(
      400,
      "marketing_schedule_time_invalid",
      "Scheduled local date/time is invalid.",
    );
  }
  return {
    scheduledLocal: body.scheduledLocal,
    timezone: timezone(typeof body.timezone === "string" ? body.timezone : null),
    reason: reason(body.reason),
  };
}

export async function parseMarketingExecutionActionPayload(
  request: Request,
): Promise<MarketingExecutionActionPayload> {
  const body = await objectBody(request);
  return { reason: reason(body.reason) };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function hashMarketingScheduleRequest(
  campaignId: string,
  payload: MarketingSchedulePayload,
): Promise<string> {
  return sha256(`v1\nschedule-publish\n${campaignId}\n${JSON.stringify(payload)}`);
}

export function hashMarketingExecutionActionRequest(
  action: "cancel" | "retry",
  executionId: string,
  payload: MarketingExecutionActionPayload,
): Promise<string> {
  return sha256(`v1\n${action}\n${executionId}\n${payload.reason}`);
}
