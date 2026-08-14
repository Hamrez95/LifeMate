import { assertEquals, assertThrows } from "jsr:@std/assert";

import { ApiError } from "./validation.ts";
import { matchUserDetailPath } from "./user_detail.ts";

Deno.test("matches a valid User 360 account path", () => {
  assertEquals(
    matchUserDetailPath("/api/v1/users/91000000-0000-4000-8000-000000000001"),
    "91000000-0000-4000-8000-000000000001",
  );
});

Deno.test("ignores non-detail routes", () => {
  assertEquals(matchUserDetailPath("/api/v1/users"), null);
  assertEquals(matchUserDetailPath("/api/v1/users/search"), null);
});

Deno.test("rejects malformed UUID-shaped detail paths", () => {
  assertThrows(
    () =>
      matchUserDetailPath("/api/v1/users/91000000-0000-0000-0000-000000000001"),
    ApiError,
  );
});
