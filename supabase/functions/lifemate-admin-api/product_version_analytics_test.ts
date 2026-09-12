import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  matchAccountProductVersionsPath,
  parseProductVersionAdoptionQuery,
} from "./product_version_analytics.ts";
import {
  mapAccountVersion,
  mapAdoption,
} from "./product_version_analytics_service.ts";
import { ApiError } from "./validation.ts";

Deno.test("product version adoption filters normalize safely", () => {
  assertEquals(
    parseProductVersionAdoptionQuery(
      new URL(
        "https://example.test/api/v1/analytics/product-version-adoption?product=WellMate&platform=Android",
      ),
    ),
    { product: "wellmate", platform: "android" },
  );

  const error = assertThrows(() =>
    parseProductVersionAdoptionQuery(
      new URL(
        "https://example.test/api/v1/analytics/product-version-adoption?platform=device-fingerprint",
      ),
    )
  );
  assertEquals(error instanceof ApiError, true);
  assertEquals((error as ApiError).code, "platform_invalid");
});

Deno.test("User 360 product-version route requires canonical account uuid", () => {
  assertEquals(
    matchAccountProductVersionsPath(
      "/api/v1/analytics/accounts/018f5e6a-7e91-4c26-8e18-a83c5531d111/product-versions",
    ),
    "018f5e6a-7e91-4c26-8e18-a83c5531d111",
  );
  assertEquals(
    matchAccountProductVersionsPath(
      "/api/v1/analytics/accounts/not-an-account/product-versions",
    ),
    null,
  );
});

Deno.test("read-model mapping exposes definition-safe version metadata only", () => {
  assertEquals(
    mapAdoption({
      product: "wellmate",
      platform: "android",
      app_version: "1.2.3",
      build_number: "42",
      account_count: 7,
      first_seen_at_utc: "2026-08-20T10:00:00Z",
      last_seen_at_utc: "2026-08-27T10:00:00Z",
      freshness_at_utc: "2026-08-27T10:01:00Z",
    }),
    {
      product: "wellmate",
      platform: "android",
      appVersion: "1.2.3",
      buildNumber: "42",
      accountCount: 7,
      firstSeenAtUtc: "2026-08-20T10:00:00.000Z",
      lastSeenAtUtc: "2026-08-27T10:00:00.000Z",
      freshnessAtUtc: "2026-08-27T10:01:00.000Z",
      source: "analytics.product_version_adoption_v1",
    },
  );

  const user = mapAccountVersion({
    account_id: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
    product: "caremate",
    platform: "android",
    app_version: "1.1.0",
    build_number: "31",
    rollout_cohort: "beta-a",
    first_seen_at_utc: "2026-08-22T10:00:00Z",
    last_seen_at_utc: "2026-08-27T11:00:00Z",
  });
  assertEquals(user.rolloutCohort, "beta-a");
  assertEquals(Object.hasOwn(user, "deviceId"), false);
  assertEquals(Object.hasOwn(user, "healthData"), false);
});

Deno.test("update policy history stays read-only, permission-scoped, and bounded", async () => {
  const routes = await Deno.readTextFile(
    new URL("./product_version_analytics_routes.ts", import.meta.url),
  );
  const service = await Deno.readTextFile(
    new URL("./product_version_analytics_service.ts", import.meta.url),
  );

  assertEquals(
    routes.includes(
      'path === "/api/v1/platform/product-update-policies/history"',
    ),
    true,
  );
  assertEquals(
    routes.includes(
      'requirePermission(admin, "analytics.product_versions.read")',
    ),
    true,
  );
  assertEquals(
    routes.includes('source: "platform.product_update_policy_history"'),
    true,
  );
  assertEquals(
    service.includes("from platform.product_update_policy_history"),
    true,
  );
  assertEquals(service.includes("limit 250"), true);
  assertEquals(service.includes("updated_by_account_id"), false);
});
