import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  hashGrowthRewardAdminRequest,
  matchRewardSourceReviewPath,
  parseRewardEventCreate,
  parseRewardFulfillmentExecute,
  parseRewardFulfillmentRequest,
  parseRewardRuleMutation,
  parseRewardSourceReview,
} from "./growth_reward_admin.ts";
import { createGrowthRewardAdminStore } from "./growth_reward_admin_service.ts";
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
      "growth_reward_workflow_unavailable",
      "Growth reward workflow returned an invalid status.",
    );
  }
  if (value >= 400) {
    throw new ApiError(
      value,
      String(result.code),
      typeof result.message === "string"
        ? result.message
        : "Growth reward operation was not completed.",
    );
  }
  return value;
}

function limit(request: Request): number {
  const raw = new URL(request.url).searchParams.get("limit");
  const value = raw == null ? 50 : Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 100) {
    throw new ApiError(
      400,
      "growth_reward_limit_invalid",
      "limit must be between 1 and 100.",
    );
  }
  return value;
}

export function createGrowthRewardAdminRouteHandler(databaseUrl: string) {
  const store = createGrowthRewardAdminStore(databaseUrl);
  return async function handle(context: Context): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/commerce/rewards/rules") {
      requirePermission(admin, "growth.rewards.read");
      const pageLimit = limit(request);
      return json(
        { items: await store.listRules(pageLimit), limit: pageLimit },
        200,
        origin,
      );
    }
    if (
      request.method === "GET" && path === "/api/v1/commerce/rewards/events"
    ) {
      requirePermission(admin, "growth.rewards.read");
      const pageLimit = limit(request);
      return json(
        { items: await store.listEvents(pageLimit), limit: pageLimit },
        200,
        origin,
      );
    }
    if (
      request.method === "GET" &&
      (path === "/api/v1/commerce/rewards/sources/Referral" ||
        path === "/api/v1/commerce/rewards/sources/Advocacy")
    ) {
      requirePermission(admin, "growth.rewards.read");
      const sourceKind = path.endsWith("Referral") ? "Referral" : "Advocacy";
      const pageLimit = limit(request);
      return json(
        {
          items: await store.listSources(sourceKind, pageLimit),
          limit: pageLimit,
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" && path === "/api/v1/commerce/rewards/rules"
    ) {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardRuleMutation(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.upsertRule({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardAdminRequest(payload),
      });
      return json(result, status(result), origin);
    }
    if (
      request.method === "POST" && path === "/api/v1/commerce/rewards/events"
    ) {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardEventCreate(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.createEvent({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardAdminRequest(payload),
      });
      return json(result, status(result), origin);
    }

    const source = matchRewardSourceReviewPath(path);
    if (request.method === "POST" && source) {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardSourceReview(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const requestPayload = { ...source, ...payload };
      const result = await store.reviewSource({
        actorAccountId: accountId,
        ...requestPayload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardAdminRequest(requestPayload),
      });
      return json(result, status(result), origin);
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/commerce/rewards/fulfillment-requests"
    ) {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardFulfillmentRequest(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.requestFulfillment({
        actorAccountId: accountId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardAdminRequest(payload),
      });
      return json(result, status(result), origin);
    }
    if (
      request.method === "POST" && path === "/api/v1/commerce/rewards/fulfill"
    ) {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardFulfillmentExecute(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.executeFulfillment({
        actorAccountId: accountId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardAdminRequest(payload),
      });
      return json(result, status(result), origin);
    }

    return null;
  };
}
