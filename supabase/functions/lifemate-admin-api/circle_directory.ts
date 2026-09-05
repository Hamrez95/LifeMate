import {
  ApiError,
  boundedAdminPage,
  boundedAdminPageSize,
  requireUuid,
} from "./validation.ts";

const CIRCLE_STATUSES = new Set(["active", "closed"]);
const CIRCLE_KINDS = new Set([
  "women_health_planning",
  "family",
  "care",
  "pregnancy_support",
]);

export type AdminCircleStatus = "active" | "closed";
export type AdminCircleKind =
  | "women_health_planning"
  | "family"
  | "care"
  | "pregnancy_support";

function optionalEnum<T extends string>(
  value: string | null,
  allowed: ReadonlySet<string>,
  field: string,
): T | undefined {
  if (value == null || value.trim() === "") return undefined;
  const normalized = value.trim();
  if (!allowed.has(normalized)) {
    throw new ApiError(400, "invalid_request", `${field} is invalid.`);
  }
  return normalized as T;
}

function optionalUuid(value: string | null, field: string): string | undefined {
  if (value == null || value.trim() === "") return undefined;
  return requireUuid(value.trim(), field);
}

function optionalSearch(value: string | null): string | undefined {
  if (value == null || value.trim() === "") return undefined;
  const normalized = value.trim();
  if (normalized.length < 2 || normalized.length > 80) {
    throw new ApiError(
      400,
      "invalid_request",
      "q must be between 2 and 80 characters.",
    );
  }
  return normalized;
}

export function parseAdminCircleListQuery(url: URL) {
  return {
    page: boundedAdminPage(url.searchParams.get("page"), 1),
    pageSize: boundedAdminPageSize(url.searchParams.get("pageSize"), 25, 1, 100),
    status: optionalEnum<AdminCircleStatus>(
      url.searchParams.get("status"),
      CIRCLE_STATUSES,
      "status",
    ),
    kind: optionalEnum<AdminCircleKind>(
      url.searchParams.get("kind"),
      CIRCLE_KINDS,
      "kind",
    ),
    ownerPersonId: optionalUuid(
      url.searchParams.get("ownerPersonId"),
      "ownerPersonId",
    ),
    memberPersonId: optionalUuid(
      url.searchParams.get("memberPersonId"),
      "memberPersonId",
    ),
    q: optionalSearch(url.searchParams.get("q")),
  };
}

export function matchAdminCircleDetailPath(path: string): string | null {
  const match = path.match(/^\/api\/v1\/circles\/([^/]+)$/);
  if (!match) return null;
  return requireUuid(match[1], "circleId");
}
