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
import { parseCommerceCatalogV2Query } from "./commerce_catalog_v2.ts";
import { createCommerceCatalogV2MutationRouteHandler } from "./commerce_catalog_v2_mutation_routes.ts";
import { createCommerceCatalogV2Store } from "./commerce_catalog_v2_service.ts";
import { createCommerceDiscountCodeStore } from "./commerce_discount_codes_service.ts";
import {
  hashDiscountCodeStatusRequest,
  hashIssueDiscountCodesRequest,
  matchCommerceDiscountCodeStatusPath,
  matchCommercePromotionCodesPath,
  parseDiscountCodeStatusPayload,
  parseIssueDiscountCodesPayload,
} from "./commerce_promotions.ts";
import { createGrowthRewardAdminRouteHandler } from "./growth_reward_admin_routes.ts";
import { createManualEntitlementAdjustmentRouteHandler } from "./manual_entitlement_adjustments_routes.ts";
import { createPaymentOperationsRouteHandler } from "./payment_operations_routes.ts";
import {
  hashGiftTestFinalizePayload,
  parseGiftTestFinalizePayload,
} from "./gift_test_operations.ts";
import { createGiftTestOperationsStore } from "./gift_test_operations_service.ts";
import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

function status(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(
      503,
      "commerce_catalog_workflow_unavailable",
      "Commerce catalog workflow returned an invalid status.",
    );
  }
  return value;
}

function failureMessage(
  result: Record<string, unknown>,
  fallback: string,
): string {
  return typeof result.message === "string" ? result.message : fallback;
}

export function createCommerceCatalogRouteHandler(databaseUrl: string) {
  const store = createCommerceCatalogStore(databaseUrl);
  const catalogV2Store = createCommerceCatalogV2Store(databaseUrl);
  const catalogV2MutationRouteHandler =
    createCommerceCatalogV2MutationRouteHandler(databaseUrl);
  const discountCodeStore = createCommerceDiscountCodeStore(databaseUrl);
  const growthRewardAdminRouteHandler = createGrowthRewardAdminRouteHandler(
    databaseUrl,
  );
  const manualEntitlementRouteHandler =
    createManualEntitlementAdjustmentRouteHandler(databaseUrl);
  const paymentOperationsRouteHandler = createPaymentOperationsRouteHandler(
    databaseUrl,
  );
  const giftTestOperationsStore = createGiftTestOperationsStore(databaseUrl);

  return async function commerceCatalogRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    const catalogV2MutationResponse = await catalogV2MutationRouteHandler(
      input,
    );
    if (catalogV2MutationResponse) return catalogV2MutationResponse;

    if (path.startsWith("/api/v1/commerce/rewards/")) {
      const response = await growthRewardAdminRouteHandler(input);
      if (response) return response;
    }

    if (
      path === "/api/v1/commerce/refunds" ||
      path.startsWith("/api/v1/commerce/refunds/") ||
      path === "/api/v1/commerce/churn" ||
      path.startsWith("/api/v1/commerce/reconciliation/") ||
      path === "/api/v1/commerce/subscriptions/renewal-intent"
    ) {
      const response = await paymentOperationsRouteHandler(input);
      if (response) return response;
    }

    if (
      path.startsWith("/api/v1/commerce/entitlement-adjustments") ||
      /^\/api\/v1\/commerce\/accounts\/[^/]+\/entitlement-adjustments$/i.test(
        path,
      )
    ) {
      const response = await manualEntitlementRouteHandler(input);
      if (response) return response;
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/gifts/test-finalize"
    ) {
      requirePermission(admin, "commerce.entitlement.adjust.execute");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseGiftTestFinalizePayload(request);
      const requestHash = await hashGiftTestFinalizePayload(payload);
      const result = await giftTestOperationsStore.finalize({
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
          failureMessage(result, "Gift test finalization was not completed."),
        );
      }
      return json(result, httpStatus, origin);
    }

    if (request.method === "GET" && path === "/api/v1/commerce/catalog-v2") {
      requirePermission(admin, "commerce.read");
      return json(
        {
          ...(await catalogV2Store.get(
            parseCommerceCatalogV2Query(new URL(request.url)),
          )),
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const discountCodeStatusPath = matchCommerceDiscountCodeStatusPath(path);
    if (request.method === "POST" && discountCodeStatusPath) {
      requirePermission(admin, "commerce.discount_code.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseDiscountCodeStatusPayload(request);
      const requestHash = await hashDiscountCodeStatusRequest(
        discountCodeStatusPath.promotionId,
        discountCodeStatusPath.codeId,
        payload,
      );
      const result = await discountCodeStore.setStatus({
        actorAccountId: accountId,
        promotionId: discountCodeStatusPath.promotionId,
        codeId: discountCodeStatusPath.codeId,
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
          failureMessage(
            result,
            "Discount-code status change was not completed.",
          ),
        );
      }
      return json(
        {
          promotionId: String(result.promotionId),
          codeId: String(result.codeId),
          previousStatus: String(result.previousStatus),
          status: String(result.status),
          version: Number(result.version),
          noop: Boolean(result.noop),
          replayed: Boolean(result.replayed),
        },
        httpStatus,
        origin,
      );
    }

    const promotionCodesId = matchCommercePromotionCodesPath(path);
    if (request.method === "GET" && promotionCodesId) {
      requirePermission(admin, "commerce.read");
      const items = await discountCodeStore.list(promotionCodesId);
      return json(
        {
          promotionId: promotionCodesId,
          items,
          total: items.length,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" && promotionCodesId) {
      requirePermission(admin, "commerce.discount_code.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseIssueDiscountCodesPayload(request);
      const requestHash = await hashIssueDiscountCodesRequest(
        promotionCodesId,
        payload,
      );
      const result = await discountCodeStore.issue({
        actorAccountId: accountId,
        promotionId: promotionCodesId,
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
          failureMessage(result, "Discount-code issuance was not completed."),
        );
      }
      return json(
        {
          promotionId: promotionCodesId,
          issuedCount: Number(result.issuedCount),
          items: Array.isArray(result.items) ? result.items : [],
          replayed: Boolean(result.replayed),
        },
        httpStatus,
        origin,
      );
    }

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
      const requestHash = await hashScheduleCommercePriceRequest(
        pricePlanId,
        payload,
      );
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
