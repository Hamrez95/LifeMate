import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import { parseElevatedHealthQuery } from "./elevated_health.ts";
import { createElevatedHealthStore } from "./elevated_health_service.ts";
import { json } from "./http.ts";
import { ApiError } from "./validation.ts";

export type ElevatedHealthRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

export function createElevatedHealthRouteHandler(databaseUrl: string) {
  const store = createElevatedHealthStore(databaseUrl);
  return async function handleElevatedHealthRoute(
    context: ElevatedHealthRouteContext,
  ): Promise<Response | null> {
    if (context.request.method !== "GET") return null;
    const query = parseElevatedHealthQuery(new URL(context.request.url));
    if (!query) return null;

    // Ordinary permission remains an additional kill switch. It never substitutes
    // for the exact active break-glass grant checked inside the security-definer projection.
    requirePermission(context.admin, "security.break_glass.request");
    const result = await store.read({
      actorAccountId: context.accountId,
      query,
      correlationId: context.correlationId,
    });
    const status = Number(result.httpStatus);
    if (status === 403) {
      throw new ApiError(
        403,
        String(result.code),
        "No active exact break-glass grant permits this elevated read.",
      );
    }
    if (status >= 400 || status < 200 || status > 299) {
      throw new ApiError(
        Number.isInteger(status) ? status : 503,
        typeof result.code === "string"
          ? result.code
          : "elevated_health_unavailable",
        "Elevated health read was not completed.",
      );
    }
    return json(
      {
        ...result,
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      },
      200,
      context.origin,
    );
  };
}
