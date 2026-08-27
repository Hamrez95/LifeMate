import { type AdminCapabilitySnapshot, requirePermission } from "./authorization.ts";
import {
  matchCampaignExecutionAction,
  parseCancelExecution,
  parseExecutionTransition,
  parsePrepareCampaignExecution,
  parseScheduleExecution,
} from "./campaign_orchestrator.ts";
import { createCampaignOrchestratorStore } from "./campaign_orchestrator_service.ts";
import { createExperimentRouteHandler } from "./experiments_routes.ts";
import { json } from "./http.ts";
import { ApiError } from "./validation.ts";

async function readBody(request: Request): Promise<Record<string, unknown>> {
  let parsed: unknown;
  try {
    parsed = await request.json();
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON.");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new ApiError(400, "invalid_json", "Request body must be a JSON object.");
  }
  return parsed as Record<string, unknown>;
}

function httpStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  return Number.isInteger(status) && status >= 100 && status <= 599 ? status : 200;
}

export function createCampaignOrchestratorRouteHandler(databaseUrl: string) {
  const store = createCampaignOrchestratorStore(databaseUrl);
  const experimentRouteHandler = createExperimentRouteHandler(databaseUrl);

  return async function campaignOrchestratorRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    const experimentResponse = await experimentRouteHandler(input);
    if (experimentResponse) return experimentResponse;

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
