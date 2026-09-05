import { assertEquals, assertThrows } from "jsr:@std/assert";
import {
  parseGrowthAnalyticsQuery,
  previousPeriod,
} from "./growth_analytics.ts";

Deno.test("growth analytics accepts canonical windows and product filter", () => {
  const query = parseGrowthAnalyticsQuery(
    new URL(
      "https://example.test/api/v1/analytics/growth?from=2026-08-01&to=2026-08-31&window=monthly&product=wellmate",
    ),
  );
  assertEquals(query, {
    from: "2026-08-01",
    to: "2026-08-31",
    window: "monthly",
    product: "wellmate",
  });
});

Deno.test("growth analytics rejects invalid calendar ranges", () => {
  assertThrows(() =>
    parseGrowthAnalyticsQuery(
      new URL(
        "https://example.test/api/v1/analytics/growth?from=2026-02-30&to=2026-03-01",
      ),
    )
  );
  assertThrows(() =>
    parseGrowthAnalyticsQuery(
      new URL(
        "https://example.test/api/v1/analytics/growth?from=2026-08-02&to=2026-08-01",
      ),
    )
  );
});

Deno.test("growth previous period has equal inclusive duration", () => {
  assertEquals(
    previousPeriod({
      from: "2026-08-01",
      to: "2026-08-07",
      window: "weekly",
      product: null,
    }),
    { from: "2026-07-25", to: "2026-07-31" },
  );
});
