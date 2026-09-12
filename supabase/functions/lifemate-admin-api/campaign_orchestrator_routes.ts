import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  matchCampaignExecutionAction,
  parseCancelExecution,
  parseExecutionTransition,
  parsePrepareCampaignExecution,
  parseScheduleExecution,
} from "./campaign_orchestrator.ts";
import { createCampaignOrchestratorStore } from "./campaign_orchestrator_service.ts";
import { json } from "./http.ts";
import { createProductLearningRouteHandler } from "./product_learning_routes.ts";
import { ApiError } from "./validation.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function readBody(request: Request): Promise<Record<string, unknown>> {
  let parsed: unknown;
  try {
    parsed = await request.json();
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON.");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new ApiError(
      400,
      "invalid_json",
      "Request body must be a JSON object.",
    );
  }
  return parsed as Record<string, unknown>;
}

function httpStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  return Number.isInteger(status) && status >= 100 && status <= 599
    ? status
    : 200;
}

function idFromPath(
  path: string,
  pattern: RegExp,
  code: string,
): string | null {
  const match = path.match(pattern);
  if (!match) return null;
  const id = match[1].toLowerCase();
  if (!UUID.test(id)) throw new ApiError(400, code, "Identifier is invalid.");
  return id;
}

export function createCampaignOrchestratorRouteHandler(databaseUrl: string) {
  const store = createCampaignOrchestratorStore(databaseUrl);
  const productLearningRouteHandler = createProductLearningRouteHandler(
    databaseUrl,
  );

  return async function campaignOrchestratorRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    const productLearningResponse = await productLearningRouteHandler(input);
    if (productLearningResponse) return productLearningResponse;

    const campaignId = idFromPath(
      path,
      /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/executions$/,
      "campaign_id_invalid",
    );
    if (request.method === "GET" && campaignId) {
      requirePermission(admin, "marketing.campaign.send");
      const items = await store.listExecutions(campaignId);
      return json(
        {
          items,
          total: items.length,
          privacy: {
            recipientIdentifiersExposed: false,
            messageBodiesExposed: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const executionId = idFromPath(
      path,
      /^\/api\/v1\/marketing\/campaign-executions\/([^/]+)$/,
      "campaign_execution_id_invalid",
    );
    if (request.method === "GET" && executionId) {
      requirePermission(admin, "marketing.campaign.send");
      const execution = await store.getExecution(executionId);
      if (!execution) {
        throw new ApiError(
          404,
          "campaign_execution_not_found",
          "Campaign execution was not found.",
        );
      }
      return json(
        {
          execution,
          privacy: {
            recipientIdentifiersExposed: false,
            messageBodiesExposed: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/marketing/campaign-executions/prepare"
    ) {
      requirePermission(admin, "marketing.campaign.send");
      const payload = parsePrepareCampaignExecution(await readBody(request));
      const result = await store.prepare({
        actorAccountId: accountId,
        ...payload,
        correlationId,
      });
      return json(result, httpStatus(result), origin);
    }

    const action = matchCampaignExecutionAction(path);
    if (!action || request.method !== "POST") return null;
    requirePermission(admin, "marketing.campaign.send");
    const body = await readBody(request);

    if (action.action === "confirm") {
      const payload = parseExecutionTransition(action.executionId, body);
      const result = await store.confirm({
        actorAccountId: accountId,
        ...payload,
        correlationId,
      });
      return json(result, httpStatus(result), origin);
    }
    if (action.action === "schedule") {
      const payload = parseScheduleExecution(action.executionId, body);
      const result = await store.schedule({
        actorAccountId: accountId,
        ...payload,
        correlationId,
      });
      return json(result, httpStatus(result), origin);
    }
    const payload = parseCancelExecution(action.executionId, body);
    const result = await store.cancel({
      actorAccountId: accountId,
      ...payload,
      correlationId,
    });
    return json(result, httpStatus(result), origin);
  };
}
