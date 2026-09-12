import {
  hashBreakGlassActionRequest,
  hashBreakGlassCreateRequest,
  matchBreakGlassActionPath,
  parseBreakGlassActionRequest,
  parseBreakGlassCreateRequest,
} from "./break_glass.ts";
import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import { json } from "./http.ts";
import { createBreakGlassStore } from "./break_glass_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type BreakGlassRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "break_glass_unavailable",
      "Break-glass workflow returned an invalid status.",
    );
  }
  return status;
}

export function createBreakGlassRouteHandler(databaseUrl: string) {
  const store = createBreakGlassStore(databaseUrl);

  return async function handleBreakGlassRoute(
    context: BreakGlassRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (
      request.method === "GET" &&
      path === "/api/v1/security/break-glass/requests"
    ) {
      if (
        !admin.permissions.includes("security.break_glass.request") &&
        !admin.permissions.includes("security.break_glass.approve")
      ) {
        requirePermission(admin, "security.break_glass.request");
      }
      return json(
        {
          items: await store.list(accountId),
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/security/break-glass/requests"
    ) {
      requirePermission(admin, "security.break_glass.request");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseBreakGlassCreateRequest(request);
      const requestHash = await hashBreakGlassCreateRequest(payload);
      const result = await store.create({
        actorAccountId: accountId,
        request: payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          typeof result.message === "string"
            ? result.message
            : "Break-glass request was not created.",
        );
      }
      return json(result, status, origin);
    }

    const actionRoute = matchBreakGlassActionPath(path);
    if (request.method === "POST" && actionRoute) {
      if (actionRoute.action === "approve" || actionRoute.action === "deny") {
        requirePermission(admin, "security.break_glass.approve");
      } else if (
        !admin.permissions.includes("security.break_glass.request") &&
        !admin.permissions.includes("security.break_glass.approve")
      ) {
        requirePermission(admin, "security.break_glass.request");
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseBreakGlassActionRequest(request);
      const requestHash = await hashBreakGlassActionRequest(
        actionRoute.requestId,
        actionRoute.action,
        payload,
      );
      const result = await store.mutate({
        actorAccountId: accountId,
        requestId: actionRoute.requestId,
        action: actionRoute.action,
        request: payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) {
        throw new ApiError(
          status,
          String(result.code),
          typeof result.message === "string"
            ? result.message
            : "Break-glass request was not changed.",
        );
      }
      return json(result, status, origin);
    }

    return null;
  };
}
