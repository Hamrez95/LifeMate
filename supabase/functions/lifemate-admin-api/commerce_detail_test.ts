import { assertEquals, assertThrows } from "jsr:@std/assert";

import {
  matchCommerceEntitlementDetailPath,
  matchCommercePlanDetailPath,
  parseCommerceDetailQuery,
} from "./commerce_detail.ts";
import { ApiError } from "./validation.ts";

Deno.test("commerce plan detail accepts only a UUID path", () => {
  assertEquals(
    matchCommercePlanDetailPath(
      "/api/v1/commerce/plans/550e8400-e29b-41d4-a716-446655440000",
    ),
    "550e8400-e29b-41d4-a716-446655440000",
  );
  assertEquals(matchCommercePlanDetailPath("/api/v1/commerce/plans"), null);
  assertThrows(
    () => matchCommercePlanDetailPath("/api/v1/commerce/plans/not-a-uuid"),
    ApiError,
  );
});

Deno.test("commerce entitlement detail accepts bounded feature codes", () => {
  assertEquals(
    matchCommerceEntitlementDetailPath(
      "/api/v1/commerce/entitlements/wellmate.family_share",
    ),
    "wellmate.family_share",
  );
  assertEquals(
    matchCommerceEntitlementDetailPath("/api/v1/commerce/entitlements"),
    null,
  );
  assertThrows(
    () =>
      matchCommerceEntitlementDetailPath(
        "/api/v1/commerce/entitlements/bad%20feature",
      ),
    ApiError,
  );
});

Deno.test("commerce detail pagination is server bounded", () => {
  assertEquals(
    parseCommerceDetailQuery(new URL("https://admin.example/details")),
    { page: 1, pageSize: 25, offset: 0 },
  );
  assertEquals(
    parseCommerceDetailQuery(
      new URL("https://admin.example/details?page=3&pageSize=50"),
    ),
    { page: 3, pageSize: 50, offset: 100 },
  );
  assertThrows(
    () =>
      parseCommerceDetailQuery(
        new URL("https://admin.example/details?pageSize=500"),
      ),
    ApiError,
  );
});
