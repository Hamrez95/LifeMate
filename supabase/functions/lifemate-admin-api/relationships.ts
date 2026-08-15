import {
  ApiError,
  boundedAdminPage,
  boundedAdminPageSize,
} from "./validation.ts";

export type RelationshipOverviewKind =
  | "relationship"
  | "consent"
  | "access_grant";

export type RelationshipOverviewQuery = {
  page: number;
  pageSize: number;
  kind: RelationshipOverviewKind | null;
  status: string | null;
};

const KINDS = new Set<RelationshipOverviewKind>([
  "relationship",
  "consent",
  "access_grant",
]);

const STATUS_PATTERN = /^[A-Za-z][A-Za-z0-9_-]{0,31}$/;

function readKind(value: string | null): RelationshipOverviewKind | null {
  if (value == null || value === "") return null;
  const normalized = value.toLowerCase() as RelationshipOverviewKind;
  if (!KINDS.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Relationship overview kind is invalid.",
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
      "Relationship overview status is invalid.",
    );
  }
  return value;
}

export function parseRelationshipOverviewQuery(
  url: URL,
): RelationshipOverviewQuery {
  return {
    page: boundedAdminPage(url.searchParams.get("page")),
    pageSize: boundedAdminPageSize(url.searchParams.get("pageSize"), 25, 5),
    kind: readKind(url.searchParams.get("kind")),
    status: readStatus(url.searchParams.get("status")),
  };
}
