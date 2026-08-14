import { ApiError } from "./validation.ts";

const DETAIL_PATH = /^\/api\/v1\/users\/([0-9a-f-]{36})$/i;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function matchUserDetailPath(path: string): string | null {
  const match = DETAIL_PATH.exec(path);
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
