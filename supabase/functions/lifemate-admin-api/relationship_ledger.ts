import { ApiError, boundedInteger } from "./validation.ts";
import type { RelationshipOverviewKind } from "./relationships.ts";

export type RelationshipLedgerQuery = {
  page: number;
  pageSize: number;
  kind: RelationshipOverviewKind | null;
  status: string | null;
  from: string;
  to: string;
};

const KINDS = new Set<RelationshipOverviewKind>([
  "relationship",
  "consent",
  "access_grant",
]);
const STATUS_PATTERN = /^[A-Za-z][A-Za-z0-9_-]{0,31}$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function tehranDate(now: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tehran",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const value = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

function shiftDate(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function validDate(value: string): boolean {
  if (!DATE_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

function readDate(value: string | null, fallback: string): string {
  if (value == null || value === "") return fallback;
  if (!validDate(value)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Relationship ledger date filter is invalid.",
    );
  }
  return value;
}

function readKind(value: string | null): RelationshipOverviewKind | null {
  if (value == null || value === "") return null;
  const normalized = value.toLowerCase() as RelationshipOverviewKind;
  if (!KINDS.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Relationship ledger kind is invalid.",
    );
  }
  return normalized;
}

function readStatus(value: string | null): string | null {
  if (value == null || value === "") return null;
  if (!STATUS_PATTERN.test(value)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Relationship ledger status is invalid.",
    );
  }
  return value;
}

export function parseRelationshipLedgerQuery(
  url: URL,
  now = new Date(),
): RelationshipLedgerQuery {
  const today = tehranDate(now);
  const to = readDate(url.searchParams.get("to"), today);
  const from = readDate(url.searchParams.get("from"), shiftDate(to, -89));
  const fromMs = Date.parse(`${from}T00:00:00.000Z`);
  const toMs = Date.parse(`${to}T00:00:00.000Z`);
  const days = Math.floor((toMs - fromMs) / 86_400_000) + 1;
  if (days < 1 || days > 366) {
    throw new ApiError(
      400,
      "invalid_request",
      "Relationship ledger date range must contain between 1 and 366 days.",
    );
  }

  return {
    page: boundedInteger(url.searchParams.get("page"), 1, 1, 100_000),
    pageSize: boundedInteger(url.searchParams.get("pageSize"), 25, 5, 100),
    kind: readKind(url.searchParams.get("kind")),
    status: readStatus(url.searchParams.get("status")),
    from,
    to,
  };
}
