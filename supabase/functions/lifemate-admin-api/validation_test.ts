import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import {
  ApiError,
  boundedInteger,
  normalizePath,
  requireIdempotencyKey,
  requireUuid,
} from "./validation.ts";

Deno.test("normalizes deployed Edge Function paths", () => {
  assertEquals(
    normalizePath("/functions/v1/lifemate-admin-api/api/v1/me/"),
    "/api/v1/me",
  );
});

Deno.test("bounded integer enforces server query limits", () => {
  assertEquals(boundedInteger(null, 50, 1, 200), 50);
  assertThrows(() => boundedInteger("1000", 50, 1, 200), ApiError);
});

Deno.test("UUID parsing fails closed", () => {
  assertEquals(
    requireUuid("11111111-1111-4111-8111-111111111111", "id"),
    "11111111-1111-4111-8111-111111111111",
  );
  assertThrows(() => requireUuid("not-a-uuid", "id"), ApiError);
});

Deno.test("mutations require a bounded idempotency key", () => {
  const request = new Request("https://example.test", {
    headers: { "Idempotency-Key": "bootstrap:founder:0001" },
  });
  assertEquals(requireIdempotencyKey(request), "bootstrap:founder:0001");
  assertThrows(
    () => requireIdempotencyKey(new Request("https://example.test")),
    ApiError,
  );
});
