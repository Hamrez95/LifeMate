export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export const ADMIN_MAX_PAGE = 100;
export const ADMIN_MAX_PAGE_SIZE = 100;
export const ADMIN_MAX_JSON_RESPONSE_BYTES = 512 * 1024;

export function normalizePath(pathname: string): string {
  const marker = "/lifemate-admin-api";
  const index = pathname.indexOf(marker);
  const path = index >= 0 ? pathname.slice(index + marker.length) : pathname;
  const normalized = `/${path}`.replace(/\/{2,}/g, "/");
  return normalized.length > 1 ? normalized.replace(/\/$/, "") : normalized;
}

export function requireUuid(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(
        value,
      )
  ) {
    throw new ApiError(400, "invalid_request", `${field} must be a UUID.`);
  }
  return value.toLowerCase();
}

export function boundedInteger(
  value: string | null,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (value == null || value === "") return fallback;
  if (!/^\d+$/.test(value)) {
    throw new ApiError(
      400,
      "invalid_request",
      "Query parameter must be an integer.",
    );
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new ApiError(
      400,
      "invalid_request",
      `Query parameter must be between ${minimum} and ${maximum}.`,
    );
  }
  return parsed;
}

export function boundedAdminPage(
  value: string | null,
  fallback = 1,
): number {
  return boundedInteger(value, fallback, 1, ADMIN_MAX_PAGE);
}

export function boundedAdminPageSize(
  value: string | null,
  fallback: number,
  minimum = 1,
  maximum = ADMIN_MAX_PAGE_SIZE,
): number {
  return boundedInteger(
    value,
    fallback,
    minimum,
    Math.min(maximum, ADMIN_MAX_PAGE_SIZE),
  );
}

export function assertAdminPaginationWindow(
  page: number,
  pageSize: number,
): void {
  const offset = (page - 1) * pageSize;
  if (
    !Number.isSafeInteger(offset) ||
    offset < 0 ||
    page > ADMIN_MAX_PAGE ||
    pageSize > ADMIN_MAX_PAGE_SIZE
  ) {
    throw new ApiError(
      400,
      "pagination_window_exceeded",
      "Requested page is outside the bounded admin pagination window; refine filters instead of deep paging.",
    );
  }
}

export function requireIdempotencyKey(request: Request): string {
  const value = request.headers.get("idempotency-key")?.trim() ?? "";
  if (!/^[A-Za-z0-9._:-]{8,180}$/.test(value)) {
    throw new ApiError(
      400,
      "idempotency_key_required",
      "A valid Idempotency-Key header is required.",
    );
  }
  return value;
}
