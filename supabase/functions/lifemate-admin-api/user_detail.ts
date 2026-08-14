import { ApiError, boundedInteger } from "./validation.ts";

const DETAIL_PATH = /^\/api\/v1\/users\/([0-9a-f-]{36})$/i;
const ACTIVITY_PATH = /^\/api\/v1\/users\/([0-9a-f-]{36})\/activity$/i;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type UserActivityQuery = {
  page: number;
  pageSize: number;
};

function readAccountId(match: RegExpExecArray | null): string | null {
  if (!match) return null;
  const accountId = match[1];
  if (!UUID_PATTERN.test(accountId)) {
    throw new ApiError(
      404,
      "route_not_found",
      "Admin API route was not found.",
    );
  }
  return accountId.toLowerCase();
}

export function matchUserDetailPath(path: string): string | null {
  return readAccountId(DETAIL_PATH.exec(path));
}

export function matchUserActivityPath(path: string): string | null {
  return readAccountId(ACTIVITY_PATH.exec(path));
}

export function parseUserActivityQuery(url: URL): UserActivityQuery {
  return {
    page: boundedInteger(url.searchParams.get("page"), 1, 1, 100_000),
    pageSize: boundedInteger(url.searchParams.get("pageSize"), 20, 5, 50),
  };
}
