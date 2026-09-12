import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";

import {
  parseFinanceCashPlanningQuery,
  projectScenario,
  runwayMonthsBasisPoints,
  summarizeBurn,
} from "./finance_cash.ts";
import { createFinanceRouteHandler } from "./finance_routes.ts";

Deno.test("cash planning defaults to completed actual months and bounded forecast horizon", () => {
  const query = parseFinanceCashPlanningQuery(
    new URL("https://admin.test/api/v1/finance/cash-planning"),
    new Date("2026-08-17T09:00:00.000Z"),
  );
  assertEquals(query, {
    from: "2026-07-01",
    to: "2026-07-31",
    currency: null,
    horizonMonths: 6,
  });

  assertThrows(
    () =>
      parseFinanceCashPlanningQuery(
        new URL(
          "https://admin.test/api/v1/finance/cash-planning?horizonMonths=19",
        ),
        new Date("2026-08-17T09:00:00.000Z"),
      ),
    Error,
    "between 1 and 18 months",
  );
});

Deno.test("cash planning burn math keeps gross and net burn explicit", () => {
  const summary = summarizeBurn([
    { month: "2026-06", revenueMinor: 100n, expenseMinor: 300n },
    { month: "2026-07", revenueMinor: 50n, expenseMinor: 250n },
  ]);

  assertEquals(summary?.grossBurnMinor, 550n);
  assertEquals(summary?.netBurnMinor, 400n);
  assertEquals(summary?.averageGrossBurnMinor, 275n);
  assertEquals(summary?.averageNetBurnMinor, 200n);
  assertEquals(summary?.series[0].netBurnMinor, 200n);
  assertEquals(runwayMonthsBasisPoints(1_000n, 200n), "50000");
  assertEquals(runwayMonthsBasisPoints(1_000n, 0n), null);
  assertEquals(runwayMonthsBasisPoints(1_000n, -10n), null);
});

Deno.test("cash planning scenarios are isolated and depletion is bounded to supplied forecast months", () => {
  const base = projectScenario(1_000n, [
    { month: "2026-08", revenueMinor: 100n, expenseMinor: 400n },
    { month: "2026-09", revenueMinor: 100n, expenseMinor: 400n },
  ]);
  const downside = projectScenario(1_000n, [
    { month: "2026-08", revenueMinor: 0n, expenseMinor: 700n },
    { month: "2026-09", revenueMinor: 0n, expenseMinor: 700n },
  ]);

  assertEquals(base.endingCashMinor, 400n);
  assertEquals(base.depletionMonth, null);
  assertEquals(downside.endingCashMinor, -400n);
  assertEquals(downside.depletionMonth, "2026-09");
  assertEquals(base.series[0].projectedEndingCashMinor, 700n);
  assertEquals(downside.series[0].projectedEndingCashMinor, 300n);
});

Deno.test("cash planning rejects negative observed cash input", () => {
  assertThrows(
    () => runwayMonthsBasisPoints(-1n, 100n),
    Error,
    "cash balance cannot be negative",
  );
  assertThrows(
    () => projectScenario(-1n, []),
    Error,
    "cash balance cannot be negative",
  );
});

Deno.test("cash planning route denies admins without finance.read before querying data", async () => {
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
        throw new Error("budget store must not be queried");
      },
    },
    {
      async getCashPlanning() {
        queried = true;
        throw new Error("cash store must not be queried");
      },
    },
  );

  await assertRejects(
    async () =>
      await handler({
        request: new Request(
          "https://admin.test/api/v1/finance/cash-planning?from=2026-07-01&to=2026-07-31&currency=IRR",
        ),
        path: "/api/v1/finance/cash-planning",
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
