import {
  hashConfigureCommercePlanFeatureRequest,
  matchCommercePlanFeaturesPath,
  parseConfigureCommercePlanFeaturePayload,
} from "./commerce_plan_features.ts";
import { createCommercePlanFeatureStore } from "./commerce_plan_features_service.ts";
import { createCommerceSubscriptionAuditStore } from "./commerce_subscription_audit_service.ts";
import {
  hashConfigureCommerceTrialRequest,
  matchCommerceTrialPolicyPath,
  parseConfigureCommerceTrialPayload,
} from "./commerce_trial.ts";
import { createCommerceTrialStore } from "./commerce_trial_service.ts";
import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  ApiError,
  boundedAdminPage,
  boundedAdminPageSize,
  requireIdempotencyKey,
} from "./validation.ts";

function checkedStatus(result: Record<string, unknown>, workflow: string): number {
  const httpStatus = Number(result.httpStatus);
  if (!Number.isInteger(httpStatus) || httpStatus < 100 || httpStatus > 599) {
    throw new ApiError(
      503,
      `${workflow}_workflow_unavailable`,
      "Commerce workflow returned an invalid status.",
    );
  }
  return httpStatus;
}

export function createCommerceTrialRouteHandler(databaseUrl: string) {
  const trialStore = createCommerceTrialStore(databaseUrl);
  const planFeatureStore = createCommercePlanFeatureStore(databaseUrl);
  const subscriptionAuditStore = createCommerceSubscriptionAuditStore(databaseUrl);

  return async function commerceTrialRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    if (
      request.method === "GET" &&
      (path === "/api/v1/commerce/conversions" || path === "/api/v1/commerce/gifts")
    ) {
      requirePermission(admin, "commerce.read");
      const url = new URL(request.url);
      const query = {
        page: boundedAdminPage(url.searchParams.get("page")),
        pageSize: boundedAdminPageSize(url.searchParams.get("pageSize"), 25),
      };
      const data = path.endsWith("/conversions")
        ? await subscriptionAuditStore.conversions(query)
        : await subscriptionAuditStore.gifts(query);
      return json(
        {
          ...data,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const planFeaturePlanId = matchCommercePlanFeaturesPath(path);
    if (planFeaturePlanId) {
      if (request.method === "GET") {
        requirePermission(admin, "commerce.read");
        return json({
          planId: planFeaturePlanId,
          items: await planFeatureStore.list(planFeaturePlanId),
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        }, 200, origin);
      }
      if (request.method !== "PUT") return null;
      requirePermission(admin, "commerce.plan_feature.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseConfigureCommercePlanFeaturePayload(request);
      const result = await planFeatureStore.configure({
        actorAccountId: accountId,
        planId: planFeaturePlanId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashConfigureCommercePlanFeatureRequest(planFeaturePlanId, payload),
      });
      const httpStatus = checkedStatus(result, "commerce_plan_feature");
      if (httpStatus >= 400) {
        throw new ApiError(
          httpStatus,
          String(result.code),
          typeof result.message === "string"
            ? result.message
            : "Plan feature update was not completed.",
        );
      }
      return json({
        planId: String(result.planId),
        featureId: String(result.featureId),
        assigned: Boolean(result.assigned),
        version: Number(result.version),
        replayed: Boolean(result.replayed),
      }, httpStatus, origin);
    }

    const planId = matchCommerceTrialPolicyPath(path);
    if (!planId) return null;
    if (request.method === "GET") {
      requirePermission(admin, "commerce.read");
      const policy = await trialStore.get(planId);
      return json({
        policy,
        freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
      }, 200, origin);
    }
    if (request.method !== "PUT") return null;
    requirePermission(admin, "commerce.trial.write");
    const idempotencyKey = requireIdempotencyKey(request);
    const payload = await parseConfigureCommerceTrialPayload(request);
    const result = await trialStore.configure({
      actorAccountId: accountId,
      planId,
      payload,
      correlationId,
      idempotencyKey,
      requestHash: await hashConfigureCommerceTrialRequest(planId, payload),
    });
    const httpStatus = checkedStatus(result, "commerce_trial");
    if (httpStatus >= 400) {
      throw new ApiError(
        httpStatus,
        String(result.code),
        typeof result.message === "string" ? result.message : "Trial policy update was not completed.",
      );
    }
    return json({
      planId: String(result.planId),
      durationDays: Number(result.durationDays),
      eligibilityRule: String(result.eligibilityRule),
      status: String(result.status),
      version: Number(result.version),
      replayed: Boolean(result.replayed),
    }, httpStatus, origin);
  };
}
