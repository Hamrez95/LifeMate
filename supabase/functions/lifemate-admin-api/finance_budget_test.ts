import { assertEquals, assertRejects } from "jsr:@std/assert";

import {
  financeBudgetMonthCount,
  parseFinanceBudgetQuery,
  summarizeBudgetVsActual,
  varianceBasisPoints,
  varianceFavorability,
} from "./finance_budget.ts";
import { createFinanceRouteHandler } from "./finance_routes.ts";

Deno.test("finance budget comparison defaults to the last completed Tehran calendar month", () => {
  const query = parseFinanceBudgetQuery(
    new URL("https://admin.test/api/v1/finance/budget-vs-actual"),
    new Date("2026-08-16T21:30:00.000Z"),
  );
  assertEquals(query, { from: "2026-07-01", to: "2026-07-31", currency: null });
  assertEquals(financeBudgetMonthCount(query), 1);
});

Deno.test("finance budget comparison requires complete completed calendar months", async () => {
  const query = parseFinanceBudgetQuery(
    new URL(
      "https://admin.test/api/v1/finance/budget-vs-actual?from=2026-06-01&to=2026-07-31&currency=IRR",
    ),
    new Date("2026-08-17T09:00:00.000Z"),
  );
  assertEquals(query, {
    from: "2026-06-01",
    to: "2026-07-31",
    currency: "IRR",
  });
  assertEquals(financeBudgetMonthCount(query), 2);

  await assertRejects(
    async () =>
      parseFinanceBudgetQuery(
        new URL(
          "https://admin.test/api/v1/finance/budget-vs-actual?from=2026-07-02&to=2026-07-31",
        ),
        new Date("2026-08-17T09:00:00.000Z"),
      ),
    Error,
    "complete calendar months",
  );

  await assertRejects(
    async () =>
      parseFinanceBudgetQuery(
        new URL(
          "https://admin.test/api/v1/finance/budget-vs-actual?from=2026-08-01&to=2026-08-31",
        ),
        new Date("2026-08-17T09:00:00.000Z"),
      ),
    Error,
    "completed calendar months",
  );
});

Deno.test("finance budget comparison rolls the default completed month across year boundary", () => {
  const query = parseFinanceBudgetQuery(
    new URL("https://admin.test/api/v1/finance/budget-vs-actual"),
    new Date("2027-01-15T09:00:00.000Z"),
  );
  assertEquals(query, { from: "2026-12-01", to: "2026-12-31", currency: null });
});

Deno.test("finance budget variance keeps expense favorability direction explicit", () => {
  assertEquals(varianceFavorability("Revenue", 120n, 100n), "favorable");
  assertEquals(varianceFavorability("Expense", 80n, 100n), "favorable");
  assertEquals(varianceFavorability("Expense", 120n, 100n), "unfavorable");
  assertEquals(varianceFavorability("Net", 120n, 100n), "favorable");
  assertEquals(varianceBasisPoints(125n, 100n), "2500");
  assertEquals(varianceBasisPoints(25n, 0n), null);
  assertEquals(varianceBasisPoints(-50n, -100n), null);
});

Deno.test("finance budget comparison preserves missing budget as unavailable rather than fake zero", () => {
  const result = summarizeBudgetVsActual([
    {
      kind: "Revenue",
      code: "subscription",
      label: "Subscription",
      budgetMinor: 1_000n,
      actualMinor: 1_250n,
    },
    {
      kind: "Expense",
      code: "payroll",
      label: "Payroll",
      budgetMinor: 800n,
      actualMinor: 750n,
    },
    {
      kind: "Expense",
      code: "incident:response",
      label: "Incident response",
      budgetMinor: null,
      actualMinor: 50n,
    },
  ]);

  assertEquals(result.totals.revenue.varianceMinor, 250n);
  assertEquals(result.totals.revenue.favorability, "favorable");
  assertEquals(result.totals.expense.varianceMinor, 0n);
  assertEquals(result.categories[1].favorability, "favorable");
  assertEquals(result.categories[2].code, "incident:response");
  assertEquals(result.categories[2].budgetMinor, null);
  assertEquals(result.categories[2].varianceMinor, null);
  assertEquals(result.categories[2].varianceBasisPoints, null);
});

Deno.test("finance budget route denies admins without finance.read before querying budget data", async () => {
  let queried = false;
  const handler = createFinanceRouteHandler(
    "unused",
    {
      async getProfitLoss() {
        throw new Error("P&L store must not be queried");
      },
    },
    {
      async getBudgetVsActual() {
        queried = true;
        throw new Error("budget store must not be queried");
      },
    },
  );

  await assertRejects(
    async () =>
      await handler({
        request: new Request(
          "https://admin.test/api/v1/finance/budget-vs-actual?from=2026-08-01&to=2026-08-31",
        ),
        path: "/api/v1/finance/budget-vs-actual",
        accountId: crypto.randomUUID(),
        admin: { accountId: crypto.randomUUID(), roles: [], permissions: [] },
        correlationId: crypto.randomUUID(),
        origin: null,
      }),
    Error,
    "Administrative permission is required",
  );
  assertEquals(queried, false);
});
