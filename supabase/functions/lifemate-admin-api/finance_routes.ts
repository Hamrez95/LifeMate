import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { parseFinanceProfitLossQuery } from "./finance.ts";
import { parseFinanceBudgetQuery } from "./finance_budget.ts";
import { createFinanceBudgetStore } from "./finance_budget_service.ts";
import { parseFinanceCashPlanningQuery } from "./finance_cash.ts";
import { createFinanceCashPlanningStore } from "./finance_cash_service.ts";
import { createFinanceProfitLossStore } from "./finance_service.ts";
import { json } from "./http.ts";

export type FinanceRouteContext = {
  request: Request;
  path: string;
  admin: AdminCapabilitySnapshot;
  origin: string | null;
};

type FinanceProfitLossStore = ReturnType<typeof createFinanceProfitLossStore>;
type FinanceBudgetStore = ReturnType<typeof createFinanceBudgetStore>;
type FinanceCashPlanningStore = ReturnType<
  typeof createFinanceCashPlanningStore
>;

export function createFinanceRouteHandler(
  databaseUrl: string,
  store: FinanceProfitLossStore = createFinanceProfitLossStore(databaseUrl),
  budgetStore?: FinanceBudgetStore,
  cashPlanningStore?: FinanceCashPlanningStore,
) {
  let resolvedBudgetStore = budgetStore;
  let resolvedCashPlanningStore = cashPlanningStore;

  return async function handleFinanceRoute(
    context: FinanceRouteContext,
  ): Promise<Response | null> {
    const { request, path, admin, origin } = context;
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
