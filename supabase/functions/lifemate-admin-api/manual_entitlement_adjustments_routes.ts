import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  hashManualEntitlementPayload,
  matchManualEntitlementHistoryPath,
  parseManualEntitlementPayload,
} from "./manual_entitlement_adjustments.ts";
import { createManualEntitlementAdjustmentStore } from "./manual_entitlement_adjustments_service.ts";
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
      "entitlement_adjustment_unavailable",
      "Entitlement adjustment workflow returned an invalid status.",
    );
  }
  if (value >= 400) {
    throw new ApiError(
      value,
      String(result.code ?? "entitlement_adjustment_failed"),
      typeof result.message === "string"
        ? result.message
        : "Entitlement adjustment failed.",
    );
  }
  return value;
}

function historyLimit(url: URL): number {
  const raw = url.searchParams.get("limit");
  if (raw == null) return 50;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 100) {
    throw new ApiError(
      400,
      "limit_invalid",
      "limit must be between 1 and 100.",
    );
  }
  return value;
}

export function createManualEntitlementAdjustmentRouteHandler(
  databaseUrl: string,
) {
  const store = createManualEntitlementAdjustmentStore(databaseUrl);

  return async function handleManualEntitlementAdjustmentRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    const historyAccountId = matchManualEntitlementHistoryPath(path);
    if (request.method === "GET" && historyAccountId) {
      requirePermission(admin, "commerce.entitlement.adjust.read");
      const limit = historyLimit(new URL(request.url));
      return json(
        {
          subjectAccountId: historyAccountId,
          items: await store.history(historyAccountId, limit),
          limit,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/preview"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.request");
      const payload = await parseManualEntitlementPayload(request);
      const result = await store.preview(payload);
      return json(
        {
          ...result,
          normalized: payload,
          approvalRequestTemplate: {
            requestType: "manual_entitlement_adjustment",
            targetType: "account",
            targetId: payload.subjectAccountId,
            before: result.before,
            delta: result.delta,
            after: result.after,
            reason: payload.reason,
          },
        },
        status(result),
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/requests"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.request");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseManualEntitlementPayload(request, {
        requireReference: true,
      });
      const requestHash = await hashManualEntitlementPayload(payload);
      const result = await store.request({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/entitlement-adjustments/execute"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.execute");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseManualEntitlementPayload(request, {
        requireReference: true,
        requireConfirmation: true,
      });
      const requestHash = await hashManualEntitlementPayload(payload);
      const result = await store.execute({
        actorAccountId: accountId,
        isFounder: admin.roles.includes("founder"),
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      return json(result, status(result), origin);
    }

    return null;
  };
}
