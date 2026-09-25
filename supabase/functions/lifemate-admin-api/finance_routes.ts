import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { parseFinanceProfitLossQuery } from "./finance.ts";
import { parseFinanceBudgetQuery } from "./finance_budget.ts";
import { createFinanceBudgetStore } from "./finance_budget_service.ts";
import { parseFinanceCashPlanningQuery } from "./finance_cash.ts";
import { createFinanceCashPlanningStore } from "./finance_cash_service.ts";
import {
  hashFinanceScenarioRequest,
  parseConfigureFinanceScenarioPayload,
} from "./finance_scenarios.ts";
import { createFinanceScenarioStore } from "./finance_scenarios_service.ts";
import { createFinanceProfitLossStore } from "./finance_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

export type FinanceRouteContext = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

type FinanceProfitLossStore = ReturnType<typeof createFinanceProfitLossStore>;
type FinanceBudgetStore = ReturnType<typeof createFinanceBudgetStore>;
type FinanceCashPlanningStore = ReturnType<
  typeof createFinanceCashPlanningStore
>;
type FinanceScenarioStore = ReturnType<typeof createFinanceScenarioStore>;

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "finance_scenario_workflow_unavailable",
      "Finance scenario workflow returned an invalid status.",
    );
  }
  return status;
}

function scenarioIdFromPath(path: string): string | null | undefined {
  if (path === "/api/v1/finance/scenarios") return null;
  const match =
    /^\/api\/v1\/finance\/scenarios\/([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i
      .exec(path);
  return match?.[1];
}

export function createFinanceRouteHandler(
  databaseUrl: string,
  store: FinanceProfitLossStore = createFinanceProfitLossStore(databaseUrl),
  budgetStore?: FinanceBudgetStore,
  cashPlanningStore?: FinanceCashPlanningStore,
  scenarioStore?: FinanceScenarioStore,
) {
  let resolvedBudgetStore = budgetStore;
  let resolvedCashPlanningStore = cashPlanningStore;
  let resolvedScenarioStore = scenarioStore;

  return async function handleFinanceRoute(
    context: FinanceRouteContext,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/finance/scenarios") {
      requirePermission(admin, "finance.read");
      resolvedScenarioStore ??= createFinanceScenarioStore(databaseUrl);
      return json(
        {
          items: await resolvedScenarioStore.list(),
          semantics: {
            actualSource: "canonical_read_models_only",
            scenarioClassifications: ["BUDGET", "FORECAST"],
            scenarioKinds: ["BASE", "UPSIDE", "DOWNSIDE"],
            implicitFx: false,
            amountRepresentation: "integer_minor_units",
          },
          generatedAtUtc: new Date().toISOString(),
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" || request.method === "PUT") {
      const scenarioId = scenarioIdFromPath(path);
      if (scenarioId !== undefined) {
        if (request.method === "POST" && scenarioId !== null) return null;
        if (request.method === "PUT" && scenarioId === null) return null;
        requirePermission(admin, "finance.scenario.write");
        resolvedScenarioStore ??= createFinanceScenarioStore(databaseUrl);
        const payload = await parseConfigureFinanceScenarioPayload(request);
        if (request.method === "POST" && payload.expectedVersion !== null) {
          throw new ApiError(
            400,
            "finance_scenario_version_invalid",
            "New scenarios must not provide an expected version.",
          );
        }
        if (request.method === "PUT" && payload.expectedVersion === null) {
          throw new ApiError(
            400,
            "finance_scenario_version_required",
            "Existing scenarios require an expected version.",
          );
        }
        const idempotencyKey = requireIdempotencyKey(request);
        const result = await resolvedScenarioStore.configure({
          actorAccountId: accountId,
          scenarioId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashFinanceScenarioRequest(payload),
        });
        const status = mutationStatus(result);
        if (status >= 400) {
          throw new ApiError(
            status,
            String(result.code),
            typeof result.message === "string"
              ? result.message
              : "Finance scenario update was not completed.",
          );
        }
        return json(
          {
            scenarioId: String(result.scenarioId),
            version: Number(result.version),
            updatedAtUtc: String(result.updatedAtUtc),
            replayed: Boolean(result.replayed),
          },
          status,
          origin,
        );
      }
    }

    if (request.method !== "GET") return null;

    if (path === "/api/v1/finance/profit-loss") {
      requirePermission(admin, "finance.read");
      const query = parseFinanceProfitLossQuery(new URL(request.url));
      const report = await store.getProfitLoss(query);
      return json(
        {
          ...report,
          generatedAtUtc: new Date().toISOString(),
        },
        200,
        origin,
      );
    }

    if (path === "/api/v1/finance/budget-vs-actual") {
      requirePermission(admin, "finance.read");
      const query = parseFinanceBudgetQuery(new URL(request.url));
      resolvedBudgetStore ??= createFinanceBudgetStore(databaseUrl);
      const report = await resolvedBudgetStore.getBudgetVsActual(query);
      return json(
        {
          ...report,
          generatedAtUtc: new Date().toISOString(),
        },
        200,
        origin,
      );
    }

    if (path === "/api/v1/finance/cash-planning") {
      requirePermission(admin, "finance.read");
      const query = parseFinanceCashPlanningQuery(new URL(request.url));
      resolvedCashPlanningStore ??= createFinanceCashPlanningStore(databaseUrl);
      const report = await resolvedCashPlanningStore.getCashPlanning(query);
      return json(
        {
          ...report,
          generatedAtUtc: new Date().toISOString(),
        },
        200,
        origin,
      );
    }

    return null;
  };
}
