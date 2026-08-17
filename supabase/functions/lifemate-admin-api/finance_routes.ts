import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { parseFinanceProfitLossQuery } from "./finance.ts";
import { createFinanceProfitLossStore } from "./finance_service.ts";
import { json } from "./http.ts";

export type FinanceRouteContext = {
  request: Request;
  path: string;
  admin: AdminCapabilitySnapshot;
  origin: string | null;
};

type FinanceProfitLossStore = ReturnType<typeof createFinanceProfitLossStore>;

export function createFinanceRouteHandler(
  databaseUrl: string,
  store: FinanceProfitLossStore = createFinanceProfitLossStore(databaseUrl),
) {
  return async function handleFinanceRoute(
    context: FinanceRouteContext,
  ): Promise<Response | null> {
    const { request, path, admin, origin } = context;
    if (request.method !== "GET" || path !== "/api/v1/finance/profit-loss") {
      return null;
    }

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
  };
}
