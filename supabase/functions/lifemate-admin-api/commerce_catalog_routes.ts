import {
  hashCreateCommercePlanRequest,
  hashScheduleCommercePriceRequest,
  hashUpdateCommercePlanRequest,
  matchCommerceCatalogPlanPath,
  matchCommercePlanPricesPath,
  parseCreateCommercePlanPayload,
  parseScheduleCommercePricePayload,
  parseUpdateCommercePlanPayload,
} from "./commerce_catalog.ts";
import { createCommerceCatalogStore } from "./commerce_catalog_service.ts";
import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

function status(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(503, "commerce_catalog_workflow_unavailable", "Commerce catalog workflow returned an invalid status.");
  }
  return value;
}

function failureMessage(result: Record<string, unknown>, fallback: string): string {
  return typeof result.message === "string" ? result.message : fallback;
}

export function createCommerceCatalogRouteHandler(databaseUrl: string) {
  const store = createCommerceCatalogStore(databaseUrl);

  return async function commerceCatalogRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    if (request.method === "POST" && path === "/api/v1/commerce/plans") {
      requirePermission(admin, "commerce.plan.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCreateCommercePlanPayload(request);
      const requestHash = await hashCreateCommercePlanRequest(payload);
      const result = await store.createPlan({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const httpStatus = status(result);
      if (httpStatus >= 400) {
        throw new ApiError(
          httpStatus,
          String(result.code),
          failureMessage(result, "Plan creation was not completed."),
        );
      }
      return json(
        {
          planId: String(result.planId),
          status: String(result.status),
          replayed: Boolean(result.replayed),
        },
        httpStatus,
        origin,
      );
    }

    const pricePlanId = matchCommercePlanPricesPath(path);
    if (request.method === "POST" && pricePlanId) {
      requirePermission(admin, "commerce.price.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseScheduleCommercePricePayload(request);
      const requestHash = await hashScheduleCommercePriceRequest(pricePlanId, payload);
      const result = await store.schedulePrice({
        actorAccountId: accountId,
        planId: pricePlanId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const httpStatus = status(result);
      if (httpStatus >= 400) {
        throw new ApiError(
          httpStatus,
          String(result.code),
          failureMessage(result, "Price scheduling was not completed."),
        );
      }
      return json(
        {
          priceId: String(result.priceId),
          planId: String(result.planId),
          effectiveFromUtc: String(result.effectiveFromUtc),
          replayed: Boolean(result.replayed),
        },
        httpStatus,
        origin,
      );
    }

    const planId = matchCommerceCatalogPlanPath(path);
    if (request.method === "PUT" && planId) {
      requirePermission(admin, "commerce.plan.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseUpdateCommercePlanPayload(request);
      const requestHash = await hashUpdateCommercePlanRequest(planId, payload);
      const result = await store.updatePlan({
        actorAccountId: accountId,
        planId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const httpStatus = status(result);
      if (httpStatus >= 400) {
        throw new ApiError(
          httpStatus,
          String(result.code),
          failureMessage(result, "Plan update was not completed."),
        );
      }
      return json(
        {
          planId: String(result.planId),
          previousStatus: String(result.previousStatus),
          status: String(result.status),
          replayed: Boolean(result.replayed),
        },
        httpStatus,
        origin,
      );
    }

    return null;
  };
}
