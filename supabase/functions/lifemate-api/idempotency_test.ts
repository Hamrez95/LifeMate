import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  requestHash,
  requireMutationIdempotencyKey,
  shouldProtectMutation,
} from "./idempotency.ts";
import { ApiError } from "./validation.ts";

Deno.test("critical JSON mutations require idempotency protection", () => {
  assertEquals(shouldProtectMutation("POST", "/api/v1/treatment-plans"), true);
  assertEquals(
    shouldProtectMutation(
      "POST",
      "/api/v1/dose-occurrences/11111111-1111-4111-8111-111111111111/report",
    ),
    true,
  );
  assertEquals(
    shouldProtectMutation("PATCH", "/api/v1/care-events/event-id"),
    true,
  );
  assertEquals(
    shouldProtectMutation("DELETE", "/api/v1/care/relationships/relation-id"),
    true,
  );
  assertEquals(
    shouldProtectMutation("PUT", "/api/v1/women-calendar/daily-logs"),
    true,
  );
  assertEquals(shouldProtectMutation("PUT", "/api/v1/me/profile/photo"), false);
  assertEquals(shouldProtectMutation("GET", "/api/v1/treatment-plans"), false);
  assertEquals(shouldProtectMutation("POST", "/health"), false);
});

Deno.test("idempotency key header is validated consistently", () => {
  const request = new Request("https://example.test/api/v1/medications", {
    method: "POST",
    headers: { "Idempotency-Key": "11111111-1111-4111-8111-111111111111" },
  });
  assertEquals(
    requireMutationIdempotencyKey(request),
    "11111111-1111-4111-8111-111111111111",
  );

  const missing = new Request("https://example.test/api/v1/medications", {
    method: "POST",
  });
  const error = assertThrows(
    () => requireMutationIdempotencyKey(missing),
    ApiError,
  );
  assertEquals(error.code, "idempotency_key_required");
});

Deno.test("request hashing is stable and payload-sensitive", async () => {
  const first = await requestHash('{"name":"Metformin","dose":"500"}');
  const replay = await requestHash('{"name":"Metformin","dose":"500"}');
  const conflict = await requestHash('{"name":"Metformin","dose":"1000"}');
  assertEquals(first, replay);
  assertEquals(first.length, 64);
  if (first === conflict) {
    throw new Error("different payloads must not share a request hash");
  }
});
