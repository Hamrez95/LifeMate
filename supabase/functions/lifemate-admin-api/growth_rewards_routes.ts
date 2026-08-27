import { type AdminCapabilitySnapshot, requirePermission } from "./authorization.ts";
import {
  hashGrowthRewardRequest,
  matchAdvocacyReviewPath,
  parseAdvocacyReview,
  parseRewardIssueExecute,
  parseRewardIssueRequest,
  parseRewardRuleUpsert,
} from "./growth_rewards.ts";
import { createGrowthRewardAdminStore } from "./growth_rewards_service.ts";
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

function resultStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(503, "growth_reward_workflow_unavailable", "Growth reward workflow returned an invalid status.");
  }
  if (status >= 400) {
    throw new ApiError(status, String(result.code), typeof result.message === "string" ? result.message : "Growth reward operation was not completed.");
  }
  return status;
}

function listLimit(request: Request): number {
  const raw = new URL(request.url).searchParams.get("limit");
  const limit = raw === null ? 50 : Number(raw);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new ApiError(400, "growth_reward_limit_invalid", "limit must be between 1 and 100.");
  return limit;
}

export function createGrowthRewardAdminRouteHandler(databaseUrl: string) {
  const store = createGrowthRewardAdminStore(databaseUrl);

  return async function growthRewardAdminRouteHandler(context: Context): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/commerce/rewards/rules") {
      requirePermission(admin, "growth.rewards.read");
      const limit = listLimit(request);
      return json({ items: await store.listRules(limit), limit }, 200, origin);
    }
    if (request.method === "GET" && path === "/api/v1/commerce/rewards/events") {
      requirePermission(admin, "growth.rewards.read");
      const limit = listLimit(request);
      return json({ items: await store.listEvents(limit), limit }, 200, origin);
    }
    if (request.method === "POST" && path === "/api/v1/commerce/rewards/rules") {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardRuleUpsert(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.upsertRule({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardRequest(payload),
      });
      return json(result, resultStatus(result), origin);
    }

    const advocacyId = matchAdvocacyReviewPath(path);
    if (request.method === "POST" && advocacyId) {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseAdvocacyReview(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.reviewAdvocacy({
        actorAccountId: accountId,
        submissionId: advocacyId,
        ...payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardRequest({ submissionId: advocacyId, ...payload }),
      });
      return json(result, resultStatus(result), origin);
    }

    if (request.method === "POST" && path === "/api/v1/commerce/rewards/issuance-requests") {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardIssueRequest(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.requestIssue({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardRequest(payload),
      });
      return json(result, resultStatus(result), origin);
    }

    if (request.method === "POST" && path === "/api/v1/commerce/rewards/issue") {
      requirePermission(admin, "growth.rewards.write");
      const payload = await parseRewardIssueExecute(request);
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.executeIssue({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash: await hashGrowthRewardRequest(payload),
      });
      return json(result, resultStatus(result), origin);
    }

    return null;
  };
}
