import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import { hasPermission, requirePermission } from "./authorization.ts";
import { ApiError } from "./validation.ts";

const supportSnapshot = {
  accountId: "11111111-1111-4111-8111-111111111111",
  roles: ["support"],
  permissions: ["users.read.basic", "support.read", "support.write"],
};

Deno.test("Support permission snapshot allows Support work", () => {
  assertEquals(hasPermission(supportSnapshot, "support.write"), true);
});

Deno.test("Support permission snapshot denies Finance", () => {
  assertEquals(hasPermission(supportSnapshot, "finance.read"), false);
  assertThrows(
    () => requirePermission(supportSnapshot, "finance.read"),
    ApiError,
  );
});

Deno.test("hidden navigation is not treated as authorization", () => {
  const forgedClientNavigation = { financeVisible: true };
  assertEquals(forgedClientNavigation.financeVisible, true);
  assertThrows(
    () => requirePermission(supportSnapshot, "finance.write"),
    ApiError,
  );
});
