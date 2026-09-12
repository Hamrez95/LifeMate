import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  matchAdminCircleDetailPath,
  parseAdminCircleListQuery,
} from "./circle_directory.ts";
import { createAdminCircleDirectoryStore } from "./circle_directory_store.ts";
import { json } from "./http.ts";
import { ApiError } from "./validation.ts";

export function createAdminCircleDirectoryRouteHandler(databaseUrl: string) {
  const store = createAdminCircleDirectoryStore(databaseUrl);

  return async function adminCircleDirectoryRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, admin, origin } = input;

    if (request.method === "GET" && path === "/api/v1/circles") {
      requirePermission(admin, "relationships.read");
      const query = parseAdminCircleListQuery(new URL(request.url));
      const result = await store.list(query);
      return json(
        {
          ...result,
          filters: {
            status: query.status ?? null,
            kind: query.kind ?? null,
            ownerPersonId: query.ownerPersonId ?? null,
            memberPersonId: query.memberPersonId ?? null,
            q: query.q ?? null,
          },
          source: {
            kind: "canonical",
            label: "LifeMate Circle structural directory",
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    const circleId = matchAdminCircleDetailPath(path);
    if (request.method === "GET" && circleId) {
      requirePermission(admin, "relationships.read");
      const result = await store.detail(circleId);
      if (!result) {
        throw new ApiError(404, "circle_not_found", "Circle was not found.");
      }
      return json(
        {
          ...result,
          source: {
            kind: "canonical",
            label: "LifeMate Circle structural detail",
          },
          privacy: {
            scope: "structure_only",
            protectedHealthContentIncluded: false,
          },
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
