import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import { json } from "./http.ts";
import {
  hashAccessGrantActionRequest,
  matchAccessGrantActionPath,
  parseAccessGrantActionRequest,
} from "./relationship_access_grant_actions.ts";
import { createRelationshipAccessGrantActionStore } from "./relationship_access_grant_actions_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type RelationshipAccessGrantRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

function statusOf(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "access_grant_workflow_unavailable",
      "Access Grant workflow returned an invalid status.",
    );
  }
  return status;
}

export function createRelationshipAccessGrantRouteHandler(databaseUrl: string) {
  const store = createRelationshipAccessGrantActionStore(databaseUrl);
  return async function handleRelationshipAccessGrantRoute(
    context: RelationshipAccessGrantRouteContext,
  ): Promise<Response | null> {
    const route = matchAccessGrantActionPath(context.path);
    if (!route || context.request.method !== "POST") return null;

    requirePermission(context.admin, "relationships.access_grant.write");
    const idempotencyKey = requireIdempotencyKey(context.request);
    const payload = await parseAccessGrantActionRequest(
      context.request,
      route.action,
    );
    const requestHash = await hashAccessGrantActionRequest(
      route.grantId,
      route.action,
      payload,
    );
    const result = await store.mutate({
      actorAccountId: context.accountId,
      grantId: route.grantId,
      action: route.action,
      request: payload,
      correlationId: context.correlationId,
      idempotencyKey,
      requestHash,
    });
    const status = statusOf(result);
    if (status >= 400) {
      throw new ApiError(
        status,
        String(result.code),
        typeof result.message === "string"
          ? result.message
          : "Access Grant mutation was not completed.",
      );
    }

    return json(
      {
        grantId: String(result.grantId),
        action: String(result.action),
        status: String(result.status),
        version: Number(result.version),
        expiresAtUtc: result.expiresAtUtc == null
          ? null
          : String(result.expiresAtUtc),
        scopeCount: Number(result.scopeCount),
        noop: Boolean(result.noop),
        replayed: Boolean(result.replayed),
      },
      status,
      context.origin,
    );
  };
}
