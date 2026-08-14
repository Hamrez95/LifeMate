import { assertEquals, assertThrows } from "jsr:@std/assert";

import { parseAnalyticsKpiQuery } from "./analytics_kpis.ts";
import { ApiError } from "./validation.ts";

const NOW = new Date("2026-08-14T06:00:00.000Z");

Deno.test("analytics KPI query defaults to a bounded trailing 30-day Tehran range", () => {
  const result = parseAnalyticsKpiQuery(
    new URL("https://admin.example/api/v1/analytics/kpis"),
    NOW,
  );
  assertEquals(result, {
    from: "2026-07-16",
    to: "2026-08-14",
    product: null,
  });
});

Deno.test("analytics KPI query accepts explicit bounded filters", () => {
  const result = parseAnalyticsKpiQuery(
    new URL(
      "https://admin.example/api/v1/analytics/kpis?from=2026-08-01&to=2026-08-14&product=wellmate",
    ),
    NOW,
  );
  assertEquals(result, {
    from: "2026-08-01",
    to: "2026-08-14",
    product: "wellmate",
  });
});

Deno.test("analytics KPI query rejects inverted or oversized ranges", () => {
  assertThrows(
    () =>
      parseAnalyticsKpiQuery(
        new URL(
          "https://admin.example/api/v1/analytics/kpis?from=2026-08-15&to=2026-08-14",
        ),
        NOW,
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseAnalyticsKpiQuery(
        new URL(
          "https://admin.example/api/v1/analytics/kpis?from=2025-01-01&to=2026-08-14",
        ),
        NOW,
      ),
    ApiError,
  );
});

Deno.test("analytics KPI query rejects unknown products and malformed dates", () => {
  assertThrows(
    () =>
      parseAnalyticsKpiQuery(
        new URL(
          "https://admin.example/api/v1/analytics/kpis?product=unknown-product",
        ),
        NOW,
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseAnalyticsKpiQuery(
        new URL("https://admin.example/api/v1/analytics/kpis?from=2026-02-31"),
        NOW,
      ),
    ApiError,
  );
});
