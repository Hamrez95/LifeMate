import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { assertExperimentMetrics, parseExperimentKey } from "./experiments.ts";
import {
  hashExperimentMutation,
  parseCreateExperimentPayload,
  parseExperimentStatusPayload,
} from "./experiments_payload.ts";
import { createExperimentStore } from "./experiments_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "experiment_workflow_unavailable",
      "Experiment workflow returned an invalid status.",
    );
  }
  return status;
}

function mutationError(result: Record<string, unknown>): never {
  throw new ApiError(
    mutationStatus(result),
    typeof result.code === "string"
      ? result.code
      : "experiment_workflow_unavailable",
    typeof result.message === "string"
      ? result.message
      : "Experiment workflow was not completed.",
  );
}

export function createExperimentRouteHandler(databaseUrl: string) {
  const store = createExperimentStore(databaseUrl);
  return async function experimentRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;

    if (request.method === "GET" && path === "/api/v1/experiments") {
      requirePermission(admin, "experiments.read");
      const items = await store.list();
      return json(
        {
          items,
          total: items.length,
          outcomesComputed: false,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" && path === "/api/v1/experiments") {
      requirePermission(admin, "experiments.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseCreateExperimentPayload(request);
      const requestHash = await hashExperimentMutation(payload);
      const result = await store.create({
        actorAccountId: accountId,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) mutationError(result);
      return json(result, status, origin);
    }

    const statusMatch = path.match(/^\/api\/v1\/experiments\/([^/]+)\/status$/);
    if (request.method === "POST" && statusMatch) {
      requirePermission(admin, "experiments.write");
      const experimentKey = parseExperimentKey(
        decodeURIComponent(statusMatch[1]),
      );
      const current = await store.get(experimentKey);
      if (!current) {
        throw new ApiError(
          404,
          "experiment_not_found",
          "Experiment was not found.",
        );
      }
      const payload = await parseExperimentStatusPayload(request);
      if (payload.status === "Scheduled" || payload.status === "Running") {
        assertExperimentMetrics(
          current.primaryMetricCode,
          current.guardrailMetricCodes,
          { requireMeasurable: true },
        );
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await hashExperimentMutation({
        experimentKey,
        ...payload,
      });
      const result = await store.setStatus({
        actorAccountId: accountId,
        experimentKey,
        payload,
        correlationId,
        idempotencyKey,
        requestHash,
      });
      const status = mutationStatus(result);
      if (status >= 400) mutationError(result);
      return json(result, status, origin);
    }

    const detailMatch = path.match(/^\/api\/v1\/experiments\/([^/]+)$/);
    if (request.method === "GET" && detailMatch) {
      requirePermission(admin, "experiments.read");
      const experimentKey = parseExperimentKey(
        decodeURIComponent(detailMatch[1]),
      );
      const item = await store.get(experimentKey);
      if (!item) {
        throw new ApiError(
          404,
          "experiment_not_found",
          "Experiment was not found.",
        );
      }
      return json(
        {
          item,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
