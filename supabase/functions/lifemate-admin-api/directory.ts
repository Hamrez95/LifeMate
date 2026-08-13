import { ApiError, boundedInteger } from "./validation.ts";

export type UserDirectorySort = "createdAt" | "displayName" | "lastActiveAt";
export type SortDirection = "asc" | "desc";

export type UserDirectoryQuery = {
  page: number;
  pageSize: number;
  offset: number;
  search: string | null;
  status: string | null;
  application: string | null;
  sort: UserDirectorySort;
  direction: SortDirection;
};

const ACCOUNT_STATUSES = new Set(["Active", "Disabled", "DeletionPending"]);
const SORTS = new Set<UserDirectorySort>([
  "createdAt",
  "displayName",
  "lastActiveAt",
]);

function optionalSearch(value: string | null): string | null {
  if (value == null) return null;
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  if (normalized.length > 120 || /[\u0000-\u001f\u007f]/.test(normalized)) {
    throw new ApiError(400, "invalid_request", "Search query is invalid.");
  }
  if (normalized.length < 2) {
    throw new ApiError(400, "invalid_request", "Search query is too short.");
  }
  return normalized;
}

function optionalStatus(value: string | null): string | null {
  if (value == null || value === "") return null;
  if (!ACCOUNT_STATUSES.has(value)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Account status filter is invalid.",
    );
  }
  return value;
}

function optionalApplication(value: string | null): string | null {
  if (value == null || value === "") return null;
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(value)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Application filter is invalid.",
    );
  }
  return value.toLowerCase();
}

export function parseUserDirectoryQuery(url: URL): UserDirectoryQuery {
  const page = boundedInteger(url.searchParams.get("page"), 1, 1, 10_000);
  const pageSize = boundedInteger(url.searchParams.get("pageSize"), 25, 1, 100);
  const search = optionalSearch(url.searchParams.get("q"));
  const status = optionalStatus(url.searchParams.get("status"));
  const application = optionalApplication(url.searchParams.get("application"));

  const rawSort = url.searchParams.get("sort") ?? "createdAt";
  if (!SORTS.has(rawSort as UserDirectorySort)) {
    throw new ApiError(400, "invalid_request", "Sort field is invalid.");
  }
  const sort = rawSort as UserDirectorySort;

  const rawDirection = url.searchParams.get("direction") ?? "desc";
  if (rawDirection !== "asc" && rawDirection !== "desc") {
    throw new ApiError(400, "invalid_request", "Sort direction is invalid.");
  }

  return {
    page,
    pageSize,
    offset: (page - 1) * pageSize,
    search,
    status,
    application,
    sort,
    direction: rawDirection,
  };
}
