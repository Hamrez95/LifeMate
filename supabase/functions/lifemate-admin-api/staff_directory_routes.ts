import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  encodeStaffDirectoryCursor,
  matchStaffDetailPath,
  parseStaffDirectoryQuery,
} from "./staff_directory.ts";
import { createStaffDirectoryStore } from "./staff_directory_service.ts";
import { createCommandCenterPreferencesRouteHandler } from "./settings_preferences_routes.ts";
import { ApiError } from "./validation.ts";

export function createStaffDirectoryRouteHandler(databaseUrl: string) {
  const store = createStaffDirectoryStore(databaseUrl);
  const preferencesRouteHandler = createCommandCenterPreferencesRouteHandler(databaseUrl);

  return async function staffDirectoryRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    // Keep the settings contract in the authenticated Admin API routing layer without
    // exposing it to browser/direct-database access. This route handler is invoked
    // immediately after the canonical admin snapshot is resolved in index.ts.
    const preferencesResponse = await preferencesRouteHandler(input);
    if (preferencesResponse) return preferencesResponse;

    if (request.method === "GET" && path === "/api/v1/staff") {
      requirePermission(admin, "security.staff.manage");
      const query = parseStaffDirectoryQuery(new URL(request.url));
      const rows = await store.list(query);
      const hasNext = rows.length > query.pageSize;
      const items = hasNext ? rows.slice(0, query.pageSize) : rows;
      const last = items.at(-1);
      const nextCursor = hasNext && last
        ? encodeStaffDirectoryCursor({
          createdAtUtc: last.createdAtUtc,
          accountId: last.accountId,
        })
        : null;
      return json(
        {
          items,
          nextCursor,
          pageSize: query.pageSize,
          filters: {
            status: query.status,
            role: query.roleCode,
            q: query.q,
          },
          mfaPostureSource: "unavailable",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const targetAccountId = matchStaffDetailPath(path);
    if (request.method === "GET" && targetAccountId) {
      requirePermission(admin, "security.staff.manage");
      requirePermission(admin, "security.staff.audit.read");
      const detail = await store.getDetail(targetAccountId);
      if (!detail) {
        throw new ApiError(404, "staff_not_found", "Staff member was not found.");
      }
      await store.auditDetailRead(accountId, targetAccountId, correlationId);
      return json(
        {
          staff: detail,
          mfaPostureSource: "unavailable",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
