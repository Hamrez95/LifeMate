import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  hashEntitlementAdjustmentRequest,
  matchEntitlementAdjustmentHistoryPath,
  parseExecuteEntitlementAdjustmentPayload,
} from "./entitlement_adjustments.ts";
import { createEntitlementAdjustmentStore } from "./entitlement_adjustments_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

function status(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(
      503,
      "entitlement_adjust_workflow_unavailable",
      "Entitlement adjustment workflow returned an invalid status.",
    );
  }
  return value;
}

function throwIfError(result: Record<string, unknown>): number {
  const httpStatus = status(result);
  if (httpStatus >= 400) {
    throw new ApiError(
      httpStatus,
      String(result.code ?? "entitlement_adjust_failed"),
      typeof result.message === "string"
        ? result.message
        : "Entitlement adjustment was not completed.",
    );
  }
  return httpStatus;
}

function historyLimit(url: URL): number {
  const raw = url.searchParams.get("limit");
  if (raw == null) return 50;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 100) {
    throw new ApiError(
      400,
      "entitlement_adjust_limit_invalid",
      "limit must be an integer between 1 and 100.",
    );
  }
  return value;
}

export function createEntitlementAdjustmentRouteHandler(databaseUrl: string) {
  const store = createEntitlementAdjustmentStore(databaseUrl);
  return async function handleEntitlementAdjustmentRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    const subjectAccountId = matchEntitlementAdjustmentHistoryPath(path);
    if (request.method === "GET" && subjectAccountId) {
      requirePermission(admin, "commerce.entitlement.adjust.read");
      const limit = historyLimit(new URL(request.url));
      const items = await store.history(subjectAccountId, limit);
      return json(
        {
          subjectAccountId,
          items,
          limit,
          source: { kind: "canonical", label: "LifeMate entitlement adjustment ledger" },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/requests"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.request");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseExecuteEntitlementAdjustmentPayload(request);
      const requestHash = await hashEntitlementAdjustmentRequest(payload);
      const result = await store.request({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const httpStatus = throwIfError(result);
      return json(result, httpStatus, origin);
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/execute"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.execute");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseExecuteEntitlementAdjustmentPayload(request);
      const requestHash = await hashEntitlementAdjustmentRequest(payload);
      const result = await store.execute({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const httpStatus = throwIfError(result);
      return json(result, httpStatus, origin);
    }

    return null;
  };
}
