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
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export function createCommerceTrialRouteHandler(databaseUrl: string) {
  const store = createCommerceTrialStore(databaseUrl);
  return async function commerceTrialRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;
    const planId = matchCommerceTrialPolicyPath(path);
    if (!planId) return null;

    if (request.method === "GET") {
      requirePermission(admin, "commerce.read");
      const policy = await store.get(planId);
      return json(
        {
          policy,
          freshness: {
            status: "fresh",
            asOfUtc: new Date().toISOString(),
          },
        },
        200,
        origin,
      );
    }

    if (request.method !== "PUT") return null;

    requirePermission(admin, "commerce.trial.write");
    const idempotencyKey = requireIdempotencyKey(request);
    const payload = await parseConfigureCommerceTrialPayload(request);
    const result = await store.configure({
      actorAccountId: accountId,
      planId,
      payload,
      correlationId,
      idempotencyKey,
      requestHash: await hashConfigureCommerceTrialRequest(planId, payload),
    });
    const httpStatus = Number(result.httpStatus);
    if (!Number.isInteger(httpStatus) || httpStatus < 100 || httpStatus > 599) {
      throw new ApiError(
        503,
        "commerce_trial_workflow_unavailable",
        "Trial workflow returned an invalid status.",
      );
    }
    if (httpStatus >= 400) {
      throw new ApiError(
        httpStatus,
        String(result.code),
        typeof result.message === "string"
          ? result.message
          : "Trial policy update was not completed.",
      );
    }
    return json(
      {
        planId: String(result.planId),
        durationDays: Number(result.durationDays),
        eligibilityRule: String(result.eligibilityRule),
        status: String(result.status),
        version: Number(result.version),
        replayed: Boolean(result.replayed),
      },
      httpStatus,
      origin,
    );
  };
}
