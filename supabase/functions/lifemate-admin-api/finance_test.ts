import { assertEquals, assertRejects } from "jsr:@std/assert";

import {
  parseFinanceProfitLossQuery,
  summarizeActualEntries,
} from "./finance.ts";

Deno.test("finance P&L defaults to a bounded Tehran 30-day period", () => {
  const query = parseFinanceProfitLossQuery(
    new URL("https://admin.test/api/v1/finance/profit-loss"),
    new Date("2026-08-16T21:30:00.000Z"),
  );
  assertEquals(query, { from: "2026-07-19", to: "2026-08-17", currency: null });
});

Deno.test("finance P&L rejects invalid ranges and currencies", async () => {
  await assertRejects(
    async () => parseFinanceProfitLossQuery(
      new URL("https://admin.test/api/v1/finance/profit-loss?from=2025-01-01&to=2026-08-17"),
    ),
  );
  await assertRejects(
    async () => parseFinanceProfitLossQuery(
      new URL("https://admin.test/api/v1/finance/profit-loss?currency=toman"),
    ),
  );
});

Deno.test("finance actual math keeps revenue and expense separate and supports negative net result", () => {
  const result = summarizeActualEntries([
    {
      kind: "Revenue",
      categoryCode: "subscription",
      categoryLabel: "Subscription revenue",
      month: "2026-08",
      amountMinor: 1_000n,
    },
    {
      kind: "Expense",
      categoryCode: "payroll",
      categoryLabel: "Payroll",
      month: "2026-08",
      amountMinor: 1_250n,
    },
    {
      kind: "Expense",
      categoryCode: "infrastructure",
      categoryLabel: "Infrastructure",
      month: "2026-08",
      amountMinor: 250n,
    },
  ]);

  assertEquals(result.revenueMinor, 1_000n);
  assertEquals(result.expenseMinor, 1_500n);
  assertEquals(result.netResultMinor, -500n);
  assertEquals(result.categories.length, 3);
  assertEquals(result.series, [{
    month: "2026-08",
    revenueMinor: 1_000n,
    expenseMinor: 1_500n,
    netResultMinor: -500n,
  }]);
});
