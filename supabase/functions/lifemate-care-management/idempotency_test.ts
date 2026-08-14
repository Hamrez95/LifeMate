import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  careManagementRequestHash,
  requireCareManagementIdempotencyKey,
  shouldProtectCareManagementMutation,
} from "./idempotency.ts";

Deno.test("care-management critical mutations are protected", () => {
  assertEquals(
    shouldProtectCareManagementMutation(
      "POST",
      "/api/v1/patients/11111111-1111-4111-8111-111111111111/treatment-plans",
    ),
    true,
  );
  assertEquals(
    shouldProtectCareManagementMutation(
      "PATCH",
      "/api/v1/relationships/11111111-1111-4111-8111-111111111111/health-record-permission",
    ),
    true,
  );
  assertEquals(
    shouldProtectCareManagementMutation(
      "DELETE",
      "/api/v1/patients/11111111-1111-4111-8111-111111111111/care-events/22222222-2222-4222-8222-222222222222",
    ),
    true,
  );
  assertEquals(
    shouldProtectCareManagementMutation(
      "GET",
      "/api/v1/patients/11111111-1111-4111-8111-111111111111/treatment-plans",
    ),
    false,
  );
});

Deno.test("care-management requires the shared Idempotency-Key contract", () => {
  const request = new Request("https://example.test/api/v1/test", {
    method: "POST",
    headers: {
      "Idempotency-Key": "11111111-1111-4111-8111-111111111111",
    },
  });
  assertEquals(
    requireCareManagementIdempotencyKey(request),
    "11111111-1111-4111-8111-111111111111",
  );

  const missing = new Request("https://example.test/api/v1/test", {
    method: "POST",
  });
  const error = assertThrows(
    () => requireCareManagementIdempotencyKey(missing),
    Error,
  );
  assertEquals(error.message, "idempotency_key_required");
});

Deno.test("care-management request hashes are stable and payload-sensitive", async () => {
  const first = await careManagementRequestHash('{"version":1}');
  const replay = await careManagementRequestHash('{"version":1}');
  const conflict = await careManagementRequestHash('{"version":2}');
  assertEquals(first, replay);
  assertEquals(first.length, 64);
  if (first === conflict) throw new Error("request hash must bind the payload");
});
